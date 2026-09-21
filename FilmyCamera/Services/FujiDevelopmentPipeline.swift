@preconcurrency import CoreImage
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// DR recovery runs in CIRAWFilter's linear, demosaiced sensor domain, before
/// the film transform. It pairs only with a verified shorter RAW exposure.
final class FujiLinearDRFilter: CIFilter {
    var inputImage: CIImage?
    var gain: Float = 1
    private static let shoulder = CIColorKernel(source: """
        kernel vec4 fujiDR(__sample s, float gain) {
            vec3 x = max(s.rgb, vec3(0.0));
            return vec4(gain * x / (vec3(1.0) + (gain - 1.0) * x), s.a);
        }
        """)
    override var outputImage: CIImage? {
        guard let inputImage else { return nil }
        return Self.shoulder?.apply(extent: inputImage.extent, arguments: [inputImage, gain])
    }
    static var isAvailable: Bool { shoulder != nil }
}

struct FujiDevelopedPhoto: @unchecked Sendable {
    let image: UIImage
    let data: Data
}

enum FujiDevelopmentPipeline {
    static let linearColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    static let linearContext = CIContext(options: [.workingColorSpace: linearColorSpace, .cacheIntermediates: false])

    static func centerCrop(_ image: CIImage, factor: Double, aspectRatio: Double? = nil) -> CIImage {
        let factor = FujiLimits.finite(factor, fallback: 1, in: 1...3)
        let bounds = image.extent
        var width = bounds.width / factor
        var height = bounds.height / factor
        if let ratio = aspectRatio, ratio.isFinite, ratio > 0 {
            if width / height > ratio { width = height * ratio } else { height = width / ratio }
        }
        let crop = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height).integral
            .intersection(bounds)
        return image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    static func bounded(_ image: CIImage, longEdge: Int) -> CIImage {
        let scale = min(1, CGFloat(longEdge) / max(image.extent.width, image.extent.height))
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    static func decode(_ frame: FujiSourceFrame, adjustments input: FujiDevelopmentAdjustments = .init()) throws -> CIImage {
        guard !frame.data.isEmpty, frame.data.count <= FujiLimits.maximumSourceBytes else { throw FujiCaptureError.invalidImage }
        let adjustments = input.validated()
        let image: CIImage
        if frame.metadata.sourceKind.isRAW {
            guard let raw = CIRAWFilter(imageData: frame.data, identifierHint: nil),
                  raw.nativeSize.width > 0, raw.nativeSize.height > 0,
                  raw.nativeSize.width * raw.nativeSize.height <= 100_000_000 else { throw FujiCaptureError.invalidImage }
            raw.exposure = Float(adjustments.exposureEV)
            if let temperature = adjustments.temperature { raw.neutralTemperature = Float(temperature) }
            raw.neutralTint += Float(adjustments.tint)
            if raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = Float(adjustments.noiseReduction) }
            if raw.isSharpnessSupported { raw.sharpnessAmount = Float(adjustments.sharpness) }
            if frame.metadata.dynamicRange != .dr100 {
                guard FujiLinearDRFilter.isAvailable else {
                    throw FujiCaptureError.unavailable("The linear RAW development kernel could not be created.")
                }
                raw.baselineExposure = 0
                raw.boostAmount = 0
                raw.boostShadowAmount = 0
                if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
                let protection = FujiLinearDRFilter()
                protection.gain = Float(frame.metadata.dynamicRange.gain)
                raw.linearSpaceFilter = protection
            }
            guard let output = raw.outputImage else { throw FujiCaptureError.invalidImage }
            image = output
        } else {
            guard frame.metadata.dynamicRange == .dr100 else { throw FujiCaptureError.rawUnavailable }
            guard let source = CGImageSourceCreateWithData(frame.data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue * height.doubleValue <= 100_000_000,
                  let decoded = CIImage(data: frame.data, options: [.applyOrientationProperty: true]) else {
                throw FujiCaptureError.invalidImage
            }
            var processed = decoded.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustments.exposureEV])
            if adjustments.temperature != nil || adjustments.tint != 0 {
                let temperature = adjustments.temperature ?? 6500
                processed = processed.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: temperature, y: adjustments.tint)
                ])
            }
            image = processed
        }
        guard image.extent.width.isFinite, image.extent.height.isFinite,
              image.extent.width > 0, image.extent.height > 0 else { throw FujiCaptureError.invalidImage }
        return image
    }

    static func develop(
        _ frame: FujiSourceFrame, recipe input: FilmRecipe, adjustments: FujiDevelopmentAdjustments = .init(),
        cropFactor: Double = 1, aspectRatio: Double? = nil, longEdge: Int? = nil, finish: PhotoFinish = .photo
    ) throws -> FujiDevelopedPhoto {
        var image = try decode(frame, adjustments: adjustments)
        image = centerCrop(image, factor: cropFactor, aspectRatio: aspectRatio)
        if let longEdge { image = bounded(image, longEdge: longEdge) }
        let controls = adjustments.validated()
        image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": 1 - controls.highlights * 0.5,
            "inputShadowAmount": controls.shadows
        ])
        var recipe = input
        if frame.metadata.dynamicRange != .dr100 {
            // Capture-time DR already received its matching linear development.
            recipe.dynamicRange = .dr100
            recipe.dRangePriority = .off
        }
        let filtered = FilmRenderer.render(image, recipe: recipe, quality: .photo)
        guard let finished = PhotoPrintCompositor.composedImage(filtered, finish: finish),
              let cgImage = FilmRenderer.outputCGImage(finished),
              let data = PhotoOutputEncoder.jpegData(
                for: cgImage, sourceData: frame.data, capturedAt: frame.metadata.capturedAt, recipe: input
              ) else { throw FujiCaptureError.invalidImage }
        return FujiDevelopedPhoto(image: UIImage(cgImage: cgImage), data: data)
    }

    /// Materialize in half-float linear light after every accumulation. This
    /// prevents an unbounded lazy graph and avoids gamma-space averaging.
    static func materializeLinear(_ image: CIImage) throws -> CIImage {
        guard let cgImage = linearContext.createCGImage(image, from: image.extent.integral, format: .RGBAh,
                                                      colorSpace: linearColorSpace) else { throw FujiCaptureError.invalidImage }
        return CIImage(cgImage: cgImage, options: [.colorSpace: linearColorSpace])
    }

    private static let blendKernel = CIColorKernel(source: """
        kernel vec4 fujiBlend(__sample a, __sample b, float n, float mode) {
            vec3 c;
            if (mode < 0.5) { c = (a.rgb * n + b.rgb) / (n + 1.0); }
            else if (mode < 1.5) { c = a.rgb + b.rgb; }
            else if (mode < 2.5) { c = max(a.rgb, b.rgb); }
            else { c = min(a.rgb, b.rgb); }
            return vec4(c, 1.0);
        }
        """)

    static func blend(_ accumulated: CIImage, _ next: CIImage, count: Int, mode: FujiMultipleExposureBlend) throws -> CIImage {
        let frame = CameraFrameLayout.aspectFill(next, in: accumulated.extent)
        let modeValue = Double(FujiMultipleExposureBlend.allCases.firstIndex(of: mode) ?? 0)
        guard let blended = blendKernel?.apply(extent: accumulated.extent, arguments: [accumulated, frame, Double(count), modeValue]) else {
            throw FujiCaptureError.invalidImage
        }
        return try materializeLinear(blended)
    }

    /// Merge a single focus plane without retaining the complete source set.
    static func mergeFocusPair(_ previous: CIImage, next: CIImage, sharpest: CIImage) throws -> (CIImage, CIImage) {
        let next = CameraFrameLayout.aspectFill(next, in: previous.extent)
        let measure = sharpnessMask(next)
        guard let selection = focusKernel?.apply(extent: previous.extent, arguments: [measure, sharpest]) else {
            throw FujiCaptureError.invalidImage
        }
        let feather = selection.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
            .cropped(to: previous.extent)
        let result = try materializeLinear(next.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: previous, kCIInputMaskImageKey: feather
        ]))
        let maximum = try materializeLinear(measure.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: sharpest]))
        return (result, maximum)
    }

    private static let focusKernel = CIColorKernel(source: """
        kernel vec4 fujiFocus(__sample a, __sample b) {
            float choose = step(b.r + 0.00001, a.r);
            return vec4(vec3(choose), 1.0);
        }
        """)

    static func sharpnessMask(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1])
            .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2])
            .cropped(to: image.extent)
    }

    static func encodeSource(_ image: CIImage, metadata: FujiCaptureMetadata) throws -> FujiSourceFrame {
        // A 16-bit TIFF keeps compositing data separate from the finished JPEG.
        guard let data = linearContext.tiffRepresentation(of: image, format: .RGBA16,
                                                          colorSpace: linearColorSpace, options: [:]),
              data.count <= FujiLimits.maximumSourceBytes else { throw FujiCaptureError.invalidImage }
        return FujiSourceFrame(data: data, metadata: metadata)
    }
}

enum FujiWork {
    static func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) { try Task.checkCancellation(); return try await operation() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }
}
