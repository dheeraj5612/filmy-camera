import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import XCTest
@testable import FilmyCamera

final class G7DateStampRendererTests: XCTestCase {
    func testDateTextUsesStableTwoDigitYearMonthDay() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            G7DateStampRenderer.dateText(
                for: Date(timeIntervalSince1970: 0), timeZone: utc
            ),
            "70.01.01"
        )
    }

    func testPreferenceIsNamespacedAndOffUntilOptedIn() {
        let suiteName = "G7DateStampRendererTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(G7DateStampPreferences.enabledKey, "g7x.dateStamp.enabled")
        XCTAssertFalse(G7DateStampPreferences.isEnabled(in: defaults))
        G7DateStampPreferences.setEnabled(true, in: defaults)
        XCTAssertTrue(G7DateStampPreferences.isEnabled(in: defaults))
        G7DateStampPreferences.setEnabled(false, in: defaults)
        XCTAssertFalse(G7DateStampPreferences.isEnabled(in: defaults))
    }

    func testDisabledStampPreservesImageExtent() {
        let extent = CGRect(x: 17, y: 23, width: 640, height: 480)
        let image = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            .cropped(to: extent)
        let stamped = G7DateStampRenderer.applyingStamp(to: image, text: "24.01.31", enabled: false)
        XCTAssertEqual(stamped.extent, image.extent)
    }

    func testEnabledStampKeepsExtentForFractionalOriginAndSize() {
        let extent = CGRect(x: 10.5, y: 7.25, width: 640.5, height: 480.75)
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: extent)
        let stamped = G7DateStampRenderer.applyingStamp(to: image, text: "24.01.31", enabled: true)
        XCTAssertEqual(stamped.extent, image.extent)
    }

    func testEnabledStampRendersInBottomRightOfOutput() {
        let extent = CGRect(x: 0, y: 0, width: 640, height: 480)
        let image = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let stamped = G7DateStampRenderer.applyingStamp(to: image, text: "24.01.31", enabled: true)
        let width = Int(extent.width)
        let height = Int(extent.height)
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                stamped, toBitmap: buffer.baseAddress!, rowBytes: rowBytes,
                bounds: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        var visiblePixels = 0
        var leftmostVisibleX = width
        var topmostVisibleY = height
        for y in 0..<height {
            for x in 0..<width {
                if bytes[(y * rowBytes) + (x * 4) + 3] > 8 {
                    visiblePixels += 1
                    leftmostVisibleX = min(leftmostVisibleX, x)
                    topmostVisibleY = min(topmostVisibleY, y)
                }
            }
        }
        XCTAssertGreaterThan(visiblePixels, 0)
        XCTAssertGreaterThan(leftmostVisibleX, width / 2)
        XCTAssertGreaterThan(topmostVisibleY, height / 2)
    }

    // MARK: Saved still path

    private struct DecodedPixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private func stampFixtureJPEG() throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.95))
    }

    private func renderStill(
        source: Data,
        finish: PhotoFinish,
        outputSettings: ProCaptureSettings?,
        stampEnabled: Bool,
        text: String?
    ) throws -> DecodedPixels {
        let size = CGSize(width: 640, height: 480)
        let rendered = try XCTUnwrap(CameraViewModel.render(
            sourceData: source, recipe: FilmRecipe.builtIns[0], viewportSize: size,
            previewDrawableSize: size, capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            flashFired: false, grainSeed: 1, finish: finish, outputSettings: outputSettings,
            dateStampEnabled: stampEnabled, dateStampText: text
        ))
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(rendered.data as CFData, nil))
        let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drewImage = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drewImage)
        return DecodedPixels(width: width, height: height, bytes: bytes)
    }

    /// Bounding box (top-left origin) of pixels that differ by more than a small tolerance.
    private func differingBounds(_ a: DecodedPixels, _ b: DecodedPixels) -> CGRect? {
        // Callers assert the dimensions; a size mismatch must fail there, not trap here.
        guard a.width == b.width, a.height == b.height, a.bytes.count == b.bytes.count else { return nil }
        var minX = a.width, minY = a.height, maxX = -1, maxY = -1
        for y in 0..<a.height {
            for x in 0..<a.width {
                let index = (y * a.width + x) * 4
                var changed = false
                for channel in 0..<3 where abs(Int(a.bytes[index + channel]) - Int(b.bytes[index + channel])) > 6 {
                    changed = true
                }
                if changed {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func assertStampReachesSavedPixels(
        finish: PhotoFinish,
        outputSettings: ProCaptureSettings?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let source = try stampFixtureJPEG()
        let text = "24.01.31"
        let off = try renderStill(source: source, finish: finish, outputSettings: outputSettings, stampEnabled: false, text: nil)
        let offWithText = try renderStill(source: source, finish: finish, outputSettings: outputSettings, stampEnabled: false, text: text)
        let on = try renderStill(source: source, finish: finish, outputSettings: outputSettings, stampEnabled: true, text: text)

        XCTAssertEqual(on.width, off.width, file: file, line: line)
        XCTAssertEqual(on.height, off.height, file: file, line: line)
        XCTAssertEqual(offWithText.width, off.width, file: file, line: line)
        XCTAssertEqual(offWithText.height, off.height, file: file, line: line)
        XCTAssertNil(differingBounds(off, offWithText), "A disabled stamp must not change pixels", file: file, line: line)
        let bounds = try XCTUnwrap(differingBounds(off, on), "The enabled stamp left no mark", file: file, line: line)
        XCTAssertGreaterThan(bounds.minX, CGFloat(off.width) / 2, file: file, line: line)
        XCTAssertGreaterThan(bounds.minY, CGFloat(off.height) / 2, file: file, line: line)
        if finish == .instantPrint {
            let layout = try XCTUnwrap(PhotoPrintCompositor.layout(
                for: CGRect(x: 0, y: 0, width: 640, height: 480), finish: finish
            ), file: file, line: line)
            XCTAssertEqual(CGFloat(off.width), layout.canvasExtent.width, accuracy: 1, file: file, line: line)
            XCTAssertEqual(CGFloat(off.height), layout.canvasExtent.height, accuracy: 1, file: file, line: line)
            XCTAssertGreaterThanOrEqual(bounds.minY, CGFloat(off.height) - layout.bottomMargin, file: file, line: line)
        }
    }

    func testStampReachesSavedJPEGPathOnlyWhenEnabled() throws {
        try assertStampReachesSavedPixels(finish: .photo, outputSettings: nil)
    }

    func testStampReachesSavedProPathOnlyWhenEnabled() throws {
        var settings = ProCaptureSettings()
        settings.format = .jpeg
        settings.colorGamut = .sRGB
        try assertStampReachesSavedPixels(finish: .photo, outputSettings: settings)
    }

    func testStampStaysInsideInstantPrintCanvas() throws {
        try assertStampReachesSavedPixels(finish: .instantPrint, outputSettings: nil)
    }

    func testStampStaysInsideInstantPrintCanvasOnProPath() throws {
        var settings = ProCaptureSettings()
        settings.format = .jpeg
        settings.colorGamut = .sRGB
        try assertStampReachesSavedPixels(finish: .instantPrint, outputSettings: settings)
    }
}
