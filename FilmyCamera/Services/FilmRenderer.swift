import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit
import UIKit

/// Core Image renderer for live camera frames and full-resolution stills.
///
/// Each recipe gets a generated 3D color cube. The cube is cached by the
/// renderer inputs that actually affect the color transform, so exposure and
/// finishing-slider changes do not rebuild the table while the filter graph
/// remains deterministic and inspectable.
public final class FilmRenderer {
    public enum Quality: Hashable, Sendable {
        case preview
        case photo
        case export

        /// Keep one canonical transform across the live preview, still, and
        /// export paths. Quality is retained as a call-site contract so those
        /// paths can evolve independently without changing a recipe's look.
        fileprivate var cubeDimension: Int {
            switch self {
            case .preview, .photo, .export:
                return 32
            }
        }
    }

    public nonisolated(unsafe) static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// A reusable GPU-backed context for callers that need to materialize the
    /// rendered CIImage. It falls back to Core Image's software renderer on a
    /// simulator or Mac without a Metal device.
    public nonisolated(unsafe) static let sharedContext: CIContext = {
        if let metalDevice {
            return CIContext(
                mtlDevice: metalDevice,
                options: contextOptions
            )
        }

        return CIContext(options: contextOptions.merging([
            .useSoftwareRenderer: true
        ]) { _, new in new })
    }()

    private struct CubeRecipeKey: Hashable, Sendable {
        let filmBase: FilmRecipe.FilmBase
        let colorChrome: Double
        let blueResponse: Double
        let fxBlue: Double
        let palette: FilmRecipe.Palette

        init(recipe: FilmRecipe) {
            filmBase = recipe.filmBase
            colorChrome = recipe.colorChrome
            blueResponse = recipe.blueResponse
            fxBlue = recipe.fxBlue
            palette = recipe.palette
        }
    }

    private struct CubeCacheKey: Hashable, Sendable {
        let recipe: CubeRecipeKey
        let dimension: Int

        init(recipe: FilmRecipe, dimension: Int) {
            self.recipe = CubeRecipeKey(recipe: recipe)
            self.dimension = dimension
        }
    }

    private final class CubeCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [CubeCacheKey: NSData] = [:]
        private let maxEntries = 32

        func data(for key: CubeCacheKey, make: () -> NSData) -> NSData {
            lock.lock()
            if let cached = storage[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            // Cube generation is intentionally outside the lock. A recipe
            // change should not stall an already-rendering frame or another
            // thread requesting a different recipe.
            let generated = make()

            lock.lock()
            defer { lock.unlock() }

            // Another thread may have generated the same cube while this
            // thread was outside the lock. Reuse the first completed value.
            if let cached = storage[key] {
                return cached
            }

            // Slider changes can produce many distinct recipes. Keep the
            // cache bounded without making a miss affect rendered output.
            if storage.count >= maxEntries {
                storage.removeAll(keepingCapacity: true)
            }

            storage[key] = generated
            return generated
        }
    }

    private final class ImmutableResources: @unchecked Sendable {
        let randomGeneratorImage: CIImage?
        let clearImage: CIImage
        let zeroComponents: CIVector
        let oneComponents: CIVector
        let neutralWhiteBalance: CIVector

        init() {
            randomGeneratorImage = CIFilter(name: "CIRandomGenerator")?.outputImage
            clearImage = CIImage(color: .clear)
            zeroComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            oneComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            neutralWhiteBalance = CIVector(x: 6500, y: 0)
        }
    }

    private static let cubeCache = CubeCache()
    private static let immutableResources = ImmutableResources()
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    private static var contextOptions: [CIContextOption: Any] {
        var options: [CIContextOption: Any] = [
            .cacheIntermediates: false
        ]
        if let sRGBColorSpace {
            options[.workingColorSpace] = sRGBColorSpace
            options[.outputColorSpace] = sRGBColorSpace
        }
        return options
    }

    private init() {}

    /// Builds a tiny deterministic reference scene for recipe selection UI.
    /// It is deliberately synthetic rather than a bundled photograph, so the
    /// picker previews the real renderer without introducing an unlicensed
    /// image asset or pretending that one lighting condition is universal.
    public static func thumbnail(
        for recipe: FilmRecipe,
        size: CGSize = CGSize(width: 264, height: 160)
    ) -> UIImage? {
        let width = max(size.width.rounded(), 1)
        let height = max(size.height.rounded(), 1)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        var reference = CIImage(
            color: CIColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1)
        )
        .cropped(to: extent)

        let blocks: [(CGRect, CIColor)] = [
            (
                CGRect(x: 0, y: height * 0.48, width: width, height: height * 0.52),
                CIColor(red: 0.28, green: 0.47, blue: 0.58, alpha: 1)
            ),
            (
                CGRect(x: 0, y: height * 0.18, width: width, height: height * 0.30),
                CIColor(red: 0.72, green: 0.56, blue: 0.34, alpha: 1)
            ),
            (
                CGRect(x: width * 0.04, y: height * 0.16, width: width * 0.42, height: height * 0.30),
                CIColor(red: 0.15, green: 0.29, blue: 0.18, alpha: 1)
            ),
            (
                CGRect(x: width * 0.56, y: height * 0.14, width: width * 0.36, height: height * 0.24),
                CIColor(red: 0.68, green: 0.19, blue: 0.12, alpha: 1)
            ),
            (
                CGRect(x: width * 0.48, y: height * 0.48, width: width * 0.30, height: height * 0.34),
                CIColor(red: 0.66, green: 0.39, blue: 0.28, alpha: 1)
            ),
            (
                CGRect(x: width * 0.10, y: height * 0.56, width: width * 0.20, height: height * 0.22),
                CIColor(red: 0.91, green: 0.78, blue: 0.53, alpha: 1)
            ),
            (
                CGRect(x: width * 0.80, y: height * 0.56, width: width * 0.12, height: height * 0.22),
                CIColor(red: 0.86, green: 0.86, blue: 0.82, alpha: 1)
            )
        ]

        for (blockRect, color) in blocks {
            reference = CIImage(color: color)
                .cropped(to: blockRect)
                .composited(over: reference)
        }

        let rendered = render(reference, recipe: recipe, quality: .preview)
        guard let sRGBColorSpace,
              let image = sharedContext.createCGImage(
                  rendered,
                  from: extent,
                  format: .RGBA8,
                  colorSpace: sRGBColorSpace
              ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

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

        output = applyDynamicRange(to: output, recipe: recipe)
        output = applyExposureAndTone(to: output, recipe: recipe)
        output = applyWhiteBalance(to: output, recipe: recipe)
        output = applyColorControls(to: output, recipe: recipe)
        output = applyColorCube(to: output, recipe: recipe, quality: quality)
        output = applyDetailControls(to: output, recipe: recipe)
        output = applyClarity(to: output, recipe: recipe)
        output = applyGrain(to: output, recipe: recipe, quality: quality)
        output = applyVignette(to: output, recipe: recipe)
        output = applyHalation(to: output, recipe: recipe, quality: quality)
        output = clampOutput(toNormalizedRange: output)

        // Some finishing filters can expand their extent. Camera and export
        // callers expect the same bounds as the source image.
        return output.cropped(to: sourceExtent)
    }

    private static func clampOutput(toNormalizedRange image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorClamp") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(
            immutableResources.zeroComponents,
            forKey: "inputMinComponents"
        )
        filter.setValue(
            immutableResources.oneComponents,
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

    private static func applyDynamicRange(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        let amount = recipe.dynamicRange.highlightProtection
        guard amount > 0.0001,
              let filter = CIFilter(name: "CIHighlightShadowAdjust") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(-amount, forKey: "inputHighlightAmount")
        filter.setValue(amount * 0.18, forKey: "inputShadowAmount")
        return filter.outputImage?.cropped(to: image.extent) ?? image
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
        let target = CIVector(
            x: 6500 - clamp(recipe.temperatureShift, lower: -1, upper: 1) * 1800,
            y: clamp(recipe.tintShift, lower: -1, upper: 1) * 120
        )
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(immutableResources.neutralWhiteBalance, forKey: "inputNeutral")
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
        let cubeKey = CubeCacheKey(recipe: recipe, dimension: dimension)
        let cubeData = cubeCache.data(for: cubeKey) {
            makeCubeData(dimension: dimension, recipe: recipe) as NSData
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

    private static func applyDetailControls(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        var output = image

        let noiseReduction = clamp(recipe.noiseReduction, lower: 0, upper: 1)
        if noiseReduction > 0.0001,
           let noiseFilter = CIFilter(name: "CINoiseReduction") {
            noiseFilter.setValue(output, forKey: kCIInputImageKey)
            noiseFilter.setValue(noiseReduction * 0.035, forKey: "inputNoiseLevel")
            noiseFilter.setValue(1 - noiseReduction * 0.65, forKey: "inputSharpness")
            output = noiseFilter.outputImage?.cropped(to: image.extent) ?? output
        }

        let sharpness = clamp(recipe.sharpness, lower: -1, upper: 1)
        if sharpness > 0.0001,
           let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(output, forKey: kCIInputImageKey)
            unsharp.setValue(0.35 + sharpness * 0.65, forKey: kCIInputRadiusKey)
            unsharp.setValue(sharpness * 0.7, forKey: kCIInputIntensityKey)
            output = unsharp.outputImage?.cropped(to: image.extent) ?? output
        } else if sharpness < -0.0001,
                  let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(output, forKey: kCIInputImageKey)
            blur.setValue(abs(sharpness) * 0.35, forKey: kCIInputRadiusKey)
            output = blur.outputImage?.cropped(to: image.extent) ?? output
        }

        return output
    }

    private static func applyGrain(
        to image: CIImage,
        recipe: FilmRecipe,
        quality _: Quality
    ) -> CIImage {
        // Grain is part of the look, not a preview-only effect. Normalize the
        // procedural frequency to a reference image size so the same recipe
        // remains visually stable when the source changes from a video frame
        // to a full-resolution still.
        let amount = clamp(recipe.grain, lower: 0, upper: 1)
        guard amount > 0.0001,
              let random = immutableResources.randomGeneratorImage,
              let softLight = CIFilter(name: "CISoftLightBlendMode") else {
            return image
        }

        let extent = image.extent
        let referenceDimension = 1080.0
        let outputDimension = max(Double(extent.width), Double(extent.height))
        let resolutionScale = max(outputDimension / referenceDimension, 0.5)
        let grainSize = max(
            0.35,
            min(recipe.grainSize * resolutionScale, 8.0)
        )
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

    private static func applyHalation(
        to image: CIImage,
        recipe: FilmRecipe,
        quality _: Quality
    ) -> CIImage {
        let amount = clamp(recipe.halation, lower: 0, upper: 1)
        guard amount > 0.0001 else { return image }

        let extent = image.extent
        let referenceDimension = 1080.0
        let outputDimension = max(Double(extent.width), Double(extent.height))
        let resolutionScale = max(outputDimension / referenceDimension, 0.5)
        let highlightMask = image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 2.4,
                kCIInputBrightnessKey: -1.15
            ])
            .applyingFilter("CIMaskToAlpha")
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: (1.5 + amount * 4.5) * resolutionScale
            ])
            .cropped(to: extent)

        let redLayer = CIImage(
            color: CIColor(red: 1.0, green: 0.10, blue: 0.035, alpha: amount * 0.24)
        )
        .cropped(to: extent)

        let maskedLayer = redLayer.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: immutableResources.clearImage.cropped(to: extent),
            "inputMaskImage": highlightMask
        ])

        return maskedLayer
            .applyingFilter("CIScreenBlendMode", parameters: [
                kCIInputBackgroundImageKey: image
            ])
            .cropped(to: extent)
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
        let blueInfluence = Float(clamp(recipe.blueResponse + recipe.fxBlue * 0.72, lower: -1, upper: 1))
        let coolChroma = max(0, blue - max(red * 0.55, green * 0.45))
        let blueWeight = blueInfluence * (1 - luma) * max(chroma * 0.45, coolChroma) * 0.30
        mappedBlue += blueWeight
        mappedRed -= blueWeight * 0.16
        mappedGreen += blueWeight * 0.04

        let baseMapped = applyFilmBase(
            red: mappedRed,
            green: mappedGreen,
            blue: mappedBlue,
            luma: luma,
            recipe: recipe
        )

        return (
            clamp(baseMapped.red, lower: 0, upper: 1),
            clamp(baseMapped.green, lower: 0, upper: 1),
            clamp(baseMapped.blue, lower: 0, upper: 1)
        )
    }

    private static func applyFilmBase(
        red: Float,
        green: Float,
        blue: Float,
        luma: Float,
        recipe: FilmRecipe
    ) -> (red: Float, green: Float, blue: Float) {
        var mappedRed = red
        var mappedGreen = green
        var mappedBlue = blue

        func saturate(_ amount: Float) {
            mappedRed = luma + (mappedRed - luma) * amount
            mappedGreen = luma + (mappedGreen - luma) * amount
            mappedBlue = luma + (mappedBlue - luma) * amount
        }

        let shadowWeight = 1 - smoothstep(0.08, 0.62, luma)
        let highlightWeight = smoothstep(0.48, 0.98, luma)

        switch recipe.filmBase {
        case .standard, .provia:
            break
        case .classicChrome:
            saturate(0.94)
            mappedRed += 0.010 * highlightWeight
            mappedBlue += 0.012 * shadowWeight
            mappedGreen += 0.006 * shadowWeight
        case .velvia:
            saturate(1.08 + 0.06 * smoothstep(0.18, 0.92, luma))
            mappedRed += 0.010 * highlightWeight
            mappedGreen += 0.010 * (1 - shadowWeight)
            mappedBlue += 0.014 * highlightWeight
        case .astia:
            saturate(0.98)
            mappedRed += 0.012 * highlightWeight
            mappedBlue -= 0.006 * highlightWeight
        case .proNegative, .proNegStandard:
            saturate(0.97)
            mappedRed += 0.005 * highlightWeight
        case .eterna:
            saturate(0.90)
            mappedRed += 0.009 * shadowWeight
            mappedBlue += 0.012 * shadowWeight
            mappedGreen += 0.006 * shadowWeight
        case .eternaBleachBypass:
            saturate(0.72)
            mappedRed += 0.006 * highlightWeight
            mappedBlue += 0.008 * shadowWeight
        case .acros, .acrosYellow, .acrosRed, .acrosGreen, .monochrome:
            let filterBias: Float
            switch recipe.filmBase {
            case .acrosYellow: filterBias = 0.08
            case .acrosRed: filterBias = 0.13
            case .acrosGreen: filterBias = -0.06
            default: filterBias = 0
            }
            let filteredLuma = luma + filterBias * (red - blue)
            mappedRed = filteredLuma
            mappedGreen = filteredLuma
            mappedBlue = filteredLuma
        case .classicNegative:
            saturate(0.98)
            mappedRed += 0.018 * highlightWeight
            mappedBlue += 0.020 * shadowWeight
            mappedGreen -= 0.006 * shadowWeight
        case .nostalgicNegative:
            saturate(1.01)
            mappedRed += 0.022 * highlightWeight
            mappedBlue += 0.018 * shadowWeight
            mappedGreen -= 0.004 * highlightWeight
        case .realaAce:
            saturate(0.99)
            mappedBlue += 0.006 * shadowWeight
        }

        return (mappedRed, mappedGreen, mappedBlue)
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
