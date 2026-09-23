import CoreGraphics
import CoreImage
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

    func testPreferenceIsNamespacedAndDisabledForFilmyTarget() {
        let suiteName = "G7DateStampRendererTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(G7DateStampPreferences.enabledKey, "g7x.dateStamp.enabled")
        XCTAssertFalse(G7DateStampPreferences.isEnabled(in: defaults))
    }

    func testDisabledStampPreservesImageExtent() {
        let extent = CGRect(x: 17, y: 23, width: 640, height: 480)
        let image = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            .cropped(to: extent)
        let stamped = G7DateStampRenderer.applyingStamp(to: image, text: "24.01.31", enabled: false)
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
}
