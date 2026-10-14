import CoreImage
import ImageIO
import Metal
import UIKit
import XCTest
@testable import FilmyCamera

/// On-device timing for the live preview path. Not a pass/fail gate: it
/// attaches a per-recipe, per-stage millisecond report so pipeline changes
/// can be judged on real hardware. Run it with `-only-testing` on a device.
final class RendererPerformanceTests: XCTestCase {
    @MainActor
    func testFullResolutionImportTimings() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let scene = FilmRenderer.sampleScene(size: CGSize(width: 4000, height: 3000))
        let source = try XCTUnwrap(FilmRenderer.outputCGImage(scene))
        let data = try XCTUnwrap(UIImage(cgImage: source).jpegData(compressionQuality: 0.95))
        let suite = "RendererPerformanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var report = "12 MP import through review; thermal=\(ProcessInfo.processInfo.thermalState.rawValue)\n"
        for id in ["g7x-compact", "classic-chrome", "provia-standard"] {
            let model = CameraViewModel(defaults: defaults)
            model.select(recipe: try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == id }))
            var samples: [Double] = []
            for _ in 0..<3 {
                let start = CFAbsoluteTimeGetCurrent()
                await model.importPhoto(data: data)
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                XCTAssertNotNil(model.reviewImage)
                XCTAssertTrue(model.reviewIsFullResolution)
                XCTAssertEqual(model.reviewImage!.size.width / model.reviewImage!.size.height, 4.0 / 3, accuracy: 0.01)
                model.discardReview()
            }
            report += "\(id): \(samples) ms\n"
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = "full-resolution-import-timings"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("IMPORT PERF\n\(report)")
    }

    func testPortraitDetectorReuseTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let scene = FilmRenderer.sampleScene(size: CGSize(width: 640, height: 960))
        let source = CIImage(cgImage: try XCTUnwrap(FilmRenderer.outputCGImage(scene)))
        var fresh: [Double] = []
        var reused: [Double] = []
        _ = FilmRenderer.portraitSubjectRegions(in: source)
        for _ in 0..<8 {
            let start = CFAbsoluteTimeGetCurrent()
            let expected: [CGRect] = autoreleasepool {
                let detector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [
                    CIDetectorAccuracy: CIDetectorAccuracyHigh,
                    CIDetectorMinFeatureSize: 0.05
                ])
                return detector?.features(in: source).map(\.bounds) ?? []
            }
            fresh.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let reusedStart = CFAbsoluteTimeGetCurrent()
            let actual = FilmRenderer.portraitSubjectRegions(in: source)
            reused.append((CFAbsoluteTimeGetCurrent() - reusedStart) * 1000)
            XCTAssertEqual(actual, expected)
        }
        let report = "portrait median ms: fresh=\(fresh.sorted()[4]), reused=\(reused.sorted()[4])"
        let attachment = XCTAttachment(string: report)
        attachment.name = "portrait-detector-timings"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("PORTRAIT PERF \(report)")
    }

    private struct Variant {
        let name: String
        let mutate: (inout FilmRecipe) -> Void
    }

    func testPreviewRenderTimings() throws {
        // Hundreds of synchronous Metal renders: opt in explicitly, e.g.
        // TEST_RUNNER_FILMY_RUN_PERF=1 xcodebuild ... -only-testing:FilmyCameraTests/RendererPerformanceTests
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1",
            "Set FILMY_RUN_PERF=1 to run the on-device render benchmark"
        )
        let context = FilmRenderer.sharedContext
        let sizes: [(String, CGSize)] = [
            ("Production budget 988x1316", CGSize(width: 988, height: 1316)),
            ("iPad 1x 834x1112", CGSize(width: 834, height: 1112)),
            ("iPad 2x 1668x2224", CGSize(width: 1668, height: 2224)),
            ("iPhone 3x 1206x1610", CGSize(width: 1206, height: 1610))
        ]
        let recipeIDs = ["g7x-compact", "classic-chrome", "provia-standard", "nostalgic-summer"]
        let variants: [Variant] = [
            Variant(name: "as-is") { _ in },
            Variant(name: "no noise reduction") { $0.noiseReduction = 0 },
            Variant(name: "no clarity") { $0.clarity = 0 },
            Variant(name: "no sharpness") { $0.sharpness = 0 },
            Variant(name: "no grain") { $0.grain = 0 },
            Variant(name: "no halation") { $0.halation = 0 },
            Variant(name: "no vignette") { $0.vignette = 0 },
            Variant(name: "no spatial at all") {
                $0.noiseReduction = 0; $0.clarity = 0; $0.sharpness = 0
                $0.grain = 0; $0.halation = 0; $0.vignette = 0
            }
        ]

        var report = "device: \(FilmRenderer.metalDevice?.name ?? "software")\n"
        for (sizeName, size) in sizes {
            let extent = CGRect(origin: .zero, size: size)
            let source = Self.syntheticFrame(size: size)
            report += "\n[\(sizeName)]\n"
            for identifier in recipeIDs {
                guard let base = FilmRecipe.builtIns.first(where: { $0.id == identifier }) else { continue }
                var line = "  \(base.name):"
                for variant in variants where variant.name == "as-is" || identifier == "g7x-compact" {
                    var recipe = base
                    variant.mutate(&recipe)
                    print("PERF CASE \(sizeName) / \(identifier) / \(variant.name)")
                    let milliseconds = Self.timeRender(source, recipe: recipe, extent: extent, context: context)
                    line += " \(variant.name)=\(String(format: "%.1f", milliseconds))ms"
                }
                report += line + "\n"
            }
        }

        let attachment = XCTAttachment(string: report)
        attachment.name = "preview-render-timings"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("PERF\n\(report)")
    }

    private static func timeRender(
        _ source: CIImage,
        recipe: FilmRecipe,
        extent: CGRect,
        context: CIContext
    ) -> Double {
        guard let device = FilmRenderer.metalDevice,
              let queue = device.makeCommandQueue() else {
            return -1
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(extent.width),
            height: Int(extent.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return -1
        }

        func renderOnce() {
            autoreleasepool {
                guard let commandBuffer = queue.makeCommandBuffer() else {
                    XCTFail("Could not allocate a benchmark command buffer")
                    return
                }
                let filtered = FilmRenderer.render(source, recipe: recipe, quality: .preview)
                    .cropped(to: extent)
                context.render(
                    filtered,
                    to: texture,
                    commandBuffer: commandBuffer,
                    bounds: extent,
                    colorSpace: colorSpace
                )
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                XCTAssertEqual(commandBuffer.status, .completed,
                    "Benchmark GPU failure: \(String(describing: commandBuffer.error))")
            }
        }

        for _ in 0..<3 { renderOnce() }
        let iterations = 8
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations { renderOnce() }
        return (CFAbsoluteTimeGetCurrent() - start) / Double(iterations) * 1000
    }

    /// A camera-like frame: gradients plus a few colored regions so hue
    /// weighting and spatial stages have real content to chew on.
    private static func syntheticFrame(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let gradient = CIFilter(name: "CILinearGradient")!
        gradient.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        gradient.setValue(CIVector(x: size.width, y: size.height), forKey: "inputPoint1")
        gradient.setValue(CIColor(red: 0.12, green: 0.10, blue: 0.09), forKey: "inputColor0")
        gradient.setValue(CIColor(red: 0.92, green: 0.90, blue: 0.86), forKey: "inputColor1")
        var image = gradient.outputImage!.cropped(to: extent)

        let blocks: [(CGRect, CIColor)] = [
            (CGRect(x: size.width * 0.1, y: size.height * 0.5, width: size.width * 0.3, height: size.height * 0.3), CIColor(red: 0.70, green: 0.43, blue: 0.30)),
            (CGRect(x: size.width * 0.5, y: size.height * 0.6, width: size.width * 0.4, height: size.height * 0.2), CIColor(red: 0.18, green: 0.42, blue: 0.78)),
            (CGRect(x: size.width * 0.2, y: size.height * 0.1, width: size.width * 0.5, height: size.height * 0.25), CIColor(red: 0.20, green: 0.55, blue: 0.22))
        ]
        for (rect, color) in blocks {
            image = CIImage(color: color).cropped(to: rect).composited(over: image)
        }
        // Add a little high-frequency detail so noise reduction and sharpening
        // are not trivially cheap on flat regions.
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.08, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.08, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.08, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .cropped(to: extent)
        return noise.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)
    }

    // MARK: - Measurement pass (FILMY_RUN_PERF=1)
    //
    // Each testMeasure method times one production path and prints
    // "PERF <id> <metric> min_ms= median_ms= p90_ms= n=". Setting
    // FILMY_PERF_OUT=<path> also appends one JSON line per metric. There is
    // no assertion on time, only on the measured work having produced a sane
    // result. Wall time comes with CPU time of the calling thread, or of the
    // whole process where a metric says so. Run optimized (the test scheme's
    // DEBUG flag stays set, so a result is only as good as the -O build it
    // came from) and treat a simulator run as a lower bound for A13-class
    // CPU work.

    private struct PerfSample {
        let wallMS: Double
        let cpuMS: Double
    }

    private enum PerfCPUClock {
        case thread
        case process

        var clockID: clockid_t {
            self == .thread ? CLOCK_THREAD_CPUTIME_ID : CLOCK_PROCESS_CPUTIME_ID
        }

        var label: String { self == .thread ? "cpu_thread" : "cpu_process" }
    }

    /// Compile-time flag only. It cannot tell -O from -Onone, so the optimization
    /// level is proven from the build log, not from here.
    private static let perfBuildNote: String = {
        #if DEBUG
        return "build_flag=DEBUG"
        #else
        return "build_flag=release"
        #endif
    }()

    private static let announceBuild: Void = {
        print("PERF_BUILD \(perfBuildNote) FILMY_PERF_OUT_set=\(ProcessInfo.processInfo.environment["FILMY_PERF_OUT"] != nil); optimization level is not detectable at runtime")
    }()

    private static func timed(_ clock: PerfCPUClock, _ body: () -> Void) -> PerfSample {
        let cpuStart = clock_gettime_nsec_np(clock.clockID)
        let wallStart = DispatchTime.now().uptimeNanoseconds
        body()
        let wallEnd = DispatchTime.now().uptimeNanoseconds
        let cpuEnd = clock_gettime_nsec_np(clock.clockID)
        return PerfSample(
            wallMS: Double(wallEnd - wallStart) / 1_000_000,
            cpuMS: cpuEnd >= cpuStart ? Double(cpuEnd - cpuStart) / 1_000_000 : 0
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// `preferWall`: the work runs on Core Image, ImageIO or GPU threads, so
    /// the CPU column of the calling thread understates it and wall is the
    /// number to read.
    private static func record(
        id: String,
        metric: String,
        samples: [PerfSample],
        clock: PerfCPUClock,
        note: String,
        preferWall: Bool = false,
        into report: inout String
    ) {
        let fullNote = preferWall ? note + "; preferred=wall (work runs off the calling thread)" : note
        emit(id: id, metric: metric + ".wall", values: samples.map(\.wallMS), note: fullNote, into: &report)
        emit(id: id, metric: metric + "." + clock.label, values: samples.map(\.cpuMS), note: fullNote, into: &report)
    }

    private static func emit(
        id: String,
        metric: String,
        values: [Double],
        note: String,
        into report: inout String
    ) {
        _ = announceBuild
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return }
        let p90Rank = Int((Double(sorted.count) * 0.9).rounded(.up))
        let p90 = sorted[min(max(p90Rank - 1, 0), sorted.count - 1)]
        let median = Self.median(sorted)
        let text = { (value: Double) -> String in String(format: "%.3f", value) }
        let line = "PERF \(id) \(metric) min_ms=\(text(sorted[0])) median_ms=\(text(median)) p90_ms=\(text(p90)) n=\(sorted.count)"
        print(line)
        report += line + "\n"
        let object: [String: Any] = [
            "id": id, "metric": metric, "min_ms": sorted[0], "median_ms": median,
            "p90_ms": p90, "n": sorted.count, "note": note + "; " + perfBuildNote
        ]
        appendJSONLine(object)
    }

    private static func appendJSONLine(_ object: [String: Any]) {
        guard let path = ProcessInfo.processInfo.environment["FILMY_PERF_OUT"], !path.isEmpty,
              var line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private func attachReport(_ report: String, name: String) {
        let attachment = XCTAttachment(string: report)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: preview-2: first-use color cube

    /// Spread of recipes by palette weight. makeCubeData is branch-free, so
    /// its cost does not depend on the recipe; this only varies the inputs.
    private static func heavyCubeRecipes(count: Int) -> [FilmRecipe] {
        func weight(_ recipe: FilmRecipe) -> Double {
            let character = abs(recipe.colorChrome) + abs(recipe.blueResponse) + abs(recipe.fxBlue)
            let mixes = abs(recipe.palette.redGreenMix) + abs(recipe.palette.greenBlueMix)
            return character + mixes + abs(recipe.palette.blueRedMix)
        }
        return Array(FilmRecipe.builtIns.sorted { weight($0) > weight($1) }.prefix(count))
    }

    /// Fresh = a cube key the process has never built (redBias nudged by a
    /// random sub-visible amount). Warm = the third render of that recipe.
    /// A pair whose warm render is not faster than the fresh one by at least
    /// `suspectBelowMS` may have rebuilt the cube (NSCache is not strict LRU),
    /// so such pairs are counted and returned, never dropped.
    private static func freshAndWarmRenders(
        recipes: [FilmRecipe],
        scene: CIImage,
        pixels: Bool,
        suspectBelowMS: Double
    ) -> (fresh: [PerfSample], warm: [PerfSample], suspect: Int) {
        let salt = Double.random(in: 0.001..<0.002)
        var fresh: [PerfSample] = []
        var warm: [PerfSample] = []
        var suspect = 0
        for (index, base) in recipes.enumerated() {
            for trial in 0..<6 {
                var recipe = base
                recipe.palette.redBias += salt + Double(index * 10 + trial + 1) * 1e-7
                let nudged = recipe
                let run: () -> Void = {
                    autoreleasepool {
                        let out = FilmRenderer.render(scene, recipe: nudged, quality: .preview)
                        if pixels { _ = FilmRenderer.outputCGImage(out, from: scene.extent) }
                    }
                }
                let first = timed(.thread, run)
                _ = timed(.thread, run)
                let third = timed(.thread, run)
                fresh.append(first)
                warm.append(third)
                if third.cpuMS > first.cpuMS - suspectBelowMS { suspect += 1 }
            }
        }
        return (fresh, warm, suspect)
    }

    func testMeasureColorCubeFirstUse() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let scene = FilmRenderer.sampleScene(size: CGSize(width: 96, height: 64))
        let recipes = Self.heavyCubeRecipes(count: 5)
        XCTAssertEqual(recipes.count, 5)
        FilmRenderer.warmUp(recipe: recipes[0])
        var report = ""
        var build: [PerfSample] = []
        var cubeBytes = 0
        for recipe in recipes {
            for _ in 0..<6 {
                build.append(Self.timed(.thread) {
                    cubeBytes = FilmRenderer.makeCubeData(dimension: 32, recipe: recipe).count
                })
            }
        }
        XCTAssertEqual(cubeBytes, 32 * 32 * 32 * 4 * MemoryLayout<Float>.stride)
        Self.record(id: "preview-2", metric: "cube_build_direct", samples: build, clock: .thread,
                    note: "DECISION METRIC is cpu_thread of this one: FilmRenderer.makeCubeData(32), no cache, 5 recipes x 6; the render_* deltas also carry other per-render noise",
                    into: &report)
        let buildMedian = Self.median(build.map(\.cpuMS))
        for pixels in [false, true] {
            let kind = pixels ? "pixels" : "graph"
            let runs = Self.freshAndWarmRenders(recipes: recipes, scene: scene, pixels: pixels, suspectBelowMS: buildMedian * 0.5)
            XCTAssertEqual(runs.fresh.count, 30)
            let delta = zip(runs.fresh, runs.warm).map {
                PerfSample(wallMS: $0.wallMS - $1.wallMS, cpuMS: $0.cpuMS - $1.cpuMS)
            }
            let variant: String = pixels
                ? "; pixels variant evaluates the render, read wall (upload and GPU are off-thread)"
                : "; graph variant never evaluates pixels, so Core Image upload of the new cube is excluded"
            let note = "5 recipes x 6 never-built cube keys, 96x64 input, 32^3 cube; thread CPU only; warm_not_faster_pairs=\(runs.suspect)/30 (warm render not faster than fresh by half a direct build: cube may have been rebuilt or evicted, the delta then understates)" + variant
            Self.record(id: "preview-2", metric: "render_fresh_\(kind)", samples: runs.fresh, clock: .thread, note: note, preferWall: pixels, into: &report)
            Self.record(id: "preview-2", metric: "render_warm_\(kind)", samples: runs.warm, clock: .thread, note: note, preferWall: pixels, into: &report)
            Self.record(id: "preview-2", metric: "fresh_minus_warm_\(kind)", samples: delta, clock: .thread, note: note, preferWall: pixels, into: &report)
        }
        attachReport(report, name: "measure-preview-2-color-cube")
    }

    // MARK: library-5: catalog decode

    func testMeasureCatalogDecodeWarm() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let bundled = Bundle.main.url(forResource: "RecipeCatalog", withExtension: "json")
        let fallback = Bundle(for: FilmRenderer.self).url(forResource: "RecipeCatalog", withExtension: "json")
        let url = try XCTUnwrap(bundled ?? fallback)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var read: [PerfSample] = []
        var decode: [PerfSample] = []
        var convert: [PerfSample] = []
        var sources: [PerfSample] = []
        var total: [PerfSample] = []
        var records: [RecipeCatalog.Record] = []
        var issues = 0
        var converted = 0
        var sourceCount = 0
        for _ in 0..<12 {
            var data = Data()
            let first = Self.timed(.thread) { data = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data() }
            let second = Self.timed(.thread) {
                let result = RecipeCatalog.decode(data)
                records = result.records
                issues = result.issues.count
            }
            let third = Self.timed(.thread) { converted = records.map(\.recipe).count }
            let fourth = Self.timed(.thread) {
                sourceCount = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.source) }).count
            }
            read.append(first)
            decode.append(second)
            convert.append(third)
            sources.append(fourth)
            total.append(PerfSample(wallMS: first.wallMS + second.wallMS + third.wallMS + fourth.wallMS,
                                    cpuMS: first.cpuMS + second.cpuMS + third.cpuMS + fourth.cpuMS))
        }
        XCTAssertEqual(issues, 0)
        XCTAssertFalse(records.isEmpty)
        XCTAssertEqual(converted, records.count)
        XCTAssertEqual(sourceCount, records.count)
        XCTAssertEqual(records.count, RecipeCatalog.records.count)
        var report = ""
        let note = "bytes=\(bytes) records=\(records.count) builtIns=\(FilmRecipe.builtIns.count); WARM decode in a hosted app that already ran RecipeCatalog.loaded (Foundation JSON and Codable metadata caches, heap and page cache warm); a lower bound for a cold A13 launch; excludes the rest of the static-init chain and any main-thread lock wait"
        Self.record(id: "library-5", metric: "catalog_read_warm", samples: read, clock: .thread, note: note, into: &report)
        Self.record(id: "library-5", metric: "catalog_decode_warm", samples: decode, clock: .thread, note: note, into: &report)
        Self.record(id: "library-5", metric: "catalog_to_recipes_warm", samples: convert, clock: .thread, note: note, into: &report)
        Self.record(id: "library-5", metric: "catalog_sources_dictionary_warm", samples: sources, clock: .thread, note: note, into: &report)
        Self.record(id: "library-5", metric: "catalog_total_warm", samples: total, clock: .thread, note: note, into: &report)
        Self.record(id: "library-5", metric: "catalog_total_warm_first_sample", samples: Array(total.prefix(1)), clock: .thread,
                    note: note + "; first sample in this test, not first in the process: do not compare to a cold-launch threshold, only a value above it is informative", into: &report)
        attachReport(report, name: "measure-library-5-catalog-decode")
    }

    // MARK: library-2: saved-frame metadata index

    private static func syntheticMetadataIndex(count: Int) throws -> Data {
        let recipes = FilmRecipe.builtIns
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var entries: [String: SavedFrameMetadata] = [:]
        for index in 0..<count {
            let key = "\(UUID().uuidString)/L0/001"
            let capturedAt = base.addingTimeInterval(Double(index) * 37)
            entries[key] = SavedFrameMetadata(recipe: recipes[index % recipes.count], capturedAt: capturedAt)
        }
        return try JSONEncoder().encode(entries)
    }

    @MainActor
    func testMeasureSavedFrameIndexDecode() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let key = "filmyCamera.savedFrameMetadata"
        let suite = "RendererPerformanceTests.index.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var report = ""
        for count in [500, 2000, 5000] {
            let data = try Self.syntheticMetadataIndex(count: count)
            defaults.set(data, forKey: key)
            var loadedCounts: [Int] = []
            var reads: [PerfSample] = []
            var decodes: [PerfSample] = []
            for _ in 0..<30 {
                reads.append(Self.timed(.thread) { _ = defaults.data(forKey: key) })
                var loaded = 0
                decodes.append(Self.timed(.thread) { loaded = PhotoLibraryService.loadMetadata(forKey: key, defaults: defaults).count })
                loadedCounts.append(loaded)
            }
            XCTAssertEqual(Set(loadedCounts), [count], "every synthetic entry must decode in every iteration")
            let note = "entries=\(count) json_bytes=\(data.count) recipes cycled from builtIns; throwaway UserDefaults suite, main thread; WARM decode (plist and Codable metadata already loaded), a lower bound for init on launch; defaults_read is a copy-on-write Data return and says nothing about the plist load; the resource index is lazy and not in init"
            Self.record(id: "library-2", metric: "defaults_read_\(count)", samples: reads, clock: .thread, note: note, into: &report)
            Self.record(id: "library-2", metric: "index_load_\(count)", samples: decodes, clock: .thread, note: note, into: &report)
        }
        attachReport(report, name: "measure-library-2-saved-frame-index")
    }

    // MARK: swiftui-7: look library filter

    private struct LookQuery {
        let name: String
        let text: String
        let expectHits: Bool
        let containsSeed: Bool
    }

    /// Greedy: the most frequent token (3+ characters) across the searchable
    /// texts, then the most frequent among the looks that already contain it,
    /// and so on. Returns the tokens and how many looks contain all of them.
    private static func commonSearchWords(_ texts: [String]) -> (words: [String], coverage: Int) {
        var pool: [Set<String>] = texts.map { text in
            Set(text.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { $0.count >= 3 })
        }
        var chosen: [String] = []
        for _ in 0..<3 {
            var counts: [String: Int] = [:]
            for tokens in pool {
                for token in tokens where !chosen.contains(token) { counts[token, default: 0] += 1 }
            }
            let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            guard let best = ranked.first?.key else { break }
            chosen.append(best)
            pool = pool.filter { $0.contains(best) }
        }
        return (chosen, pool.count)
    }

    func testMeasureLookLibraryResults() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let recipes = FilmRecipe.builtIns
        let seed = try XCTUnwrap(RecipeCatalog.sourcedRecipes.first)
        let words = RecipeCatalog.searchText(for: seed).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let usable = try XCTUnwrap(words.count >= 3 ? words : nil)
        let common = Self.commonSearchWords(recipes.map { RecipeCatalog.searchText(for: $0) })
        let commonWords = try XCTUnwrap(common.words.count == 3 ? common.words : nil)
        let queries: [LookQuery] = [
            LookQuery(name: "empty", text: "", expectHits: true, containsSeed: true),
            LookQuery(name: "one_word", text: usable[0], expectHits: true, containsSeed: true),
            LookQuery(name: "three_word_selective", text: usable.prefix(3).joined(separator: " "), expectHits: true, containsSeed: true),
            LookQuery(name: "three_word_common", text: commonWords.joined(separator: " "), expectHits: true, containsSeed: false),
            LookQuery(name: "partial_2char", text: String(commonWords[0].prefix(2)), expectHits: true, containsSeed: false),
            LookQuery(name: "no_match", text: "zzqxjv", expectHits: false, containsSeed: false)
        ]
        var report = ""
        for query in queries {
            var hits: [FilmRecipe] = []
            let run = { hits = LookLibraryIndex.results(in: recipes, query: query.text, filter: .all, favorites: []) }
            run()
            var samples: [PerfSample] = []
            for _ in 0..<30 { samples.append(Self.timed(.thread, run)) }
            XCTAssertEqual(!hits.isEmpty, query.expectHits, query.name)
            if query.containsSeed { XCTAssertTrue(hits.contains { $0.id == seed.id }, query.name) }
            if query.text.isEmpty { XCTAssertEqual(hits.count, recipes.count) }
            let extra = query.name == "three_word_common" ? "; \(common.coverage) looks contain all three tokens" : ""
            let note = "looks=\(recipes.count) query='\(query.text)' hits=\(hits.count)\(extra); filter all, no favorites; one untimed call first; the selective 3-word seed short-circuits after word 1, the common one does not; steady state (RecipeCatalog search index already built)"
            Self.record(id: "swiftui-7", metric: "results_\(query.name)", samples: samples, clock: .thread, note: note, into: &report)
        }
        attachReport(report, name: "measure-swiftui-7-look-library-results")
    }

    // MARK: swiftui-3: recipe getters

    @MainActor
    func testMeasureRecipeGetters() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let suite = "RendererPerformanceTests.getters.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CameraViewModel(defaults: defaults)
        let fullAccess = MembershipStore.shared.hasFullAccess
        let monetization = MonetizationConfiguration.isEnabled
        if !fullAccess { print("PERF_WARNING swiftui-3 hasFullAccess=false: recipe(for:) skips the recipeOverrides lookup the Release build pays") }
        let readRecipes: (CameraViewModel) -> Int = { $0.recipes.count }
        let readQuick: (CameraViewModel) -> Int = { $0.quickRecipes.count }
        let readNavigation: (CameraViewModel) -> Int = { $0.quickNavigationRecipes.count }
        let getters: [(String, (CameraViewModel) -> Int)] = [
            ("recipes", readRecipes),
            ("quickRecipes", readQuick),
            ("quickNavigationRecipes", readNavigation)
        ]
        var report = ""
        for (name, read) in getters {
            var count = read(model)
            var samples: [PerfSample] = []
            for _ in 0..<100 { samples.append(Self.timed(.thread) { count = read(model) }) }
            XCTAssertGreaterThan(count, 0)
            let note = "per read, 100 reads after one untimed read; count=\(count); builtIns=\(FilmRecipe.builtIns.count); default preferences; MembershipStore.shared.hasFullAccess=\(fullAccess) MonetizationConfiguration.isEnabled=\(monetization) recipeOverrides empty (Release has monetization NO, so hasFullAccess true and the override lookup is paid per look)"
            Self.record(id: "swiftui-3", metric: "getter_\(name)", samples: samples, clock: .thread, note: note, into: &report)
        }
        attachReport(report, name: "measure-swiftui-3-recipe-getters")
    }

    // MARK: capture-4: Fuji burst thumbnail

    /// Utility-QoS render loop that stands in for develop and Photos work
    /// running beside the thumbnail task.
    private final class PerfBackgroundLoad: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        private let group = DispatchGroup()

        private var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func start(scene: CIImage, recipe: FilmRecipe) {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                while !isStopped {
                    autoreleasepool {
                        let out = FilmRenderer.render(scene, recipe: recipe, quality: .preview)
                        _ = FilmRenderer.outputCGImage(out, from: scene.extent)
                    }
                }
                group.leave()
            }
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
            group.wait()
        }
    }

    func testMeasureFujiBurstThumbnail() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let scene = Self.syntheticFrame(size: CGSize(width: 4032, height: 3024))
        let cgImage = try XCTUnwrap(FilmRenderer.outputCGImage(scene))
        XCTAssertGreaterThanOrEqual(cgImage.width * cgImage.height, 12_000_000)
        let data = try XCTUnwrap(UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9))
        XCTAssertGreaterThanOrEqual(data.count, 3_000_000, "fixture must carry camera-like detail")
        var edges: [Int] = []
        let measure: () -> PerfSample = {
            var edge = 0
            let sample = Self.timed(.process) {
                if let source = CIImage(data: data),
                   let thumbnail = try? FujiImageProcessor.thumbnail(source, edge: 512) {
                    edge = max(thumbnail.image.width, thumbnail.image.height)
                }
            }
            edges.append(edge)
            return sample
        }
        var samples: [PerfSample] = []
        for _ in 0..<31 { samples.append(measure()) }
        let loaded = edges.count
        let loadScene = FilmRenderer.sampleScene(size: CGSize(width: 1280, height: 960))
        let load = PerfBackgroundLoad()
        load.start(scene: loadScene, recipe: FilmRecipe.builtIns[0])
        var contended: [PerfSample] = []
        for _ in 0..<15 { contended.append(measure()) }
        load.stop()
        XCTAssertEqual(edges.count, loaded + 15)
        for edge in edges { XCTAssertTrue((400...512).contains(edge), "thumbnail edge \(edge)") }
        var report = ""
        let note = "CIImage(data:) + FujiImageProcessor.thumbnail(edge: 512) of a \(cgImage.width)x\(cgImage.height) noisy JPEG (\(data.count) bytes); simulator software JPEG decode, not A-series hardware decode, so only a value above the threshold is conclusive; cpu_process clock"
        Self.record(id: "capture-4", metric: "thumbnail_first_call", samples: Array(samples.prefix(1)), clock: .process,
                    note: note + "; first call after the fixture build, so the shared context, Metal and the JPEG codec are warm; Fuji context cold only if no earlier Fuji work ran in this process", preferWall: true, into: &report)
        Self.record(id: "capture-4", metric: "thumbnail_warm", samples: Array(samples.dropFirst()), clock: .process, note: note, preferWall: true, into: &report)
        Self.record(id: "capture-4", metric: "thumbnail_contended", samples: contended, clock: .process,
                    note: note + "; with a concurrent utility-QoS 1280x960 render loop running (its CPU is inside cpu_process)", preferWall: true, into: &report)
        attachReport(report, name: "measure-capture-4-fuji-thumbnail")
    }

    // MARK: swiftui-6: swatch render versus encoded decode

    private static func decodePixels(_ data: Data) -> Int {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return 0 }
        return image.width * image.height
    }

    private static func heicData(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.heic" as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// The input RecipeSwatchRenderer uses: the bundled demo art, aspect-filled
    /// to 384 x 512 and rasterised once through the given context.
    private static func swatchScene(using context: CIContext) -> CIImage? {
        guard let original = UIImage(named: "LookPreviewCafe", in: Bundle(for: FilmRenderer.self), compatibleWith: nil)?.cgImage else {
            return nil
        }
        let bounds = CGRect(x: 0, y: 0, width: 384, height: 512)
        let framed = CameraFrameLayout.aspectFill(CIImage(cgImage: original), in: bounds)
        guard let small = FilmRenderer.outputCGImage(framed, from: bounds, using: context) else { return nil }
        return CIImage(cgImage: small)
    }

    func testMeasureSwatchRenderVersusDiskDecode() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_PERF"] == "1")
        let all = FilmRecipe.builtIns
        FilmRenderer.warmUp(recipe: all[0])
        let step = max(1, all.count / 10)
        let looks = (0..<10).map { all[min($0 * step, all.count - 1)] }
        let contexts: [(String, CIContext)] = [
            ("gpu", FilmRenderer.makeOutputContext()),
            ("software", CIContext(options: FilmRenderer.testContextOptions))
        ]
        var report = ""
        var pngDecode: [PerfSample] = []
        var heicDecode: [PerfSample] = []
        var pngBytes = 0
        var heicBytes = 0
        var warmGPU: [PerfSample] = []
        for (contextIndex, entry) in contexts.enumerated() {
            let scene = try XCTUnwrap(Self.swatchScene(using: entry.1), "LookPreviewCafe asset")
            let salt = Double.random(in: 0.001..<0.002)
            var cold: [PerfSample] = []
            var warm: [PerfSample] = []
            for (index, base) in looks.enumerated() {
                var recipe = base
                recipe.palette.redBias += salt + Double(index + 1) * 1e-7
                let nudged = recipe
                var image: UIImage?
                let run = { image = autoreleasepool { FilmRenderer.previewThumbnail(for: nudged, over: scene, using: entry.1) } }
                cold.append(Self.timed(.process, run))
                for _ in 0..<3 { warm.append(Self.timed(.process, run)) }
                guard let cgImage = image?.cgImage, contextIndex == 0 else {
                    if image?.cgImage == nil { XCTFail("swatch did not render") }
                    continue
                }
                XCTAssertEqual(cgImage.width * cgImage.height, 384 * 512)
                guard let png = image?.pngData() else {
                    XCTFail("swatch did not encode")
                    continue
                }
                pngBytes += png.count
                for _ in 0..<3 {
                    var pixels = 0
                    pngDecode.append(Self.timed(.process) { pixels = Self.decodePixels(png) })
                    XCTAssertEqual(pixels, 384 * 512)
                }
                guard let heic = Self.heicData(cgImage) else { continue }
                heicBytes += heic.count
                for _ in 0..<3 {
                    var pixels = 0
                    heicDecode.append(Self.timed(.process) { pixels = Self.decodePixels(heic) })
                    XCTAssertEqual(pixels, 384 * 512)
                }
            }
            if contextIndex == 0 { warmGPU = warm }
            let note = "10 looks, 384x512 swatch via FilmRenderer.previewThumbnail over the LookPreviewCafe asset (the actor's input) on a \(entry.0) CIContext; FilmRenderer.warmUp first; cold = never-built cube key; cpu_process clock, GPU time not in it"
            Self.record(id: "swiftui-6", metric: "swatch_render_cold_cube_\(entry.0)", samples: cold, clock: .process, note: note, preferWall: true, into: &report)
            Self.record(id: "swiftui-6", metric: "swatch_render_warm_cube_\(entry.0)", samples: warm, clock: .process, note: note, preferWall: true, into: &report)
        }
        let decodeNote = "decode of the gpu-context swatch from in-memory data with ShouldCacheImmediately, no file I/O; png_bytes=\(pngBytes) heic_bytes=\(heicBytes); simulator software HEIC decode, not device hardware decode; cpu_process clock"
        Self.record(id: "swiftui-6", metric: "decode_png", samples: pngDecode, clock: .process, note: decodeNote, preferWall: true, into: &report)
        if heicDecode.isEmpty {
            let line = "PERF swiftui-6 decode_heic unavailable (HEIC encoder returned nil)"
            print(line)
            report += line + "\n"
        } else {
            Self.record(id: "swiftui-6", metric: "decode_heic", samples: heicDecode, clock: .process, note: decodeNote, preferWall: true, into: &report)
        }
        let renderMedian = Self.median(warmGPU.map(\.wallMS))
        let pngMedian = Self.median(pngDecode.map(\.wallMS))
        let heicMedian = Self.median(heicDecode.map(\.wallMS))
        let ratio = { (denominator: Double) -> String in denominator > 0 ? String(format: "%.2f", renderMedian / denominator) : "n/a" }
        let ratioLine = "PERF swiftui-6 ratio render_warm_gpu_wall_median_over_decode_png_wall_median=\(ratio(pngMedian)) over_decode_heic_wall_median=\(ratio(heicMedian))"
        print(ratioLine)
        report += ratioLine + "\n"
        attachReport(report, name: "measure-swiftui-6-swatch-render-vs-decode")
    }
}
