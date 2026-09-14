import CoreImage
import CryptoKit
import UIKit
import XCTest
@testable import FilmyCamera

#if DEBUG
final class RendererSkinCaptureDiagnosticsTests: XCTestCase {
    /// Opt-in investigation on a locally supplied capture. Personal source
    /// photographs remain outside the repository and normal test runs.
    func testExportStagesForLocalSkinCapture() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["FILMY_SKIN_DIAGNOSTIC_INPUT"],
              let outputPath = environment["FILMY_SKIN_DIAGNOSTIC_OUTPUT"] else {
            throw XCTSkip("Supply a local diagnostic capture and output directory")
        }
        let caches = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let inputDirectory = inputPath == "app-cache"
            ? caches.appendingPathComponent("FilmyCaptureDiagnostics/latest", isDirectory: true)
            : URL(fileURLWithPath: inputPath, isDirectory: true)
        let outputDirectory = outputPath == "app-cache"
            ? caches.appendingPathComponent("FilmyRenderDiagnostics", isDirectory: true)
            : URL(fileURLWithPath: outputPath, isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadataData = try Data(contentsOf: inputDirectory.appendingPathComponent("metadata.json"))
        let metadata = try decoder.decode(
            FilmyCaptureDiagnostics.Metadata.self,
            from: metadataData
        )
        let sourceData = try Data(contentsOf: inputDirectory.appendingPathComponent("source.capture"))
        let sourceHash = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(sourceHash, metadata.sourceDataSHA256)
        let input = try XCTUnwrap(CIImage(
            data: sourceData,
            options: [.applyOrientationProperty: true]
        ))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try metadataData.write(to: outputDirectory.appendingPathComponent("capture-metadata.json"))
        let provenance = [
            "rendererVersion": FilmRecipe.rendererVersion,
            "appBuild": PhotoOutputEncoder.currentApplicationBuild,
            "sourceDataSHA256": sourceHash
        ]
        try JSONEncoder().encode(provenance).write(to: outputDirectory.appendingPathComponent("render-info.json"))
        let viewport = CGSize(width: metadata.viewportSize.width, height: metadata.viewportSize.height)
        let crop = CameraFrameLayout.aspectFillCrop(sourceExtent: input.extent, targetSize: viewport)
        let framed = input.cropped(to: crop).transformed(by: CGAffineTransform(
            translationX: -crop.minX, y: -crop.minY
        ))
        let replay = try XCTUnwrap(CameraViewModel.render(
            sourceData: sourceData,
            recipe: metadata.recipe,
            viewportSize: viewport,
            previewDrawableSize: CGSize(width: metadata.previewDrawableSize.width, height: metadata.previewDrawableSize.height),
            capturedAt: metadata.capturedAt,
            flashFired: metadata.flashFired,
            grainSeed: metadata.grainSeed,
            finish: metadata.finish
        ))
        try replay.data.write(to: outputDirectory.appendingPathComponent("capture-replay.jpg"))
        let compact = try XCTUnwrap(FilmRecipe.builtIns.first { $0.id == "g7x-compact" })
        let compactLabel = metadata.recipe.id == compact.id ? "g7x-compact-built-in" : compact.id
        var variants = [(metadata.recipe.id, metadata.recipe), (compactLabel, compact)]
        if environment["FILMY_SKIN_DIAGNOSTIC_VARIANTS"] == "1" {
            var noShadow = metadata.recipe
            noShadow.tone.shadow = 0
            var noDetail = metadata.recipe
            noDetail.sharpness = 0
            noDetail.clarity = 0
            noDetail.noiseReduction = 0
            var noHalation = metadata.recipe
            noHalation.halation = 0
            variants += [("no-shadow", noShadow), ("no-detail", noDetail), ("no-halation", noHalation)]
        }
        let manifest = variants.reduce(into: [String: FilmRecipe]()) { result, entry in
            result[entry.0] = entry.1
        }
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: outputDirectory.appendingPathComponent("variant-manifest.json"))
        for (label, recipe) in variants {
            let destination = outputDirectory.appendingPathComponent(label, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let phase = CameraViewModel.scaledGrainPhase(
                metadata.grainSeed,
                grainSize: recipe.grainSize,
                previewSize: CGSize(width: metadata.previewDrawableSize.width, height: metadata.previewDrawableSize.height),
                stillSize: framed.extent.size
            )
            let stages = FilmRenderer.diagnosticRenderStages(
                framed,
                recipe: recipe,
                captureContext: .init(flashFired: metadata.flashFired),
                grainSeed: metadata.grainSeed,
                grainPhase: phase
            )
            XCTAssertNotNil(stages[.source])
            XCTAssertNotNil(stages[.final])
            for (stage, image) in stages.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                try autoreleasepool {
                    let bitmap = try XCTUnwrap(FilmRenderer.outputCGImage(image))
                    let png = try XCTUnwrap(UIImage(cgImage: bitmap).pngData())
                    try png.write(to: destination.appendingPathComponent(stage.rawValue + ".png"))
                }
            }
        }
    }
}
#endif
