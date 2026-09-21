import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision

/// CIImage graphs are immutable here; the actor owns all mutable processing state.
struct FujiImage: @unchecked Sendable { let image: CIImage }
struct FujiThumbnail: @unchecked Sendable { let image: CGImage }
struct FujiRenderedImage: Sendable { let data: Data; let width: Int; let height: Int }

/// Runs before the RAW decoder's display rendering, not as a JPEG contrast trick.
/// Underexposure is provided by CameraService; this curve restores middle gray
/// while rolling the additional scene-linear highlight range into SDR output.
private final class FujiRAWLinearFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    let gain: Double
    let recovery: Double
    let shadows: Double
    init(gain: Double, recovery: Double, shadows: Double) {
        self.gain = gain; self.recovery = recovery; self.shadows = shadows
        super.init()
    }
    required init?(coder: NSCoder) { nil }
    override var outputImage: CIImage? {
        guard let inputImage else { return nil }
        return FujiImageProcessor.developLinear(inputImage, gain: gain, recovery: recovery, shadows: shadows)
    }
}

enum FujiImageProcessor {
    static let compositePixelBudget: CGFloat = 6_000_000
    static let renderPixelBudget: CGFloat = 40_000_000
    static let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    static let displaySpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let context = CIContext(options: [.workingColorSpace: linearSpace, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])

    // A continuous, unit-slope shoulder preserves a diffuse middle gray below
    // the knee. Chroma is scaled together, including saturated highlights.
    private static let developmentKernel = CIColorKernel(source: """
        kernel vec4 fujiDevelop(__sample s, float gain, float recovery, float shadows) {
            vec3 c = max(s.rgb / max(s.a, 0.00001), vec3(0.0)) * gain;
            float v = max(c.r, max(c.g, c.b));
            c *= 1.0 + shadows * pow(1.0 - clamp(v, 0.0, 1.0), 2.0);
            v = max(c.r, max(c.g, c.b));
            float knee = 0.9 - 0.6 * recovery;
            float t = max(v - knee, 0.0);
            float mapped = knee + (1.0 - knee) * t / max(t + 1.0 - knee, 0.00001);
            float scale = v > knee ? mapped / max(v, 0.00001) : 1.0;
            return vec4(c * scale * s.a, s.a);
        }
        """)
    private static let preferenceKernel = CIColorKernel(source: """
        kernel vec4 fujiSharper(__sample candidate, __sample previous) {
            float a = dot(candidate.rgb, vec3(0.2126, 0.7152, 0.0722));
            float b = dot(previous.rgb, vec3(0.2126, 0.7152, 0.0722));
            float selected = a > b * 1.03 + 0.000001 ? 1.0 : 0.0;
            return vec4(selected, selected, selected, 1.0);
        }
        """)

    static func developLinear(_ image: CIImage, gain: Double, recovery: Double, shadows: Double) -> CIImage? {
        developmentKernel?.apply(extent: image.extent, arguments: [image, gain, recovery, shadows])
    }

    static func isRAW(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String) else { return false }
        return type.conforms(to: .rawImage)
    }

    static func decoded(_ data: Data, isRAW: Bool, dynamicRange: FujiDynamicRange,
                        adjustment: FujiRAWAdjustment = .init(), maximumEdge: CGFloat? = nil) throws -> CIImage {
        guard !data.isEmpty, data.count <= FujiCaptureLibrary.maximumImportBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 100_000_000 else { throw FujiShootingError.processingFailed }
        let image: CIImage
        if isRAW {
            guard Self.isRAW(data), let raw = CIRAWFilter(imageData: data, identifierHint: nil) else {
                throw FujiShootingError.unsupportedRAW
            }
            let edit = adjustment.normalized()
            raw.exposure = Float(edit.exposure)
            raw.boostAmount = 0
            if !edit.useAsShotWhiteBalance {
                raw.neutralTemperature = Float(edit.temperature)
                raw.neutralTint = Float(edit.tint)
            }
            raw.linearSpaceFilter = FujiRAWLinearFilter(gain: pow(2, dynamicRange.protectionStops),
                                                       recovery: edit.highlightRecovery, shadows: edit.shadowLift)
            guard let result = raw.outputImage else { throw FujiShootingError.processingFailed }
            image = result
        } else {
            guard dynamicRange == .dr100, let result = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                throw FujiShootingError.unsupportedRAW
            }
            image = result
        }
        let bounded = bound(image, pixels: renderPixelBudget)
        return maximumEdge.map { bound(bounded, maximumEdge: $0) } ?? bounded
    }

    static func bound(_ image: CIImage, pixels: CGFloat) -> CIImage {
        let area = image.extent.width * image.extent.height
        guard area.isFinite, area > pixels, pixels > 0 else { return image }
        let scale = sqrt(pixels / area)
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    static func bound(_ image: CIImage, maximumEdge: CGFloat) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maximumEdge, maximumEdge > 0 else { return image }
        let scale = maximumEdge / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Crop sensor pixels without upscaling. Shared by stills, EVF and hybrid inset.
    static func crop(_ image: CIImage, factor: Double, viewport: CGSize = .zero) -> CIImage {
        let factor = CGFloat(FujiMath.finite(factor, in: 1...3, fallback: 1))
        let extent = image.extent
        let crop = CGRect(x: extent.midX - extent.width / factor / 2, y: extent.midY - extent.height / factor / 2,
                          width: extent.width / factor, height: extent.height / factor)
        let framed = viewport.width > 0 && viewport.height > 0
            ? CameraFrameLayout.aspectFillCrop(sourceExtent: crop, targetSize: viewport) : crop
        // Round inward so an edge pixel outside the requested crop is never included.
        let integral = CGRect(x: ceil(framed.minX), y: ceil(framed.minY),
                              width: floor(framed.maxX) - ceil(framed.minX), height: floor(framed.maxY) - ceil(framed.minY))
        let result = integral.width >= 1 && integral.height >= 1 ? integral : framed
        return image.cropped(to: result).transformed(by: CGAffineTransform(translationX: -result.minX, y: -result.minY))
    }

    /// Half-float, color-tagged materialization breaks a growing filter graph.
    /// Averaging/fusion is executed in linear light; FilmRenderer subsequently
    /// color-converts this image to its existing gamma-encoded working space.
    static func materialize(_ image: CIImage) throws -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: floor(image.extent.width), height: floor(image.extent.height))
        guard rect.width > 0, rect.height > 0,
              let cg = context.createCGImage(image, from: rect, format: .RGBAh, colorSpace: linearSpace) else {
            throw FujiShootingError.processingFailed
        }
        return CIImage(cgImage: cg)
    }

    static func thumbnail(_ image: CIImage, edge: CGFloat = 420) throws -> FujiThumbnail {
        let small = bound(image, maximumEdge: edge)
        guard let cg = context.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: displaySpace) else {
            throw FujiShootingError.processingFailed
        }
        return FujiThumbnail(image: cg)
    }

    static func jpeg(_ image: CIImage, recipe: FilmRecipe, originalData: Data, capturedAt: Date,
                     finish: PhotoFinish, grainSeed: UInt32) throws -> FujiRenderedImage {
        let filtered = FilmRenderer.render(image, recipe: recipe, quality: .photo, grainSeed: grainSeed)
        guard let composed = PhotoPrintCompositor.composedImage(filtered, finish: finish),
              let cg = FilmRenderer.outputCGImage(composed, from: composed.extent),
              let data = PhotoOutputEncoder.jpegData(for: cg, sourceData: originalData, capturedAt: capturedAt, recipe: recipe) else {
            throw FujiShootingError.processingFailed
        }
        return FujiRenderedImage(data: data, width: cg.width, height: cg.height)
    }

    static func blend(_ previous: CIImage, _ candidate: CIImage, count: Int, mode: FujiBlendMode) -> CIImage {
        let image: CIImage
        switch mode {
        case .average:
            image = previous.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: candidate, kCIInputTimeKey: 1.0 / Double(max(count, 2))])
        case .additive:
            image = candidate.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: previous])
        case .bright:
            image = candidate.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: previous])
        case .dark:
            image = candidate.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: previous])
        }
        // Addition must not accumulate alpha along with exposure.
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)]).cropped(to: previous.extent)
    }

    static func sharpness(_ image: CIImage) -> CIImage {
        let mono = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let edge = mono.clampedToExtent().applyingFilter("CIConvolution3X3", parameters: [
            "inputWeights": CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9), "inputBias": 0
        ])
        return edge.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: edge])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2]).cropped(to: image.extent)
    }

    static func fuse(_ previous: CIImage, score: CIImage, candidate: CIImage) throws -> (CIImage, CIImage) {
        let candidateScore = sharpness(candidate)
        guard let mask = preferenceKernel?.apply(extent: previous.extent, arguments: [candidateScore, score]) else {
            throw FujiShootingError.processingFailed
        }
        let feathered = mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.2])
            .cropped(to: previous.extent)
        let merged = candidate.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: previous, kCIInputMaskImageKey: feathered])
        let nextScore = candidateScore.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: score])
        return try (materialize(merged), materialize(nextScore))
    }
}

/// One actor per shooting controller. A sequence keeps at most one composite,
/// one focus score, one small registration reference and the current frame.
actor FujiDevelopmentWorker {
    private var composite: CIImage?
    private var score: CIImage?
    private var registrationReference: CGImage?
    private var count = 0
    private var validExtent: CGRect?

    func reset() { composite = nil; score = nil; registrationReference = nil; count = 0; validExtent = nil }

    func develop(data: Data, record: FujiOriginalRecord, finish: PhotoFinish = .photo, grainSeed: UInt32 = 0,
                 maximumEdge: CGFloat? = nil) throws -> FujiRenderedImage {
        try autoreleasepool {
            try Task.checkCancellation()
            let input = try FujiImageProcessor.decoded(data, isRAW: record.isRAW, dynamicRange: record.dynamicRange,
                                                       adjustment: record.adjustment, maximumEdge: maximumEdge)
            let image = FujiImageProcessor.crop(input, factor: record.cropFactor,
                                               viewport: CGSize(width: record.viewportWidth, height: record.viewportHeight))
            try Task.checkCancellation()
            return try FujiImageProcessor.jpeg(image, recipe: record.recipe, originalData: data, capturedAt: record.capturedAt,
                                               finish: finish, grainSeed: grainSeed)
        }
    }

    func append(data: Data, record: FujiOriginalRecord, focusStack: Bool, blendMode: FujiBlendMode) throws -> FujiThumbnail {
        try autoreleasepool {
            try Task.checkCancellation()
            let input = try FujiImageProcessor.decoded(data, isRAW: record.isRAW, dynamicRange: record.dynamicRange)
            let framed = FujiImageProcessor.crop(input, factor: record.cropFactor,
                                                viewport: CGSize(width: record.viewportWidth, height: record.viewportHeight))
            let bounded = FujiImageProcessor.bound(framed, pixels: FujiImageProcessor.compositePixelBudget)
            var image = try FujiImageProcessor.materialize(bounded)
            if let previous = composite {
                // A changed lens/resolution/aspect is never stretched into a plausible stack.
                guard abs(previous.extent.width - image.extent.width) <= 1,
                      abs(previous.extent.height - image.extent.height) <= 1 else { throw FujiShootingError.alignmentFailed }
                image = image.cropped(to: previous.extent)
                if focusStack {
                    image = try align(image, to: previous.extent)
                    guard let score else { throw FujiShootingError.processingFailed }
                    let merged = try FujiImageProcessor.fuse(previous, score: score, candidate: image)
                    composite = merged.0; self.score = merged.1
                } else {
                    composite = try FujiImageProcessor.materialize(FujiImageProcessor.blend(previous, image, count: count + 1, mode: blendMode))
                }
            } else {
                composite = image
                validExtent = image.extent
                if focusStack {
                    score = try FujiImageProcessor.materialize(FujiImageProcessor.sharpness(image))
                    registrationReference = try FujiImageProcessor.thumbnail(image, edge: 720).image
                }
            }
            count += 1
            guard let composite else { throw FujiShootingError.processingFailed }
            return try FujiImageProcessor.thumbnail(composite)
        }
    }

    /// Translation handles small tripod jitter. It does not pretend to correct
    /// parallax, subject motion or lens breathing; large motion fails explicitly.
    private func align(_ image: CIImage, to extent: CGRect) throws -> CIImage {
        guard let reference = registrationReference else { throw FujiShootingError.alignmentFailed }
        let moving = try FujiImageProcessor.thumbnail(image, edge: 720).image
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: moving, options: [:])
        try VNImageRequestHandler(cgImage: reference, options: [:]).perform([request])
        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            throw FujiShootingError.alignmentFailed
        }
        let scale = extent.width / CGFloat(reference.width)
        let transform = CGAffineTransform(translationX: observation.alignmentTransform.tx * scale,
                                         y: observation.alignmentTransform.ty * scale)
        guard transform.tx.isFinite, transform.ty.isFinite,
              abs(transform.tx) <= extent.width * 0.05, abs(transform.ty) <= extent.height * 0.05 else {
            throw FujiShootingError.alignmentFailed
        }
        let moved = image.transformed(by: transform)
        validExtent = (validExtent ?? extent).intersection(moved.extent).intersection(extent)
        guard let validExtent, validExtent.width > extent.width * 0.85, validExtent.height > extent.height * 0.85 else {
            throw FujiShootingError.alignmentFailed
        }
        return moved.clampedToExtent().cropped(to: extent)
    }

    func finish(recipe: FilmRecipe, sourceData: Data, capturedAt: Date, finish: PhotoFinish, grainSeed: UInt32) throws -> FujiRenderedImage {
        try autoreleasepool {
            guard let composite else { throw FujiShootingError.processingFailed }
            let extent = validExtent ?? composite.extent
            let image = composite.cropped(to: extent).transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            return try FujiImageProcessor.jpeg(image, recipe: recipe, originalData: sourceData, capturedAt: capturedAt,
                                               finish: finish, grainSeed: grainSeed)
        }
    }
}
