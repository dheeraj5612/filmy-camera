import XCTest
@testable import FilmyCamera

final class CaptureModesPolicyTests: XCTestCase {
    func testEveryModeHasStableIdentityAndBoundedCapture() {
        XCTAssertEqual(Set(CaptureMode.allCases.map(\.rawValue)).count, CaptureMode.allCases.count)
        for mode in CaptureMode.allCases {
            XCTAssertEqual(CaptureMode(rawValue: mode.rawValue), mode)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.guidance.isEmpty)
            XCTAssertTrue((1...40).contains(mode.frameLimit))
            XCTAssertLessThanOrEqual(mode.minimumFrames, mode.frameLimit)
        }
    }

    func testExactlyOnePhotoMayBeInFlightAndDuplicatesAreRejected() {
        var sequence = CaptureSequence(mode: .burst)
        XCTAssertEqual(sequence.reserveFrame(), 0)
        XCTAssertNil(sequence.reserveFrame())
        XCTAssertFalse(sequence.completeFrame(1))
        XCTAssertTrue(sequence.completeFrame(0))
        XCTAssertFalse(sequence.completeFrame(0))
        XCTAssertEqual(sequence.reserveFrame(), 1)
    }

    func testEverySequenceStopsAtItsLimit() {
        for mode in CaptureMode.allCases {
            var sequence = CaptureSequence(mode: mode)
            for index in 0..<mode.frameLimit {
                XCTAssertEqual(sequence.reserveFrame(), index)
                XCTAssertNil(sequence.reserveFrame())
                XCTAssertTrue(sequence.completeFrame(index))
            }
            XCTAssertTrue(sequence.shouldFinish)
            XCTAssertNil(sequence.reserveFrame())
        }
    }

    func testStopDrainsExistingCaptureButCannotScheduleAnother() {
        var sequence = CaptureSequence(mode: .night)
        XCTAssertEqual(sequence.reserveFrame(), 0)
        sequence.requestStop()
        XCTAssertFalse(sequence.shouldFinish)
        XCTAssertNil(sequence.reserveFrame())
        XCTAssertTrue(sequence.completeFrame(0))
        XCTAssertTrue(sequence.shouldFinish)
        XCTAssertNil(sequence.reserveFrame())
    }

    func testStopBeforeFirstFrameIsImmediate() {
        var sequence = CaptureSequence(mode: .panorama)
        sequence.requestStop()
        XCTAssertTrue(sequence.shouldFinish)
        XCTAssertNil(sequence.reserveFrame())
    }

    func testMacroNeedsAutofocusAndKnownCloseFocusDistance() {
        XCTAssertTrue(CaptureModesPolicy.supportsMacro(minimumFocusDistance: 20, autofocus: true))
        for distance in [-1, 0, 51, 1_000] {
            XCTAssertFalse(CaptureModesPolicy.supportsMacro(minimumFocusDistance: distance, autofocus: true))
        }
        XCTAssertFalse(CaptureModesPolicy.supportsMacro(minimumFocusDistance: 20, autofocus: false))
    }

    func testRegistrationAndPanoramaRejectUnsafeGeometry() {
        XCTAssertTrue(CaptureModesPolicy.acceptableNightTranslation(x: 8, y: -8, width: 100, height: 100))
        XCTAssertFalse(CaptureModesPolicy.acceptableNightTranslation(x: 9, y: 0, width: 100, height: 100))
        XCTAssertFalse(CaptureModesPolicy.acceptableNightTranslation(x: .nan, y: 0, width: 100, height: 100))
        XCTAssertFalse(CaptureModesPolicy.acceptableNightTranslation(x: 0, y: 0, width: 0, height: 100))
        XCTAssertTrue(CaptureModesPolicy.acceptablePanoramaBounds(width: 12_000, height: 2_000))
        for (width, height) in [(12_001.0, 100.0), (12_000, 2_001), (1, 12_001), (.infinity, 100), (100, .nan), (-1, 100)] {
            XCTAssertFalse(CaptureModesPolicy.acceptablePanoramaBounds(width: width, height: height))
        }
    }

    func testScannedCodesCannotLaunchCustomSchemesOrCredentials() {
        for value in ["javascript:alert(1)", "file:///private/a", "data:text/html,hello", "shortcuts://run-shortcut?name=x",
                      "https://user:password@example.com", "https://example.com/\nattack", "//example.com", "not a URL"] {
            XCTAssertNil(CaptureModesPolicy.safeWebURL(value), value)
        }
        XCTAssertEqual(CaptureModesPolicy.safeWebURL("https://example.com/photo?q=film")?.host, "example.com")
    }

    func testOnlySinglePathComponentsCanAddressCaptureFiles() {
        for value in ["", ".", "..", "../escape", "/etc/passwd", "folder/file", "folder\\file", "photo\u{0}"] {
            XCTAssertFalse(CaptureModesPolicy.isSafeFilename(value), value)
        }
        XCTAssertTrue(CaptureModesPolicy.isSafeFilename("original-000.heic"))
    }

    func testPhotosReceiptRequiresEveryOutput() {
        var media = CaptureMedia(id: UUID(), mode: .burst, createdAt: Date(), recipeName: "Test")
        XCTAssertFalse(media.isExported)
        media.outputs = ["a.heic", "b.heic"]
        media.photosIdentifiers = ["a.heic": "asset-a"]
        XCTAssertFalse(media.isExported)
        media.photosIdentifiers["b.heic"] = "asset-b"
        XCTAssertTrue(media.isExported)
    }

    func testManifestRoundTripRetainsRecoveryAndExportState() throws {
        var media = CaptureMedia(id: UUID(), mode: .night, createdAt: Date(timeIntervalSince1970: 1), recipeName: "Test")
        media.originals = ["original-000.heic", "original-001.heic", "original-002.heic"]
        media.notes = ["Interrupted during processing"]
        let decoded = try JSONDecoder().decode(CaptureMedia.self, from: JSONEncoder().encode(media))
        XCTAssertEqual(decoded.id, media.id)
        XCTAssertEqual(decoded.originals, media.originals)
        XCTAssertEqual(decoded.status, .originalsOnly)
        XCTAssertEqual(decoded.notes, media.notes)
    }
}
