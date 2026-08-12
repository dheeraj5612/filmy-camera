import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit

/// Core Image renderer for live camera frames and full-resolution stills.
///
/// Each recipe gets a generated 3D color cube. The cube is cached by the
/// recipe's complete value and quality tier, so live frames do not rebuild the
/// table while the filter graph remains deterministic and inspectable.
public final class FilmRenderer {
    public enum Quality: Hashable, Sendable {
        case preview
        case photo
        case export

        fileprivate var cubeDimension: Int {
            switch self {
            case .preview:
                return 16
            case .photo:
                return 32
            case .export:
                return 48
            }
        }

        fileprivate var grainScale: Double {
            switch self {
            case .preview:
                return 0.72
            case .photo, .export:
                return 1
            }
        }
    }

    public static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// A reusable GPU-backed context for callers that need to materialize the
    /// rendered CIImage. It falls back to Core Image's software renderer on a
    /// simulator or Mac without a Metal device.
    public static let sharedContext: CIContext = {
        if let metalDevice {
            return CIContext(
                mtlDevice: metalDevice,
                options: [.cacheIntermediates: false]
            )
        }

        return CIContext(options: [.useSoftwareRenderer: true])
    }()

    private final class CubeCache: @unchecked Sendable {
        let storage = NSCache<NSString, NSData>()
    }

    private static let cubeCache = CubeCache()
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    private init() {}

    /// Applies the selected look to a CIImage. The returned image remains a
    /// CIImage so the caller can render it directly into a Metal texture or a
    /// full-resolution photo buffer without an unnecessary CPU round-trip.
    public static func render(
        _ image: CIImage,
        recipe: FilmRecipe,
        quality: Quality = .preview
    ) -> CIImage {
        guard !image.extent.isEmpty else { return image }

        let sourceExtent = image.extent
        var output = image

        output = applyExposureAndTone(to: output, recipe: recipe)
        output = applyWhiteBalance(to: output, recipe: recipe)
        output = applyColorControls(to: output, recipe: recipe)
        output = applyColorCube(to: output, recipe: recipe, quality: quality)
        output = applyClarity(to: output, recipe: recipe)
        output = applyGrain(to: output, recipe: recipe, quality: quality)
        output = applyVignette(to: output, recipe: recipe)
        output = clampOutput(toNormalizedRange: output)

        // Some finishing filters can expand their extent. Camera and export
        // callers expect the same bounds as the source image.
        return output.cropped(to: sourceExtent)
    }

    private static func clampOutput(toNormalizedRange image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorClamp") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(
            CIVector(x: 0, y: 0, z: 0, w: 0),
            forKey: "inputMinComponents"
        )
        filter.setValue(
            CIVector(x: 1, y: 1, z: 1, w: 1),
            forKey: "inputMaxComponents"
        )
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func applyExposureAndTone(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        var output = image

        if abs(recipe.exposure) > 0.0001,
           let exposure = CIFilter(name: "CIExposureAdjust") {
            exposure.setValue(output, forKey: kCIInputImageKey)
            exposure.setValue(recipe.exposure, forKey: kCIInputEVKey)
            output = exposure.outputImage ?? output
        }

        guard abs(recipe.highlightTone) > 0.0001 || abs(recipe.shadowTone) > 0.0001,
              let toneCurve = CIFilter(name: "CIToneCurve") else {
            return output
        }

        let shadow = clamp(recipe.shadowTone, lower: -1, upper: 1)
        let highlight = clamp(recipe.highlightTone, lower: -1, upper: 1)
        let points: [(CGFloat, CGFloat)] = [
            (0, clamp(0 + shadow * 0.10, lower: 0, upper: 1)),
            (0.25, clamp(0.25 + shadow * 0.055, lower: 0, upper: 1)),
            (0.50, clamp(0.50 + (shadow + highlight) * 0.018, lower: 0, upper: 1)),
            (0.75, clamp(0.75 + highlight * 0.055, lower: 0, upper: 1)),
            (1, clamp(1 + highlight * 0.10, lower: 0, upper: 1))
        ]

        toneCurve.setValue(output, forKey: kCIInputImageKey)
        for (index, point) in points.enumerated() {
            toneCurve.setValue(
                CIVector(x: point.0, y: point.1),
                forKey: "inputPoint\(index)"
            )
        }
        return toneCurve.outputImage ?? output
    }

    private static func applyWhiteBalance(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        guard abs(recipe.temperatureShift) > 0.0001 || abs(recipe.tintShift) > 0.0001,
              let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }

        // CITemperatureAndTint works in Kelvin/tint units. The model keeps
        // recipe controls normalized so they are easy to expose as sliders.
        let neutral = CIVector(x: 6500, y: 0)
        let target = CIVector(
            x: 6500 - clamp(recipe.temperatureShift, lower: -1, upper: 1) * 1800,
            y: clamp(recipe.tintShift, lower: -1, upper: 1) * 120
        )
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(neutral, forKey: "inputNeutral")
        filter.setValue(target, forKey: "inputTargetNeutral")
        return filter.outputImage ?? image
    }

    private static func applyColorControls(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else { return image }
        controls.setValue(image, forKey: kCIInputImageKey)
        controls.setValue(clamp(recipe.saturation, lower: 0, upper: 2), forKey: kCIInputSaturationKey)
        controls.setValue(clamp(recipe.contrast, lower: 0.5, upper: 1.7), forKey: kCIInputContrastKey)
        controls.setValue(0, forKey: kCIInputBrightnessKey)
        return controls.outputImage ?? image
    }

    private static func applyColorCube(
        to image: CIImage,
        recipe: FilmRecipe,
        quality: Quality
    ) -> CIImage {
        guard let cube = CIFilter(name: "CIColorCubeWithColorSpace") else { return image }

        let dimension = quality.cubeDimension
        let cubeKey = "\(recipe.hashValue)-\(dimension)" as NSString
        let cubeData: NSData
        if let cached = cubeCache.storage.object(forKey: cubeKey) {
            cubeData = cached
        } else {
            let generated = makeCubeData(dimension: dimension, recipe: recipe)
            cubeData = generated as NSData
            cubeCache.storage.setObject(cubeData, forKey: cubeKey)
        }

        cube.setValue(image, forKey: kCIInputImageKey)
        cube.setValue(cubeData, forKey: "inputCubeData")
        cube.setValue(dimension, forKey: "inputCubeDimension")
        if let sRGBColorSpace {
            cube.setValue(sRGBColorSpace, forKey: "inputColorSpace")
        }
        return cube.outputImage ?? image
    }

    private static func applyClarity(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        let clarity = clamp(recipe.clarity, lower: -1, upper: 1)
        guard abs(clarity) > 0.0001 else { return image }

        if clarity > 0, let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(image, forKey: kCIInputImageKey)
            unsharp.setValue(0.8 + clarity * 1.3, forKey: kCIInputRadiusKey)
            unsharp.setValue(clarity * 0.85, forKey: kCIInputIntensityKey)
            return unsharp.outputImage?.cropped(to: image.extent) ?? image
        }

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        blur.setValue(image, forKey: kCIInputImageKey)
        blur.setValue(abs(clarity) * 0.65, forKey: kCIInputRadiusKey)
        return blur.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func applyGrain(
        to image: CIImage,
        recipe: FilmRecipe,
        quality: Quality
    ) -> CIImage {
        let amount = clamp(recipe.grain * quality.grainScale, lower: 0, upper: 1)
        guard amount > 0.0001,
              let random = CIFilter(name: "CIRandomGenerator")?.outputImage,
              let softLight = CIFilter(name: "CISoftLightBlendMode") else {
            return image
        }

        let extent = image.extent
        let grainSize = max(0.35, min(recipe.grainSize, 2.5))
        let noise = random
            .transformed(by: CGAffineTransform(scaleX: 1 / grainSize, y: 1 / grainSize))
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.45,
                kCIInputBrightnessKey: -0.50
            ])

        softLight.setValue(noise, forKey: kCIInputImageKey)
        softLight.setValue(image, forKey: kCIInputBackgroundImageKey)
        guard let grainImage = softLight.outputImage?.cropped(to: extent),
              let maskFilter = CIFilter(name: "CIBlendWithAlphaMask") else {
            return image
        }

        let maskColor = CIColor(red: 1, green: 1, blue: 1, alpha: amount)
        let mask = CIImage(color: maskColor).cropped(to: extent)
        maskFilter.setValue(grainImage, forKey: kCIInputImageKey)
        maskFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        maskFilter.setValue(mask, forKey: "inputMaskImage")
        return maskFilter.outputImage?.cropped(to: extent) ?? image
    }

    private static func applyVignette(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        let intensity = clamp(recipe.vignette, lower: 0, upper: 1)
        guard intensity > 0.0001,
              let vignette = CIFilter(name: "CIVignette") else {
            return image
        }

        let extent = image.extent
        vignette.setValue(image, forKey: kCIInputImageKey)
        vignette.setValue(intensity * 1.35, forKey: kCIInputIntensityKey)
        vignette.setValue(max(extent.width, extent.height) * 0.62, forKey: kCIInputRadiusKey)
        return vignette.outputImage?.cropped(to: extent) ?? image
    }

    private static func makeCubeData(
        dimension: Int,
        recipe: FilmRecipe
    ) -> Data {
        var values: [Float] = []
        values.reserveCapacity(dimension * dimension * dimension * 4)

        let divisor = Float(dimension - 1)
        for blueIndex in 0..<dimension {
            for greenIndex in 0..<dimension {
                for redIndex in 0..<dimension {
                    let red = Float(redIndex) / divisor
                    let green = Float(greenIndex) / divisor
                    let blue = Float(blueIndex) / divisor
                    let mapped = mapColor(red: red, green: green, blue: blue, recipe: recipe)
                    values.append(mapped.red)
                    values.append(mapped.green)
                    values.append(mapped.blue)
                    values.append(1)
                }
            }
        }

        return values.withUnsafeBytes { rawBuffer in
            Data(bytes: rawBuffer.baseAddress!, count: rawBuffer.count)
        }
    }

    private static func mapColor(
        red: Float,
        green: Float,
        blue: Float,
        recipe: FilmRecipe
    ) -> (red: Float, green: Float, blue: Float) {
        let palette = recipe.palette
        let luma = red * 0.2126 + green * 0.7152 + blue * 0.0722
        let chroma = max(red, max(green, blue)) - min(red, min(green, blue))

        var mappedRed = red + Float(palette.redBias)
            + Float(palette.redGreenMix) * (green - luma)
        var mappedGreen = green + Float(palette.greenBias)
            + Float(palette.greenBlueMix) * (blue - luma)
        var mappedBlue = blue + Float(palette.blueBias)
            + Float(palette.blueRedMix) * (red - luma)

        let paletteSaturation = Float(clamp(palette.saturation, lower: 0, upper: 1.5))
        mappedRed = luma + (mappedRed - luma) * paletteSaturation
        mappedGreen = luma + (mappedGreen - luma) * paletteSaturation
        mappedBlue = luma + (mappedBlue - luma) * paletteSaturation

        // Color Chrome-style compression protects highly saturated highlights
        // without turning the whole image gray.
        let highlightWeight = smoothstep(0.30, 0.92, luma)
        let compression = Float(clamp(recipe.colorChrome, lower: 0, upper: 1))
            * highlightWeight
            * chroma
            * 0.30
        mappedRed = mix(mappedRed, luma + (mappedRed - luma) * 0.72, compression)
        mappedGreen = mix(mappedGreen, luma + (mappedGreen - luma) * 0.72, compression)
        mappedBlue = mix(mappedBlue, luma + (mappedBlue - luma) * 0.72, compression)

        // Blue-response controls primarily affect cool shadows/highlights,
        // keeping skin and warm midtones stable.
        let blueWeight = Float(recipe.blueResponse) * (1 - luma) * chroma * 0.18
        mappedBlue += blueWeight
        mappedRed -= blueWeight * 0.16
        mappedGreen += blueWeight * 0.04

        return (
            clamp(mappedRed, lower: 0, upper: 1),
            clamp(mappedGreen, lower: 0, upper: 1),
            clamp(mappedBlue, lower: 0, upper: 1)
        )
    }

    private static func mix(_ lhs: Float, _ rhs: Float, _ amount: Float) -> Float {
        lhs + (rhs - lhs) * clamp(amount, lower: 0, upper: 1)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let normalized = clamp((value - edge0) / (edge1 - edge0), lower: 0, upper: 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private static func clamp<T: Comparable>(
        _ value: T,
        lower: T,
        upper: T
    ) -> T {
        min(max(value, lower), upper)
    }
}
