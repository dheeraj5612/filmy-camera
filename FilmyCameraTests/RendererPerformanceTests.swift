import CoreImage
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
}
