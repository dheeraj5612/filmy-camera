import CoreGraphics
import CoreImage
import CryptoKit
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

    /// Capture facts that cannot be represented by an editable color recipe.
    /// The default keeps previews, imports, and existing callers deterministic;
    /// still captures supply the resolved flash result and detected subjects.
    public struct CaptureContext: @unchecked Sendable {
        public let flashFired: Bool
        public let subjectRegions: [CGRect]

        public init(flashFired: Bool = false, subjectRegions: [CGRect] = []) {
            self.flashFired = flashFired
            self.subjectRegions = subjectRegions
        }

        public static let standard = CaptureContext()
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
        let skinSmoothingKernel: CIColorKernel?
        let subjectGateKernel: CIColorKernel?
        let clearImage: CIImage
        let zeroComponents: CIVector
        let oneComponents: CIVector
        let alphaVector: CIVector
        let neutralWhiteBalance: CIVector

        init() {
            grainTexture = FilmRenderer.makeDeterministicGrainTexture()
            grainKernel = CIColorKernel(source: """
                kernel vec4 filmyGrain(__sample image, __sample noise, float amplitude) {
                    float luminance = dot(image.rgb, vec3(0.2126, 0.7152, 0.0722));
                    float luminanceMask = clamp(4.0 * luminance * (1.0 - luminance), 0.0, 1.0);
                    float delta = (noise.r - 0.5) * amplitude * luminanceMask;
                    return vec4(clamp(image.rgb + vec3(delta), 0.0, 1.0), image.a);
                }
                """)
            skinSmoothingKernel = CIColorKernel(source: """
                kernel vec4 filmySkinSmooth(
                    __sample image,
                    __sample blurred,
                    __sample subjectMask,
                    float amount
                ) {
                    float maximum = max(image.r, max(image.g, image.b));
                    float minimum = min(image.r, min(image.g, image.b));
                    float chroma = maximum - minimum;
                    float luminance = dot(image.rgb, vec3(0.2126, 0.7152, 0.0722));
                    float redWarmth = smoothstep(0.012, 0.16, image.r - image.g);
                    float blueBalance = 1.0 - smoothstep(0.20, 0.42, image.b - image.g);
                    float usefulChroma = smoothstep(0.025, 0.14, chroma)
                        * (1.0 - smoothstep(0.46, 0.72, chroma));
                    float usefulLuma = smoothstep(0.10, 0.28, luminance)
                        * (1.0 - smoothstep(0.86, 0.99, luminance));
                    float skin = redWarmth * blueBalance * usefulChroma * usefulLuma;
                    float mask = clamp(skin * subjectMask.r * amount, 0.0, 1.0);
                    return vec4(mix(image.rgb, blurred.rgb, mask), image.a);
                }
                """)
            // Gate the feathered subject region by luminance so a bright wall
            // behind a head is never lifted into a halo; only the subject's own
            // mid and low tones receive the flash-style lift.
            subjectGateKernel = CIColorKernel(source: """
                kernel vec4 filmySubjectGate(__sample image, __sample mask) {
                    float luminance = dot(image.rgb, vec3(0.2126, 0.7152, 0.0722));
                    float gate = 1.0 - smoothstep(0.58, 0.88, luminance);
                    float value = clamp(mask.r * gate, 0.0, 1.0);
                    return vec4(value, value, value, 1.0);
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

    /// Context options for any caller that must reproduce the app's rendering
    /// exactly (tests, tools). The working color space is part of the look.
    public static var testContextOptions: [CIContextOption: Any] {
        contextOptions.merging([.useSoftwareRenderer: true]) { _, new in new }
    }

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
        if let persisted = ThumbnailDiskCache.image(for: cacheKey) {
            return thumbnailCache.insert(persisted, for: cacheKey)
        }
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let reference = sampleScene(size: extent.size)
        let rendered = render(reference, recipe: recipe, quality: .preview)
        guard let image = outputCGImage(rendered, from: extent) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: image)
        ThumbnailDiskCache.store(thumbnail, for: cacheKey)
        return thumbnailCache.insert(thumbnail, for: cacheKey)
    }

    /// Bump when the sample scene or thumbnail composition changes so stale
    /// PNGs in Caches are not served for the new look.
    static let thumbnailSceneVersion = 2

    /// Renders a recipe over an arbitrary scene, e.g. a live viewfinder
    /// snapshot, at that scene's size. Not cached: callers debounce.
    public static func previewThumbnail(for recipe: FilmRecipe, over scene: CIImage) -> UIImage? {
        let extent = scene.extent
        guard extent.width >= 1, extent.height >= 1 else { return nil }
        let rendered = render(scene, recipe: recipe, quality: .preview)
        guard let image = outputCGImage(rendered, from: extent) else { return nil }
        return UIImage(cgImage: image)
    }

    /// A photographic stand-in used wherever no live frame exists: a
    /// golden-hour sky, a sun, layered hills, warm ground, a skin-toned
    /// subject, and a neutral card. Every recipe control (sky blues, greens,
    /// skin warmth, highlight shoulder, neutral cast) reads on it at a glance.
    public static func sampleScene(size: CGSize) -> CIImage {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)

        func gradient(_ from: CIColor, at p0: CGPoint, to: CIColor, at p1: CGPoint) -> CIImage {
            guard let filter = CIFilter(name: "CILinearGradient") else { return CIImage(color: from) }
            filter.setValue(CIVector(cgPoint: p0), forKey: "inputPoint0")
            filter.setValue(CIVector(cgPoint: p1), forKey: "inputPoint1")
            filter.setValue(from, forKey: "inputColor0")
            filter.setValue(to, forKey: "inputColor1")
            return (filter.outputImage ?? CIImage(color: from)).cropped(to: extent)
        }
        func disc(center: CGPoint, radius: CGFloat, color: CIColor, feather: CGFloat = 1) -> CIImage {
            guard let filter = CIFilter(name: "CIRadialGradient") else { return CIImage.empty() }
            filter.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
            filter.setValue(max(radius - feather, 0), forKey: "inputRadius0")
            filter.setValue(radius + feather, forKey: "inputRadius1")
            filter.setValue(color, forKey: "inputColor0")
            filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
            return (filter.outputImage ?? CIImage.empty()).cropped(to: extent)
        }

        // Sky: deep blue high, warm peach at the horizon (Core Image y is up).
        var scene = gradient(
            CIColor(red: 0.93, green: 0.72, blue: 0.52, alpha: 1), at: CGPoint(x: 0, y: height * 0.42),
            to: CIColor(red: 0.24, green: 0.45, blue: 0.78, alpha: 1), at: CGPoint(x: 0, y: height)
        )
        // Sun glow.
        scene = disc(
            center: CGPoint(x: width * 0.72, y: height * 0.62),
            radius: width * 0.16,
            color: CIColor(red: 1.0, green: 0.90, blue: 0.68, alpha: 0.85),
            feather: width * 0.14
        ).composited(over: scene)
        // Far hills (teal) and near hills (green).
        scene = disc(
            center: CGPoint(x: width * 0.28, y: height * 0.14),
            radius: width * 0.42,
            color: CIColor(red: 0.28, green: 0.47, blue: 0.46, alpha: 1)
        ).composited(over: scene)
        scene = disc(
            center: CGPoint(x: width * 0.84, y: height * 0.08),
            radius: width * 0.40,
            color: CIColor(red: 0.18, green: 0.40, blue: 0.24, alpha: 1)
        ).composited(over: scene)
        // Warm ground.
        scene = gradient(
            CIColor(red: 0.62, green: 0.46, blue: 0.32, alpha: 1), at: CGPoint(x: 0, y: 0),
            to: CIColor(red: 0.62, green: 0.46, blue: 0.32, alpha: 0), at: CGPoint(x: 0, y: height * 0.34)
        ).composited(over: scene)
        // Subject: a skin-toned figure with a darker hair cap and a red accent.
        scene = disc(
            center: CGPoint(x: width * 0.30, y: height * 0.33),
            radius: width * 0.13,
            color: CIColor(red: 0.80, green: 0.56, blue: 0.42, alpha: 1)
        ).composited(over: scene)
        scene = disc(
            center: CGPoint(x: width * 0.30, y: height * 0.41),
            radius: width * 0.11,
            color: CIColor(red: 0.16, green: 0.11, blue: 0.09, alpha: 1)
        ).composited(over: scene)
        scene = CIImage(color: CIColor(red: 0.72, green: 0.16, blue: 0.14, alpha: 1))
            .cropped(to: CGRect(x: width * 0.19, y: 0, width: width * 0.22, height: height * 0.22))
            .composited(over: scene)
        // Neutral card: white with a mid-gray step to expose casts and shoulder.
        scene = CIImage(color: CIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1))
            .cropped(to: CGRect(x: width * 0.66, y: height * 0.05, width: width * 0.24, height: height * 0.16))
            .composited(over: scene)
        scene = CIImage(color: CIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1))
            .cropped(to: CGRect(x: width * 0.66, y: height * 0.05, width: width * 0.10, height: height * 0.16))
            .composited(over: scene)
        return scene.cropped(to: extent)
    }

    /// Recipe swatches are pure functions of (recipe, renderer version, size),
    /// so their PNGs are kept in Caches across launches. Thirty tiles cost a
    /// few hundred milliseconds of GPU on every launch otherwise, competing
    /// with the live viewfinder while the rail first appears.
    private enum ThumbnailDiskCache {
        /// Entries live in a directory named for the renderer and scene
        /// version; any other directory is stale and removed on first use.
        /// The directory itself is capped by count, oldest first, so slider
        /// drafts that pause long enough to persist cannot grow it unbounded.
        private static let entryLimit = 240
        private static let pruneCounter = PruneCounter(every: 40)

        private final class PruneCounter: @unchecked Sendable {
            private let lock = NSLock()
            private let interval: Int
            private var count = 0

            init(every interval: Int) {
                self.interval = interval
            }

            func recordStore() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                count += 1
                guard count >= interval else { return false }
                count = 0
                return true
            }
        }

        private static let directoryURL: URL? = {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return nil
            }
            let root = caches.appendingPathComponent("RecipeThumbnails", isDirectory: true)
            let versionName = "v\(FilmRecipe.rendererVersion)-s\(thumbnailSceneVersion)"
            let url = root.appendingPathComponent(versionName, isDirectory: true)
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            if let siblings = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                for sibling in siblings where sibling.lastPathComponent != versionName {
                    try? fileManager.removeItem(at: sibling)
                }
            }
            prune(in: url)
            return url
        }()

        private static func prune(in directory: URL) {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ), files.count > entryLimit else {
                return
            }
            let dated = files.map { url -> (URL, Date) in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return (url, date)
            }
            .sorted { $0.1 < $1.1 }
            for (url, _) in dated.prefix(files.count - entryLimit) {
                try? fileManager.removeItem(at: url)
            }
        }

        private static func fileURL(for key: ThumbnailCacheKey) -> URL? {
            guard let directoryURL,
                  let recipeData = try? JSONEncoder().encode(key.recipe) else {
                return nil
            }
            var hasher = SHA256()
            hasher.update(data: Data(FilmRecipe.rendererVersion.utf8))
            hasher.update(data: Data("scene\(thumbnailSceneVersion)-\(key.width)x\(key.height)".utf8))
            hasher.update(data: recipeData)
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return directoryURL.appendingPathComponent("\(digest).png", isDirectory: false)
        }

        static func image(for key: ThumbnailCacheKey) -> UIImage? {
            guard let url = fileURL(for: key),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return UIImage(data: data)
        }

        static func store(_ image: UIImage, for key: ThumbnailCacheKey) {
            guard let url = fileURL(for: key),
                  let directoryURL,
                  let data = image.pngData() else {
                return
            }
            try? data.write(to: url, options: .atomic)
            if pruneCounter.recordStore() {
                prune(in: directoryURL)
            }
        }
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
        captureContext: CaptureContext = .standard,
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
        output = applyCompactDigitalTone(
            to: output,
            recipe: safeRecipe,
            captureContext: captureContext
        )
        output = applyWhiteBalance(to: output, recipe: safeRecipe)
        output = applyMonochromeFilter(to: output, recipe: safeRecipe)
        output = applyColorControls(to: output, recipe: safeRecipe)
        output = applyColorCube(to: output, recipe: safeRecipe, quality: quality)
        output = applyMonochromaticColorAxes(to: output, recipe: safeRecipe)
        output = applyCompactDigitalSubjectTreatment(
            to: output,
            recipe: safeRecipe,
            captureContext: captureContext
        )
        output = applyDetailControls(to: output, recipe: safeRecipe)
        output = applyClarity(to: output, recipe: safeRecipe)
        output = applyCompactDigitalSkinSmoothing(
            to: output,
            recipe: safeRecipe,
            captureContext: captureContext
        )
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

    /// Detects portrait subjects once on the full-resolution still path. Live
    /// preview rendering intentionally does not run a face detector per frame.
    public static func portraitSubjectRegions(in image: CIImage) -> [CGRect] {
        let extent = image.extent
        guard !extent.isEmpty,
              extent.width.isFinite,
              extent.height.isFinite,
              let detector = CIDetector(
                ofType: CIDetectorTypeFace,
                context: nil,
                options: [
                    CIDetectorAccuracy: CIDetectorAccuracyHigh,
                    CIDetectorMinFeatureSize: 0.05
                ]
              ) else {
            return []
        }

        let maximumDimension = max(extent.width, extent.height)
        let detectionScale = min(CGFloat(1), 960 / max(maximumDimension, 1))
        let detectionImage = image.transformed(by: CGAffineTransform(
            scaleX: detectionScale,
            y: detectionScale
        ))

        return detector.features(in: detectionImage).compactMap { feature in
            guard feature.type == CIFeatureTypeFace else { return nil }
            let scaledBounds = feature.bounds
            let bounds = CGRect(
                x: scaledBounds.minX / detectionScale,
                y: scaledBounds.minY / detectionScale,
                width: scaledBounds.width / detectionScale,
                height: scaledBounds.height / detectionScale
            ).intersection(extent)
            return bounds.isEmpty ? nil : bounds
        }
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
            kelvin: value(recipe.whiteBalance.kelvin, .colorTemperature, neutral: FilmRecipe.asShotKelvin)
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
        recipe: FilmRecipe,
        captureContext: CaptureContext
    ) -> CIImage {
        guard recipe.filmBase == .compactDigital,
              let toneCurve = CIFilter(name: "CIToneCurve") else {
            return image
        }

        // The default deliberately favors the social compact-camera outcome:
        // richer ambient shadows, present portrait midtones, and a protected
        // highlight shoulder. When flash actually fired, the stronger curve
        // reinforces that bright-subject/dark-room separation without
        // pretending flash lighting exists on a non-flash capture.
        let points: [(CGFloat, CGFloat)] = captureContext.flashFired
            ? [
                (0.00, 0.002),
                (0.18, 0.155),
                (0.50, 0.575),
                (0.80, 0.846),
                (1.00, 0.964)
            ]
            : [
                (0.00, 0.004),
                (0.18, 0.185),
                (0.50, 0.560),
                (0.80, 0.828),
                (1.00, 0.972)
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

    private static func applyCompactDigitalSubjectTreatment(
        to image: CIImage,
        recipe: FilmRecipe,
        captureContext: CaptureContext
    ) -> CIImage {
        guard recipe.filmBase == .compactDigital,
              let mask = compactDigitalSubjectMask(
                for: captureContext,
                extent: image.extent
              ),
              let blend = CIFilter(name: "CIBlendWithMask") else {
            return image
        }

        let backgroundEV = captureContext.flashFired ? -0.34 : -0.07
        let subjectEV = captureContext.flashFired ? 0.18 : 0.11
        let background = image.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: backgroundEV
        ])
        let subject = image
            .applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: subjectEV
            ])
            .applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": captureContext.flashFired ? 0.66 : 0.76,
                "inputShadowAmount": 0
            ])

        let gatedMask = immutableResources.subjectGateKernel?.apply(
            extent: image.extent,
            arguments: [image, mask]
        )?.cropped(to: image.extent) ?? mask

        // Separate subject from ambient with the full feathered region first,
        // so bright skin, highlights, and white clothing inside the region are
        // preserved rather than darkened as background. The luminance gate
        // then limits only the additional lift to the subject's mid and low
        // tones, which is what keeps bright walls from turning into a halo.
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(background, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: "inputMaskImage")
        guard let separated = blend.outputImage?.cropped(to: image.extent),
              let lift = CIFilter(name: "CIBlendWithMask") else {
            return image
        }

        lift.setValue(subject, forKey: kCIInputImageKey)
        lift.setValue(separated, forKey: kCIInputBackgroundImageKey)
        lift.setValue(gatedMask, forKey: "inputMaskImage")
        return lift.outputImage?.cropped(to: image.extent) ?? separated
    }

    private static func applyCompactDigitalSkinSmoothing(
        to image: CIImage,
        recipe: FilmRecipe,
        captureContext: CaptureContext
    ) -> CIImage {
        let smoothingControl = clamp(recipe.noiseReduction, lower: 0, upper: 1)
        guard recipe.filmBase == .compactDigital,
              smoothingControl > 0.0001,
              max(image.extent.width, image.extent.height) >= 16,
              let kernel = immutableResources.skinSmoothingKernel,
              let blur = CIFilter(name: "CIGaussianBlur") else {
            return image
        }

        let extent = image.extent
        blur.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(
            spatialRadius(1.15 + smoothingControl * 2.4, for: extent),
            forKey: kCIInputRadiusKey
        )
        guard let blurred = blur.outputImage?.cropped(to: extent) else {
            return image
        }

        let subjectMask = compactDigitalSubjectMask(
            for: captureContext,
            extent: extent
        ) ?? CIImage(color: .white).cropped(to: extent)
        let amount = clamp(
            smoothingControl * 1.35 + (captureContext.flashFired ? 0.05 : 0),
            lower: 0,
            upper: 0.45
        )
        return kernel.apply(
            extent: extent,
            arguments: [image, blurred, subjectMask, amount]
        )?.cropped(to: extent) ?? image
    }

    private static func compactDigitalSubjectMask(
        for captureContext: CaptureContext,
        extent: CGRect
    ) -> CIImage? {
        guard !extent.isEmpty else { return nil }

        var regions = captureContext.subjectRegions.compactMap { face -> CGRect? in
            guard !face.isEmpty, face.width.isFinite, face.height.isFinite else {
                return nil
            }
            // Expand a detected face into a softly feathered upper-body area.
            // Core Image coordinates increase upward, so shift the center down
            // to include shoulders and clothing rather than brightening only a
            // small oval over the face.
            let region = CGRect(
                x: face.midX - face.width * 1.35,
                y: face.midY - face.height * 2.15,
                width: face.width * 2.70,
                height: face.height * 3.50
            )
            return region.intersects(extent) ? region : nil
        }

        if regions.isEmpty, captureContext.flashFired {
            // Direct-flash portraits are normally center composed. This safe
            // fallback keeps flash-on captures distinctive if a face is
            // briefly occluded or the detector misses a profile.
            regions = [CGRect(
                x: extent.midX - extent.width * 0.31,
                y: extent.midY - extent.height * 0.37,
                width: extent.width * 0.62,
                height: extent.height * 0.74
            )]
        }

        guard !regions.isEmpty else { return nil }

        let masks = regions.compactMap { region -> CIImage? in
            guard let radial = CIFilter(name: "CIRadialGradient") else {
                return nil
            }
            radial.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
            radial.setValue(0.34, forKey: "inputRadius0")
            radial.setValue(1.0, forKey: "inputRadius1")
            radial.setValue(CIColor.white, forKey: "inputColor0")
            radial.setValue(CIColor.black, forKey: "inputColor1")
            return radial.outputImage?
                .transformed(by: CGAffineTransform(
                    scaleX: region.width / 2,
                    y: region.height / 2
                ))
                .transformed(by: CGAffineTransform(
                    translationX: region.midX,
                    y: region.midY
                ))
                .cropped(to: extent)
        }

        guard var combined = masks.first else { return nil }
        for mask in masks.dropFirst() {
            combined = mask.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: combined
            ]).cropped(to: extent)
        }
        return combined
    }

    private static func applyWhiteBalance(
        to image: CIImage,
        recipe: FilmRecipe
    ) -> CIImage {
        let temperatureShift = recipe.temperatureShift + recipe.whiteBalance.mode.temperatureBias
        let tintShift = recipe.tintShift + recipe.whiteBalance.mode.tintBias
        // Camera semantics: the Kelvin value is the illuminant the camera is
        // told to neutralize. Phone frames arrive already balanced for the
        // scene (about daylight), so a setting above the as-shot reference
        // renders warmer and one below renders cooler, exactly as it would on
        // the camera body and in desktop RAW editors.
        let baseKelvin = recipe.whiteBalance.mode == .colorTemperature
            ? 6500 - (clamp(recipe.whiteBalance.kelvin, lower: 2500, upper: 10000) - FilmRecipe.asShotKelvin)
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
        // The app's contexts run with an sRGB (gamma-encoded) working space,
        // so this contrast pivots at perceptual middle gray like a camera's
        // contrast control. Test contexts must use the same working space or
        // they measure a different, shadow-crushing pipeline.
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
        // keeps source alpha intact, applies one delta to every color channel,
        // and tapers the effect toward pure black and white so grain remains
        // concentrated in the descriptive midtones instead of reading as
        // uniform digital noise.
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
        // The working space is gamma-encoded, so CIVignette's darkening reads
        // stronger than in linear light; a 1:1 intensity keeps a mid-slider
        // vignette from swallowing the corners.
        vignette.setValue(
            clamp(intensity * 0.92, lower: 0, upper: 1),
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

        // Shadow tints belong to shadow detail, not to true blacks: a blue or
        // amber cast on near-black noise reads as a fault, not a film look.
        let shadowWeight = (1 - smoothstep(0.08, 0.62, luma)) * smoothstep(0.015, 0.09, luma)
        let highlightWeight = smoothstep(0.48, 0.98, luma)
        let midtoneWeight = smoothstep(0.10, 0.40, luma) * (1 - smoothstep(0.70, 0.96, luma))

        // Shared hue sectors. Every film base below is an original parametric
        // reading of Fujifilm's public descriptions of its simulations (hard or
        // soft tonality, color in highlights versus shadows, which hues move),
        // not calibration data. Sector deltas are in sRGB units.
        let baseChroma = max(mappedRed, max(mappedGreen, mappedBlue))
            - min(mappedRed, min(mappedGreen, mappedBlue))
        let baseHue = rgbHue(red: mappedRed, green: mappedGreen, blue: mappedBlue, chroma: baseChroma)
        let colorful = smoothstep(0.035, 0.30, baseChroma)
        let redSector = hueSectorWeight(baseHue, center: 0.99, halfWidth: 0.07) * colorful
        let skinSector = hueSectorWeight(baseHue, center: 0.075, halfWidth: 0.075) * colorful
        let yellowSector = hueSectorWeight(baseHue, center: 0.16, halfWidth: 0.06) * colorful
        let greenSector = hueSectorWeight(baseHue, center: 0.32, halfWidth: 0.13) * colorful
        let blueSector = hueSectorWeight(baseHue, center: 0.62, halfWidth: 0.12) * colorful
        let magentaSector = hueSectorWeight(baseHue, center: 0.86, halfWidth: 0.10) * colorful

        func nudge(_ red: Float, _ green: Float, _ blue: Float, by weight: Float) {
            mappedRed += red * weight
            mappedGreen += green * weight
            mappedBlue += blue * weight
        }

        switch recipe.filmBase {
        case .standard:
            break
        case .provia:
            // Even, slightly punchy standard: a touch more saturation than
            // neutral, greens leaning yellow-green.
            saturate(1.04)
            nudge(0.006, 0.010, -0.006, by: greenSector)
        case .classicChrome:
            // Documentary chrome: muted midtones, reds held back, blues
            // leaning teal, browns turning pink instead of yellow, cool
            // shadows, magenta suppressed.
            saturate(0.84)
            nudge(-0.030, 0.006, 0.004, by: redSector)
            nudge(-0.010, 0.036, -0.012, by: blueSector)
            nudge(0.006, -0.014, 0.020, by: skinSector)
            nudge(-0.012, 0.028, -0.008, by: magentaSector)
            nudge(-0.032, 0.012, 0.080, by: shadowWeight)
            nudge(0.008, 0.002, -0.004, by: highlightWeight)
        case .velvia:
            // Everything turned up: high saturation and contrast, cobalt
            // blues, rich cool greens, intense reds and warm yellows.
            saturate(1.20 + 0.06 * midtoneWeight)
            nudge(-0.024, -0.004, 0.050, by: blueSector)
            nudge(-0.030, 0.040, 0.006, by: greenSector)
            nudge(0.030, -0.012, -0.006, by: redSector)
            nudge(0.024, 0.008, -0.020, by: yellowSector)
        case .astia:
            // Soft portrait slide: gentle contrast, "blue-blue" skies,
            // characterful yellows, rosy rather than yellow skin.
            saturate(1.04)
            nudge(-0.006, -0.010, 0.032, by: blueSector)
            nudge(0.030, 0.006, -0.020, by: yellowSector)
            nudge(0.012, -0.002, 0.008, by: skinSector)
            nudge(0.010, 0.002, -0.006, by: highlightWeight)
        case .proNegative:
            // Portrait negative, high-contrast variant: a little muted,
            // slightly warm, yellows and greens kept alive.
            saturate(0.94)
            nudge(0.014, 0.006, -0.006, by: midtoneWeight)
            nudge(0.004, 0.012, -0.004, by: greenSector)
            nudge(0.010, 0.004, -0.006, by: yellowSector)
        case .proNegStandard:
            saturate(0.88)
            nudge(0.010, 0.004, -0.004, by: midtoneWeight)
            nudge(0.004, 0.008, -0.002, by: greenSector)
        case .eterna:
            // Cinema: flat, neutral, twice as muted as Classic Chrome, with a
            // faint cool-green cast in the shadows and no warm bias.
            saturate(0.72)
            nudge(-0.006, 0.012, 0.014, by: shadowWeight)
            nudge(0.004, 0.000, -0.002, by: highlightWeight)
        case .eternaBleachBypass:
            // Black and white with a little color left, high contrast.
            saturate(0.48)
            nudge(0.010, 0.002, -0.004, by: highlightWeight)
            nudge(-0.004, 0.004, 0.012, by: shadowWeight)
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
            // Hard tonality with its own palette: greens go "green-green"
            // (less yellow), reds deeper and less bright, browns less
            // yellow, cool cyan shadows against warm highlights.
            saturate(0.94)
            nudge(-0.050, 0.004, 0.022, by: greenSector)
            nudge(-0.030, -0.004, 0.016, by: redSector)
            nudge(-0.004, -0.022, 0.010, by: skinSector)
            nudge(0.000, -0.020, -0.004, by: yellowSector)
            nudge(-0.022, 0.030, 0.052, by: shadowWeight)
            nudge(0.030, 0.012, -0.022, by: highlightWeight)
        case .nostalgicNegative:
            // American New Color, per Fujifilm: rich colors in the shadows
            // with a soft tonality through midtones and highlights. Amber
            // highlights, warm midtones, yellow-brown browns, quieter blues,
            // and shadow color kept rich rather than washed.
            saturate(1.02 + 0.10 * shadowWeight)
            nudge(0.050, 0.030, -0.046, by: highlightWeight)
            nudge(0.022, 0.010, -0.010, by: midtoneWeight)
            nudge(0.010, 0.022, -0.012, by: skinSector)
            nudge(0.012, 0.006, -0.028, by: blueSector)
            nudge(0.014, 0.004, 0.000, by: shadowWeight)
        case .realaAce:
            // Faithful color with hard tonality: between PRO Neg. Std and Hi
            // in saturation, blues rendered slightly deeper, brighter
            // midtones, a whisper of warmth in skin.
            saturate(0.98)
            nudge(0.010, 0.002, -0.004, by: skinSector)
            nudge(-0.010, -0.010, 0.012, by: blueSector)
            nudge(0.004, 0.004, 0.004, by: midtoneWeight)
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
            // Near-neutral warm grays (fabric, walls under tungsten) must not be
            // treated as skin, or they drift brown. Require real chroma first.
            let skinWeight = hueSectorWeight(hue, center: 0.075, halfWidth: 0.095)
                * smoothstep(0.075, 0.30, chroma)
                * (1 - smoothstep(0.38, 0.62, chroma))
                * midtoneWeight
            let redWeight = hueSectorWeight(hue, center: 0.99, halfWidth: 0.075)
                * smoothstep(0.085, 0.38, chroma)
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
            // Social G7 X references consistently emphasize peach/pink skin,
            // vivid red accents, and a clean flash-lit subject. Keep the lift
            // hue- and midtone-local so landscapes and neutral objects do not
            // inherit a face-filter cast. This is an original exaggeration of
            // the public visual intent, not a sampled transform.
            mappedRed += 0.046 * redWeight
            mappedGreen -= 0.014 * redWeight
            mappedBlue -= 0.012 * redWeight
            // Peach/pink rather than orange: push red, hold green, and let a
            // little blue back in so skin reads rosy instead of tanned.
            mappedRed += 0.050 * skinWeight + 0.004 * highlightWeight
            mappedGreen -= 0.004 * skinWeight + 0.003 * greenWeight
            mappedBlue += 0.016 * skinWeight

            // Across the same-scene reference pairs, foliage was usually a
            // little quieter than the independent RAW development. Pull only
            // that hue sector toward luminance so greens retain separation
            // without the fluorescent cast of a global saturation boost.
            let greenRestraint = 0.16 * greenWeight
            mappedRed = mix(mappedRed, luma, greenRestraint)
            mappedGreen = mix(mappedGreen, luma, greenRestraint)
            mappedBlue = mix(mappedBlue, luma, greenRestraint)

            mappedBlue += 0.042 * blueWeight
            mappedGreen += 0.004 * blueWeight
            mappedRed -= 0.016 * blueWeight
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
        // The bytes are raw working-space samples centered on 0.5. They must
        // not be color-managed on the way into the kernel: a linear tag under
        // the app's sRGB working space recenters the noise near 0.73 and the
        // "zero-mean" grain then brightens every frame by a few percent.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        var bytes = deterministicGaussianGrainBytes(size: size)

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

        return CIImage(cgImage: image, options: [.colorSpace: NSNull()])
    }

    /// Produces a stable, monochrome Gaussian field for the shared grain
    /// texture. Box-Muller is evaluated once when immutable renderer resources
    /// are initialized; live frames only tile and phase-shift the cached image.
    static func deterministicGaussianGrainBytes(
        size: Int,
        seed: UInt32 = 0x9E37_79B9
    ) -> [UInt8] {
        guard size > 0 else { return [] }

        let pixelCount = size * size
        let sigma = 18.0
        var bytes = [UInt8](repeating: 255, count: pixelCount * 4)
        var state = seed == 0 ? UInt32(0xA341_316C) : seed

        func nextUniform() -> Double {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            // Half-step sampling keeps the logarithm away from zero while
            // retaining a deterministic mapping across platforms.
            return (Double(state) + 0.5) / (Double(UInt32.max) + 1.0)
        }

        func store(_ normal: Double, at pixelIndex: Int) {
            let clipped = clamp(normal, lower: -3.0, upper: 3.0)
            let value = UInt8(clamp(Int((127.5 + clipped * sigma).rounded()), lower: 0, upper: 255))
            let byteIndex = pixelIndex * 4
            bytes[byteIndex] = value
            bytes[byteIndex + 1] = value
            bytes[byteIndex + 2] = value
        }

        var pixelIndex = 0
        while pixelIndex < pixelCount {
            let firstUniform = max(nextUniform(), Double.leastNonzeroMagnitude)
            let secondUniform = nextUniform()
            let radius = sqrt(-2.0 * log(firstUniform))
            let angle = 2.0 * Double.pi * secondUniform
            store(radius * cos(angle), at: pixelIndex)
            pixelIndex += 1
            if pixelIndex < pixelCount {
                store(radius * sin(angle), at: pixelIndex)
                pixelIndex += 1
            }
        }

        return bytes
    }

    private static func clamp<T: Comparable>(
        _ value: T,
        lower: T,
        upper: T
    ) -> T {
        min(max(value, lower), upper)
    }
}
