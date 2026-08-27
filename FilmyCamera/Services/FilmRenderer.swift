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

    // Xcode 16.4's SDK annotations do not model these immutable handles as
    // Sendable. They are initialized once and never mutated after creation.
    // Keep the explicit opt-out until the minimum hosted toolchain catches up.
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
        private final class Key: NSObject {
            let value: CubeCacheKey

            init(_ value: CubeCacheKey) {
                self.value = value
            }

            override var hash: Int { value.hashValue }

            override func isEqual(_ object: Any?) -> Bool {
                guard let other = object as? Key else { return false }
                return value == other.value
            }
        }

        private let storage = NSCache<Key, NSData>()

        init() {
            // One 32³ RGBA float cube is about 512 KB. The count accommodates
            // every built-in recipe without the previous browse-to-clear
            // thrash, while the cost limit lets NSCache react to memory
            // pressure before exploratory editor values grow unbounded.
            storage.countLimit = 48
            storage.totalCostLimit = 28 * 1024 * 1024
        }

        func data(for key: CubeCacheKey, make: () -> NSData) -> NSData {
            let wrappedKey = Key(key)
            if let cached = storage.object(forKey: wrappedKey) {
                return cached
            }

            // NSCache is thread-safe. Keep cube generation outside its own
            // synchronization so distinct recipes can be prepared in
            // parallel and a thumbnail miss cannot stall the live preview.
            let generated = make()

            // Another thread may have generated the same cube while this
            // thread was working. Reuse that value when available.
            if let cached = storage.object(forKey: wrappedKey) {
                return cached
            }

            storage.setObject(generated, forKey: wrappedKey, cost: generated.length)
            return generated
        }
    }

    private struct ThumbnailCacheKey: Hashable, Sendable {
        let recipe: FilmRecipe
        let width: Int
        let height: Int
    }

    private final class ThumbnailCache: @unchecked Sendable {
        private final class Key: NSObject {
            let value: ThumbnailCacheKey

            init(_ value: ThumbnailCacheKey) {
                self.value = value
            }

            override var hash: Int { value.hashValue }

            override func isEqual(_ object: Any?) -> Bool {
                guard let other = object as? Key else { return false }
                return value == other.value
            }
        }

        private let storage = NSCache<Key, UIImage>()

        init() {
            storage.countLimit = 48
            storage.totalCostLimit = 12 * 1024 * 1024
        }

        func image(for key: ThumbnailCacheKey) -> UIImage? {
            storage.object(forKey: Key(key))
        }

        func insert(_ image: UIImage, for key: ThumbnailCacheKey) -> UIImage {
            let wrappedKey = Key(key)
            if let cached = storage.object(forKey: wrappedKey) {
                return cached
            }
            let pixelCost = max(key.width * key.height * 4, 1)
            storage.setObject(image, forKey: wrappedKey, cost: pixelCost)
            return image
        }
    }

    private final class ImmutableResources: @unchecked Sendable {
        let grainTexture: CIImage?
        let grainKernel: CIColorKernel?
        let clearImage: CIImage
        let zeroComponents: CIVector
        let oneComponents: CIVector
        let alphaVector: CIVector
        let neutralWhiteBalance: CIVector

        init() {
            grainTexture = FilmRenderer.makeDeterministicGrainTexture()
            grainKernel = CIColorKernel(source: """
                kernel vec4 filmyGrain(__sample image, __sample noise, float amplitude) {
                    float delta = (noise.r - 0.5) * amplitude;
                    return vec4(clamp(image.rgb + vec3(delta), 0.0, 1.0), image.a);
                }
                """)
            clearImage = CIImage(color: .clear)
            zeroComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            oneComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            alphaVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            neutralWhiteBalance = CIVector(x: 6500, y: 0)
        }
    }

    private static let cubeCache = CubeCache()
    private static let thumbnailCache = ThumbnailCache()
    private static let immutableResources = ImmutableResources()
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private static let spatialReferenceDimension: CGFloat = 1080

    /// A default is still useful for deterministic thumbnails and tests. Live
    /// camera sessions supply their own phase through CameraService so the
    /// preview and captured still use the same grain arrangement.
    public static let canonicalGrainSeed: UInt32 = 0

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
        let cacheKey = ThumbnailCacheKey(
            recipe: recipe,
            width: Int(width),
            height: Int(height)
        )
        if let cached = thumbnailCache.image(for: cacheKey) {
            return cached
        }
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
            ),
            (
                CGRect(x: width * 0.33, y: height * 0.57, width: width * 0.12, height: height * 0.18),
                CIColor(red: 0.69, green: 0.18, blue: 0.58, alpha: 1)
            ),
            (
                CGRect(x: width * 0.80, y: height * 0.80, width: width * 0.12, height: height * 0.14),
                CIColor(red: 0.43, green: 0.44, blue: 0.45, alpha: 1)
            )
        ]

        for (blockRect, color) in blocks {
            reference = CIImage(color: color)
                .cropped(to: blockRect)
                .composited(over: reference)
        }

        let rendered = render(reference, recipe: recipe, quality: .preview)
        guard let image = outputCGImage(rendered, from: extent) else {
            return nil
        }
        return thumbnailCache.insert(UIImage(cgImage: image), for: cacheKey)
    }

    /// Materializes a display-referred still at the app's explicit output
    /// boundary. Keeping this in one place prevents a caller from relying on
    /// Core Image's implicit color-space choice when it creates a CGImage.
    public static func outputCGImage(
        _ image: CIImage,
        from extent: CGRect? = nil
    ) -> CGImage? {
        guard let sRGBColorSpace else { return nil }
        return sharedContext.createCGImage(
            image,
            from: extent ?? image.extent,
            format: .RGBA8,
            colorSpace: sRGBColorSpace
        )
    }

    /// Applies the selected look to a CIImage. The returned image remains a
    /// CIImage so the caller can render it directly into a Metal texture or a
    /// full-resolution photo buffer without an unnecessary CPU round-trip.
    public static func render(
        _ image: CIImage,
        recipe: FilmRecipe,
        quality: Quality = .preview,
        grainSeed: UInt32 = canonicalGrainSeed,
        grainPhase: CGPoint? = nil
    ) -> CIImage {
        guard !image.extent.isEmpty else { return image }

        let sourceExtent = image.extent
        let safeRecipe = sanitizedRecipe(recipe)
        // Core Image's blend stages can operate on premultiplied alpha. Work
        // on an opaque copy, then restore the source alpha once at the end so
        // a transparent input is not multiplied repeatedly by finishing FX.
        let processingImage = opaqueImage(from: image)
        var output = processingImage

        output = applyDynamicRange(to: output, recipe: safeRecipe)
        output = applyExposureAndTone(to: output, recipe: safeRecipe)
        output = applyCompactDigitalTone(to: output, recipe: safeRecipe)
        output = applyWhiteBalance(to: output, recipe: safeRecipe)
        output = applyMonochromeFilter(to: output, recipe: safeRecipe)
        output = applyColorControls(to: output, recipe: safeRecipe)
        output = applyColorCube(to: output, recipe: safeRecipe, quality: quality)
        output = applyMonochromaticColorAxes(to: output, recipe: safeRecipe)
        output = applyDetailControls(to: output, recipe: safeRecipe)
        output = applyClarity(to: output, recipe: safeRecipe)
        // Halation is light scattered inside the film stack, so derive its
        // highlight mask before adding the final grain texture. Otherwise the
        // synthetic grain itself can create or modulate red highlight bloom.
        output = applyHalation(to: output, recipe: safeRecipe, quality: quality)
        output = applyGrain(
            to: output,
            recipe: safeRecipe,
            quality: quality,
            seed: grainSeed,
            phase: grainPhase
        )
        output = applyVignette(to: output, recipe: safeRecipe)
        output = clampOutput(toNormalizedRange: output)
        output = restoreAlpha(of: output, from: image)

        // Some finishing filters can expand their extent. Camera and export
        // callers expect the same bounds as the source image.
        return output.cropped(to: sourceExtent)
    }

    /// The renderer is also used for decoded drafts and future import paths.
    /// Sanitize at the render boundary so NaN or infinity can never reach a
    /// Core Image filter or the color-cube cache.
    private static func sanitizedRecipe(_ recipe: FilmRecipe) -> FilmRecipe {
        var safe = recipe

        func value(_ raw: Double, _: FilmRecipe.Control, neutral: Double) -> Double {
            // Preserve finite exploratory drafts. Each renderer stage applies
            // its own defensive bounds; only non-finite values need a neutral
            // replacement at this boundary.
            raw.isFinite ? raw : neutral
        }

        safe.exposure = value(recipe.exposure, .exposure, neutral: 0)
        safe.tone = FilmRecipe.Tone(
            highlight: value(recipe.tone.highlight, .highlights, neutral: 0),
            shadow: value(recipe.tone.shadow, .shadows, neutral: 0)
        )
        safe.saturation = value(recipe.saturation, .color, neutral: 1)
        safe.contrast = value(recipe.contrast, .contrast, neutral: 1)
        safe.whiteBalance = FilmRecipe.WhiteBalanceShift(
            temperature: value(recipe.whiteBalance.temperature, .temperature, neutral: 0),
            tint: value(recipe.whiteBalance.tint, .tint, neutral: 0),
            mode: recipe.whiteBalance.mode,
            kelvin: value(recipe.whiteBalance.kelvin, .colorTemperature, neutral: 6500)
        )
        safe.monochromaticColor = FilmRecipe.MonochromaticColor(
            warmCool: value(recipe.monochromaticColor.warmCool, .monochromaticWarmCool, neutral: 0),
            greenMagenta: value(recipe.monochromaticColor.greenMagenta, .monochromaticGreenMagenta, neutral: 0)
        )
        safe.colorChrome = value(recipe.colorChrome, .colorChrome, neutral: 0)
        safe.blueResponse = value(recipe.blueResponse, .blueResponse, neutral: 0)
        // FX Blue is a public Off/Weak/Strong control. Older saved recipes
        // could contain a signed negative scalar; preserve their readability
        // but normalize those legacy values to the current Off state.
        safe.fxBlue = max(value(recipe.fxBlue, .fxBlue, neutral: 0), 0)
        safe.sharpness = value(recipe.sharpness, .sharpness, neutral: 0)
        safe.noiseReduction = value(recipe.noiseReduction, .noiseReduction, neutral: 0)
        safe.clarity = value(recipe.clarity, .clarity, neutral: 0)
        safe.grain = value(recipe.grain, .grain, neutral: 0)
        safe.grainSize = value(recipe.grainSize, .grainSize, neutral: 1)
        safe.vignette = value(recipe.vignette, .vignette, neutral: 0)
        safe.halation = value(recipe.halation, .halation, neutral: 0)
        safe.palette = FilmRecipe.Palette(
            redBias: value(recipe.palette.redBias, .paletteRedBias, neutral: 0),
            greenBias: value(recipe.palette.greenBias, .paletteGreenBias, neutral: 0),
            blueBias: value(recipe.palette.blueBias, .paletteBlueBias, neutral: 0),
            redGreenMix: value(recipe.palette.redGreenMix, .paletteRedGreenMix, neutral: 0),
            greenBlueMix: value(recipe.palette.greenBlueMix, .paletteGreenBlueMix, neutral: 0),
            blueRedMix: value(recipe.palette.blueRedMix, .paletteBlueRedMix, neutral: 0),
            saturation: value(recipe.palette.saturation, .paletteSaturation, neutral: 1)
        )
        return safe
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

    static func opaqueImage(from image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        // CIImage buffers are premultiplied by default. Recover straight RGB
        // before replacing alpha, otherwise translucent source colors remain
        // darkened when the working image becomes opaque.
        filter.setValue(image.unpremultiplyingAlpha(), forKey: kCIInputImageKey)
        // Replace alpha with 1 rather than adding a unit bias to the source
        // alpha. The default alpha vector would otherwise turn an opaque
        // source into alpha 2 before blend-based finishing effects run.
        filter.setValue(immutableResources.zeroComponents, forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func restoreAlpha(of image: CIImage, from source: CIImage) -> CIImage {
        guard let alpha = CIFilter(name: "CIColorMatrix"),
              let blend = CIFilter(name: "CIBlendWithAlphaMask") else {
            return image
        }

        alpha.setValue(source, forKey: kCIInputImageKey)
        alpha.setValue(immutableResources.zeroComponents, forKey: "inputRVector")
        alpha.setValue(immutableResources.zeroComponents, forKey: "inputGVector")
        alpha.setValue(immutableResources.zeroComponents, forKey: "inputBVector")
        alpha.setValue(immutableResources.alphaVector, forKey: "inputAVector")

        guard let alphaImage = alpha.outputImage?.cropped(to: source.extent) else {
            return image
        }

        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(immutableResources.clearImage.cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        blend.setValue(alphaImage, forKey: "inputMaskImage")
        return blend.outputImage?.cropped(to: image.extent) ?? image
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
        // The public camera convention uses positive tone values for a harder
        // curve: highlights and shadows move down. Keep that polarity in the
        // model instead of silently inverting the user's control.
        let shadowDelta = -shadow
        let highlightDelta = -highlight
        let points: [(CGFloat, CGFloat)] = [
            (0, clamp(0 + shadowDelta * 0.10, lower: 0, upper: 1)),
            (0.25, clamp(0.25 + shadowDelta * 0.055, lower: 0, upper: 1)),
            (0.50, clamp(0.50 + (shadowDelta + highlightDelta) * 0.018, lower: 0, upper: 1)),
            (0.75, clamp(0.75 + highlightDelta * 0.055, lower: 0, upper: 1)),
            (1, clamp(1 + highlightDelta * 0.10, lower: 0, upper: 1))
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
        let amount = max(
            recipe.dynamicRange.highlightProtection,
            recipe.dRangePriority.highlightProtection
        )
        guard amount > 0.0001,
              let filter = CIFilter(name: "CIHighlightShadowAdjust") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        // CIHighlightShadowAdjust uses 1 as the identity highlight amount and
        // lower values for stronger protection. The recipe value is a
        // monotonic strength, so invert it before crossing the API boundary.
        let highlightAmount = clamp(1 - amount, lower: 0, upper: 1)
        filter.setValue(highlightAmount, forKey: "inputHighlightAmount")
        filter.setValue(amount * 0.18, forKey: "inputShadowAmount")
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func applyCompactDigitalTone(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        guard recipe.filmBase == .compactDigital,
              let toneCurve = CIFilter(name: "CIToneCurve") else {
            return image
        }

        // A dedicated compact-JPEG curve complements the editable recipe
        // controls. It keeps black anchored, opens useful shadow/midtone
        // detail, and eases into a gentle highlight shoulder. The points are
        // an original approximation of the public Standard Picture Style and
        // automatic-lighting intent, not Canon calibration data.
        let points: [(CGFloat, CGFloat)] = [
            (0.00, 0.006),
            (0.18, 0.205),
            (0.50, 0.545),
            (0.80, 0.825),
            (1.00, 0.995)
        ]

        toneCurve.setValue(image, forKey: kCIInputImageKey)
        for (index, point) in points.enumerated() {
            toneCurve.setValue(
                CIVector(x: point.0, y: point.1),
                forKey: "inputPoint\(index)"
            )
        }
        return toneCurve.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func applyWhiteBalance(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        let temperatureShift = recipe.temperatureShift + recipe.whiteBalance.mode.temperatureBias
        let tintShift = recipe.tintShift + recipe.whiteBalance.mode.tintBias
        let baseKelvin = recipe.whiteBalance.mode == .colorTemperature
            ? clamp(recipe.whiteBalance.kelvin, lower: 2500, upper: 10000)
            : 6500
        let targetKelvin = clamp(
            baseKelvin - clamp(temperatureShift, lower: -1, upper: 1) * 1800,
            lower: 2500,
            upper: 10000
        )
        guard abs(targetKelvin - 6500) > 0.0001 || abs(tintShift) > 0.0001,
              let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }

        // CITemperatureAndTint works in Kelvin/tint units. The model keeps
        // fine-tuning controls normalized so they are easy to expose as
        // sliders, while the explicit Color Temperature mode stores Kelvin.
        // Core Image's tint axis is positive toward green; the recipe model
        // follows camera terminology where positive tint means magenta.
        let target = CIVector(
            x: targetKelvin,
            y: -clamp(tintShift, lower: -1, upper: 1) * 120
        )
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(immutableResources.neutralWhiteBalance, forKey: "inputNeutral")
        filter.setValue(target, forKey: "inputTargetNeutral")
        return filter.outputImage ?? image
    }

    private static func applyMonochromeFilter(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        guard let monochromeFilter = recipe.filmBase.monochromeFilter,
              let filter = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        let weights = monochromeFilter.channelWeights
        let vector = CIVector(
            x: weights.red,
            y: weights.green,
            z: weights.blue,
            w: 0
        )
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(vector, forKey: "inputRVector")
        filter.setValue(vector, forKey: "inputGVector")
        filter.setValue(vector, forKey: "inputBVector")
        filter.setValue(immutableResources.alphaVector, forKey: "inputAVector")
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    /// Applies the public monochromatic warm/cool and green/magenta controls
    /// after the film base has produced its luminance. The matrix uses the
    /// current output luminance as the tint carrier, so a neutral ACROS or
    /// MONOCHROME base remains neutral while SEPIA keeps its base tone and
    /// receives the same predictable axis behavior.
    private static func applyMonochromaticColorAxes(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        guard isMonochromaticBase(recipe.filmBase),
              let filter = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        let warmCool = CGFloat(clamp(
            recipe.monochromaticColor.warmCool,
            lower: -1,
            upper: 1
        ))
        let greenMagenta = CGFloat(clamp(
            recipe.monochromaticColor.greenMagenta,
            lower: -1,
            upper: 1
        ))
        guard abs(warmCool) > 0.0001 || abs(greenMagenta) > 0.0001 else {
            return image
        }

        // These opponent directions are normalized against display-referred
        // sRGB luminance. Positive values mean warm and magenta; negative
        // values mean cool and green. The coefficients keep the weighted
        // luma unchanged before the final safety clamp.
        let lumaRed: CGFloat = 0.2126
        let lumaGreen: CGFloat = 0.7152
        let lumaBlue: CGFloat = 0.0722
        let warmRedPerLuma: CGFloat = 0.06
        let warmBluePerLuma = -warmRedPerLuma * lumaRed / lumaBlue
        let magentaRedBluePerLuma: CGFloat = 0.12
        let magentaGreenPerLuma = -magentaRedBluePerLuma * (lumaRed + lumaBlue) / lumaGreen

        let redDeltaPerLuma = warmCool * warmRedPerLuma
            + greenMagenta * magentaRedBluePerLuma
        let greenDeltaPerLuma = greenMagenta * magentaGreenPerLuma
        let blueDeltaPerLuma = warmCool * warmBluePerLuma
            + greenMagenta * magentaRedBluePerLuma

        let redVector = CIVector(
            x: 1 + redDeltaPerLuma * lumaRed,
            y: redDeltaPerLuma * lumaGreen,
            z: redDeltaPerLuma * lumaBlue,
            w: 0
        )
        let greenVector = CIVector(
            x: greenDeltaPerLuma * lumaRed,
            y: 1 + greenDeltaPerLuma * lumaGreen,
            z: greenDeltaPerLuma * lumaBlue,
            w: 0
        )
        let blueVector = CIVector(
            x: blueDeltaPerLuma * lumaRed,
            y: blueDeltaPerLuma * lumaGreen,
            z: 1 + blueDeltaPerLuma * lumaBlue,
            w: 0
        )

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(redVector, forKey: "inputRVector")
        filter.setValue(greenVector, forKey: "inputGVector")
        filter.setValue(blueVector, forKey: "inputBVector")
        filter.setValue(immutableResources.alphaVector, forKey: "inputAVector")
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func isMonochromaticBase(_ filmBase: FilmRecipe.FilmBase) -> Bool {
        filmBase.supportsMonochromaticColorAxes
    }

    private static func applyColorControls(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else { return image }
        controls.setValue(image, forKey: kCIInputImageKey)
        // The matrix above has already produced the monochrome response. Do
        // not let a legacy saturation value of zero erase that channel mix.
        let saturation = recipe.filmBase.monochromeFilter == nil
            ? clamp(recipe.saturation, lower: 0, upper: 2)
            : 1
        controls.setValue(saturation, forKey: kCIInputSaturationKey)
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
            unsharp.setValue(
                spatialRadius(0.8 + clarity * 1.3, for: image.extent),
                forKey: kCIInputRadiusKey
            )
            unsharp.setValue(clarity * 0.85, forKey: kCIInputIntensityKey)
            return unsharp.outputImage?.cropped(to: image.extent) ?? image
        }

        // CIUnsharpMask's intensity contract is non-negative. A negative
        // value is ignored by Core Image on current runtimes, so implement
        // negative clarity as a supported local blur/original blend instead.
        guard let blur = CIFilter(name: "CIGaussianBlur"),
              let blend = CIFilter(name: "CIBlendWithAlphaMask") else {
            return image
        }

        let extent = image.extent
        blur.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(
            spatialRadius(0.9 + abs(clarity) * 1.8, for: extent),
            forKey: kCIInputRadiusKey
        )
        guard let blurred = blur.outputImage?.cropped(to: extent) else {
            return image
        }

        let blendAmount = CGFloat(abs(clarity) * 0.68)
        let mask = CIImage(
            color: CIColor(red: 1, green: 1, blue: 1, alpha: blendAmount)
        ).cropped(to: extent)
        blend.setValue(blurred, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: "inputMaskImage")
        return blend.outputImage?.cropped(to: extent) ?? image
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
            unsharp.setValue(
                spatialRadius(0.35 + sharpness * 0.65, for: image.extent),
                forKey: kCIInputRadiusKey
            )
            unsharp.setValue(sharpness * 0.7, forKey: kCIInputIntensityKey)
            output = unsharp.outputImage?.cropped(to: image.extent) ?? output
        } else if sharpness < -0.0001,
                  let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(output.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(
                spatialRadius(abs(sharpness) * 0.35, for: image.extent),
                forKey: kCIInputRadiusKey
            )
            output = blur.outputImage?.cropped(to: image.extent) ?? output
        }

        return output
    }

    private static func applyGrain(
        to image: CIImage,
        recipe: FilmRecipe,
        quality _: Quality,
        seed: UInt32,
        phase: CGPoint?
    ) -> CIImage {
        // Grain is part of the look, not a preview-only effect. Normalize the
        // procedural frequency to a reference image size so the same recipe
        // remains visually stable when the source changes from a video frame
        // to a full-resolution still.
        let amount = grainBlendOpacity(for: recipe.grain)
        guard amount > 0.0001,
              let grainTexture = immutableResources.grainTexture,
              let grainKernel = immutableResources.grainKernel else {
            return image
        }

        let extent = image.extent
        let resolutionScale = resolutionScale(for: extent)
        let grainSize = max(
            CGFloat(0.35),
            min(CGFloat(recipe.grainSize) * resolutionScale, CGFloat(8))
        )
        // A seed stores a compact 9-bit phase for the live preview. Capture
        // callers may provide a scaled phase instead; do not force that
        // phase back through the seed bit width because the texture's actual
        // repetition period is 512 * grainSize after scaling.
        let resolvedPhase = phase ?? CGPoint(
            x: CGFloat(seed & 0x1FF),
            y: CGFloat((seed >> 9) & 0x1FF)
        )
        guard resolvedPhase.x.isFinite, resolvedPhase.y.isFinite else {
            return image
        }
        let noise = grainTexture
            .transformed(by: CGAffineTransform(
                scaleX: grainSize,
                y: grainSize
            ))
            .transformed(by: CGAffineTransform(
                translationX: resolvedPhase.x,
                y: resolvedPhase.y
            ))
            .applyingFilter("CIAffineTile")
            .cropped(to: extent)

        // Add zero-mean luminance variation directly. The custom color kernel
        // keeps source alpha intact and avoids the exposure shifts produced by
        // nonlinear blend modes or premultiplied compositing.
        return grainKernel.apply(
            extent: extent,
            arguments: [image, noise, amount]
        )?.cropped(to: extent) ?? image
    }

    /// Camera grain controls describe an effect level, not a literal blend
    /// opacity. A perceptual curve keeps Weak genuinely subtle while leaving
    /// Strong visibly available for intentionally textured looks.
    static func grainBlendOpacity(for controlAmount: Double) -> Double {
        let normalized = clamp(controlAmount, lower: 0, upper: 1)
        return (0.04 * normalized) + (0.08 * normalized * normalized)
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
        // CIVignette's radius is a normalized 0...2 value, not a pixel
        // distance. Keep the radius in that contract so a 4K still does not
        // silently clamp to the same result as every smaller preview frame.
        vignette.setValue(
            clamp(intensity * 1.35, lower: 0, upper: 1),
            forKey: kCIInputIntensityKey
        )
        vignette.setValue(
            clamp(0.8 + intensity * 1.2, lower: 0, upper: 2),
            forKey: kCIInputRadiusKey
        )
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
        let resolutionScale = resolutionScale(for: extent)
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

    /// Returns the scale needed to keep pixel-radius effects visually stable
    /// when the same composition moves between a preview drawable and a
    /// full-resolution still. The lower bound keeps tiny deterministic
    /// fixtures and thumbnail-sized inputs from reducing every blur to a
    /// sub-pixel no-op.
    private static func resolutionScale(for extent: CGRect) -> CGFloat {
        let outputDimension = max(extent.width, extent.height)
        guard outputDimension.isFinite, outputDimension > 0 else { return 1 }
        return max(outputDimension / spatialReferenceDimension, 0.5)
    }

    private static func spatialRadius(
        _ referencePixels: CGFloat,
        for extent: CGRect
    ) -> CGFloat {
        max(0.01, referencePixels * resolutionScale(for: extent))
    }

    private static func makeCubeData(
        dimension: Int,
        recipe: FilmRecipe
    ) -> Data {
        let componentCount = dimension * dimension * dimension * 4
        var data = Data(count: componentCount * MemoryLayout<Float>.stride)

        let divisor = Float(dimension - 1)
        data.withUnsafeMutableBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: Float.self)
            var componentIndex = 0
            for blueIndex in 0..<dimension {
                for greenIndex in 0..<dimension {
                    for redIndex in 0..<dimension {
                        let red = Float(redIndex) / divisor
                        let green = Float(greenIndex) / divisor
                        let blue = Float(blueIndex) / divisor
                        let mapped = mapColor(red: red, green: green, blue: blue, recipe: recipe)
                        values[componentIndex] = mapped.red
                        values[componentIndex + 1] = mapped.green
                        values[componentIndex + 2] = mapped.blue
                        values[componentIndex + 3] = 1
                        componentIndex += 4
                    }
                }
            }
        }
        return data
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
        let hue = rgbHue(red: red, green: green, blue: blue, chroma: chroma)
        // Keep the broad cool response and the dedicated blue response on
        // separate, smoothly feathered hue masks. This prevents FX Blue from
        // being an alias for blueResponse and leaves cyan/teal available to
        // the general cool control.
        let cyanBlueWeight = hueSectorWeight(hue, center: 0.56, halfWidth: 0.14)
        let deepBlueWeight = hueSectorWeight(hue, center: 0.68, halfWidth: 0.12)
        let blueResponseHueWeight = cyanBlueWeight * (1 - deepBlueWeight)
        let fxBlueHueWeight = deepBlueWeight
        let warmHueWeight = max(
            hueSectorWeight(hue, center: 0.00, halfWidth: 0.14),
            hueSectorWeight(hue, center: 0.13, halfWidth: 0.14)
        )

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
        // Keep Color Chrome isolated from the dedicated blue controls. The
        // public camera model describes this stage for saturated red, yellow,
        // and green regions; cyan/deep-blue response belongs to FX Blue and
        // blueResponse below.
        let chromeSectorWeight = max(
            warmHueWeight,
            hueSectorWeight(hue, center: 0.30, halfWidth: 0.17)
        )
        let compression = Float(clamp(recipe.colorChrome, lower: 0, upper: 1))
            * highlightWeight
            * chroma
            * chromeSectorWeight
            * 0.30
        mappedRed = mix(mappedRed, luma + (mappedRed - luma) * 0.72, compression)
        mappedGreen = mix(mappedGreen, luma + (mappedGreen - luma) * 0.72, compression)
        mappedBlue = mix(mappedBlue, luma + (mappedBlue - luma) * 0.72, compression)

        // Blue-response controls primarily affect cool shadows/highlights,
        // while FX Blue is a separate deep-blue/highlight response.
        let blueResponseWeight = Float(clamp(recipe.blueResponse, lower: -1, upper: 1))
            * (1 - luma)
            * chroma
            * blueResponseHueWeight
            * 0.42
        let fxBlueWeight = Float(clamp(recipe.fxBlue, lower: -1, upper: 1))
            * smoothstep(0.18, 0.92, luma)
            * chroma
            * fxBlueHueWeight
            * 0.42
        let blueWeight = blueResponseWeight + fxBlueWeight
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
            // Fujifilm publicly characterizes Classic Chrome as subdued,
            // magenta-suppressing color with cool shadows. Use feathered hue
            // masks so that behavior is selective rather than a global cast.
            let chroma = max(mappedRed, max(mappedGreen, mappedBlue))
                - min(mappedRed, min(mappedGreen, mappedBlue))
            let hue = rgbHue(
                red: mappedRed,
                green: mappedGreen,
                blue: mappedBlue,
                chroma: chroma
            )
            let magentaWeight = hueSectorWeight(
                hue,
                center: 0.88,
                halfWidth: 0.13
            ) * smoothstep(0.025, 0.34, chroma)
            let coolShadowWeight = max(
                hueSectorWeight(hue, center: 0.56, halfWidth: 0.16),
                hueSectorWeight(hue, center: 0.65, halfWidth: 0.15)
            ) * shadowWeight
            let skinWeight = hueSectorWeight(
                hue,
                center: 0.075,
                halfWidth: 0.10
            ) * smoothstep(0.025, 0.30, chroma)

            saturate(0.92)
            mappedGreen += 0.030 * magentaWeight
            mappedRed -= 0.010 * magentaWeight
            mappedBlue -= 0.006 * magentaWeight
            mappedRed += 0.008 * highlightWeight + 0.005 * skinWeight
            mappedBlue += 0.020 * shadowWeight + 0.010 * coolShadowWeight
            mappedGreen += 0.007 * shadowWeight + 0.003 * coolShadowWeight
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
        case .sepia:
            // Original warm-monochrome approximation for the public Sepia
            // vocabulary; this is not Fujifilm calibration data.
            mappedRed = luma * 1.06
            mappedGreen = luma * 0.91
            mappedBlue = luma * 0.72
        case .acros, .acrosYellow, .acrosRed, .acrosGreen, .monochrome:
            mappedRed = luma
            mappedGreen = luma
            mappedBlue = luma
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
        case .compactDigital:
            // Original compact-camera response inspired by the G7 X Mark III
            // product envelope: clean Standard-style color, warm portrait
            // mids, selective red/blue punch, and smooth highlights. This is a
            // parametric approximation, not Canon Picture Style data.
            let chroma = max(mappedRed, max(mappedGreen, mappedBlue))
                - min(mappedRed, min(mappedGreen, mappedBlue))
            let hue = rgbHue(
                red: mappedRed,
                green: mappedGreen,
                blue: mappedBlue,
                chroma: chroma
            )
            let midtoneWeight = smoothstep(0.12, 0.42, luma)
                * (1 - smoothstep(0.78, 0.98, luma))
            let skinWeight = hueSectorWeight(hue, center: 0.075, halfWidth: 0.095)
                * smoothstep(0.035, 0.32, chroma)
                * (1 - smoothstep(0.38, 0.62, chroma))
                * midtoneWeight
            let redWeight = hueSectorWeight(hue, center: 0.99, halfWidth: 0.075)
                * smoothstep(0.055, 0.38, chroma)
                * midtoneWeight
            let greenWeight = hueSectorWeight(hue, center: 0.32, halfWidth: 0.14)
                * smoothstep(0.04, 0.34, chroma)
            let blueWeight = hueSectorWeight(hue, center: 0.60, halfWidth: 0.13)
                * smoothstep(0.04, 0.34, chroma)
            let deepShadowWeight = 1 - smoothstep(0.04, 0.26, luma)
            let brightHighlightWeight = smoothstep(0.72, 0.98, luma)

            // Deep shadows and near-white highlights carry less chroma than
            // the midtones. This avoids colorful shadow noise and hard color
            // clipping. Reference JPEG/RAW pairs also show that the compact
            // response concentrates color in reds, warm subjects, and blues
            // instead of applying blanket saturation.
            saturate(1 - 0.065 * deepShadowWeight - 0.045 * brightHighlightWeight)
            mappedRed += 0.014 * redWeight
            mappedGreen -= 0.004 * redWeight
            mappedBlue -= 0.006 * redWeight
            mappedRed += 0.016 * skinWeight + 0.003 * highlightWeight
            mappedGreen += 0.005 * skinWeight + 0.003 * greenWeight
            mappedBlue -= 0.007 * skinWeight

            // Across the same-scene reference pairs, foliage was usually a
            // little quieter than the independent RAW development. Pull only
            // that hue sector toward luminance so greens retain separation
            // without the fluorescent cast of a global saturation boost.
            let greenRestraint = 0.065 * greenWeight
            mappedRed = mix(mappedRed, luma, greenRestraint)
            mappedGreen = mix(mappedGreen, luma, greenRestraint)
            mappedBlue = mix(mappedBlue, luma, greenRestraint)

            mappedBlue += 0.013 * blueWeight
            mappedGreen += 0.003 * blueWeight
            mappedRed -= 0.003 * blueWeight
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

    private static func rgbHue(
        red: Float,
        green: Float,
        blue: Float,
        chroma: Float
    ) -> Float {
        guard chroma > 0.00001 else { return 0 }

        let maximum = max(red, max(green, blue))
        let rawHue: Float
        if maximum == red {
            rawHue = (green - blue) / chroma
        } else if maximum == green {
            rawHue = (blue - red) / chroma + 2
        } else {
            rawHue = (red - green) / chroma + 4
        }

        let normalized = rawHue / 6
        return normalized < 0 ? normalized + 1 : normalized
    }

    private static func hueSectorWeight(
        _ hue: Float,
        center: Float,
        halfWidth: Float
    ) -> Float {
        var wrappedDelta = (hue - center).truncatingRemainder(dividingBy: 1)
        if wrappedDelta > 0.5 {
            wrappedDelta -= 1
        } else if wrappedDelta < -0.5 {
            wrappedDelta += 1
        }
        let distance = abs(wrappedDelta)
        return 1 - smoothstep(halfWidth * 0.55, halfWidth, distance)
    }

    private static func makeDeterministicGrainTexture() -> CIImage? {
        let size = 512
        // The grain kernel operates in Core Image's linear working domain.
        // Label the procedural bytes as linear so mid-gray remains the exact
        // zero point instead of being gamma-decoded below 0.5.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        var state: UInt32 = 0x9E37_79B9

        for index in stride(from: 0, to: bytes.count, by: 4) {
            // A small xorshift generator gives us a stable, platform-neutral
            // texture without relying on CIRandomGenerator's process state.
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            let centered = Int((state >> 24) & 0x3F) - 31
            let value = UInt8(max(0, min(255, 128 + centered)))
            bytes[index] = value
            bytes[index + 1] = value
            bytes[index + 2] = value
            bytes[index + 3] = 255
        }

        guard let context = bytes.withUnsafeMutableBytes({ rawBuffer in
            CGContext(
                data: rawBuffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }),
              let image = context.makeImage() else {
            return nil
        }

        return CIImage(cgImage: image)
    }

    private static func clamp<T: Comparable>(
        _ value: T,
        lower: T,
        upper: T
    ) -> T {
        min(max(value, lower), upper)
    }
}
