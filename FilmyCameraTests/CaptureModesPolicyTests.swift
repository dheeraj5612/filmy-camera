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

    func testMicrophoneNoticeShowsOncePerDenial() {
        let first = CaptureModesPolicy.microphoneNotice(isVideo: true, wantsMicrophone: true, audioAllowed: false, alreadyShown: false)
        XCTAssertTrue(first.show && first.shown)
        let repeated = CaptureModesPolicy.microphoneNotice(isVideo: true, wantsMicrophone: true, audioAllowed: false, alreadyShown: true)
        XCTAssertFalse(repeated.show)
        XCTAssertTrue(repeated.shown)
        let granted = CaptureModesPolicy.microphoneNotice(isVideo: true, wantsMicrophone: true, audioAllowed: true, alreadyShown: true)
        XCTAssertFalse(granted.show || granted.shown)
        let unwanted = CaptureModesPolicy.microphoneNotice(isVideo: true, wantsMicrophone: false, audioAllowed: false, alreadyShown: true)
        XCTAssertFalse(unwanted.show || unwanted.shown)
        let photo = CaptureModesPolicy.microphoneNotice(isVideo: false, wantsMicrophone: true, audioAllowed: false, alreadyShown: true)
        XCTAssertFalse(photo.show)
        XCTAssertTrue(photo.shown)
    }

    func testStopIsOfferedOnlyForStoppableWork() {
        XCTAssertTrue(CaptureModesPolicy.isStoppable(phase: .recording, scanning: false))
        XCTAssertFalse(CaptureModesPolicy.isStoppable(phase: .capturing, scanning: true))
        XCTAssertTrue(CaptureModesPolicy.isStoppable(phase: .capturing, scanning: false))
        for idle in [CaptureModesPhase.ready, .processing, .stopped] {
            XCTAssertFalse(CaptureModesPolicy.isStoppable(phase: idle, scanning: false))
        }
    }

    func testFilmLookNoteSaysWhenTheLookIsAddedAndThatOriginalsAreKept() {
        let still = "Film look is added after you shoot. Originals are kept."
        for mode in [CaptureMode.photo, .burst, .macro, .portrait, .night, .panorama] {
            XCTAssertEqual(CaptureModesPolicy.filmLookNote(mode: mode, showingGuidance: true), still)
            XCTAssertEqual(CaptureModesPolicy.filmLookNote(mode: mode, showingGuidance: false), still)
        }
        XCTAssertNil(CaptureModesPolicy.filmLookNote(mode: .filmVideo, showingGuidance: true))
        XCTAssertEqual(CaptureModesPolicy.filmLookNote(mode: .filmVideo, showingGuidance: false),
                       "Film look is added after you stop recording. Originals are kept.")
        XCTAssertNil(CaptureModesPolicy.filmLookNote(mode: .spatialVideo, showingGuidance: true))
        XCTAssertEqual(CaptureModesPolicy.filmLookNote(mode: .spatialVideo, showingGuidance: false),
                       "Spatial video is saved as shot. No film look is added.")
    }

    func testCapturesBadgeHidesZeroAndCapsAtNinetyNine() {
        XCTAssertNil(CaptureModesPolicy.capturesBadge(count: 0))
        XCTAssertNil(CaptureModesPolicy.capturesBadge(count: -1))
        XCTAssertEqual(CaptureModesPolicy.capturesBadge(count: 1), "1")
        XCTAssertEqual(CaptureModesPolicy.capturesBadge(count: 99), "99")
        XCTAssertEqual(CaptureModesPolicy.capturesBadge(count: 100), "99+")
        XCTAssertEqual(CaptureModesPolicy.capturesBadge(count: 5000), "99+")
    }

    func testProcessingMessageSaysSpatialVideoGetsNoFilmLook() {
        XCTAssertEqual(CaptureModesPolicy.processingMessage(mode: .photo), "Developing Photo. Originals are safe.")
        XCTAssertEqual(CaptureModesPolicy.processingMessage(mode: .filmVideo), "Rendering the film look. The original is safe.")
        let spatial = CaptureModesPolicy.processingMessage(mode: .spatialVideo)
        XCTAssertEqual(spatial, "Saving the spatial video as shot.")
        XCTAssertFalse(spatial.contains("Rendering"))
    }

    func testFilmPickerListsOnlyMatchesWithTheCurrentFilmFirst() {
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [true, true, true, true], current: 2), [2, 0, 1, 3])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [true, true, true], current: 0), [0, 1, 2])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [false, true, false, true], current: 3), [3, 1])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [false, true, false, true], current: 2), [1, 3])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [true, true], current: nil), [0, 1])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [true, true], current: 9), [0, 1])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [false, false], current: 0), [])
        XCTAssertEqual(CaptureModesPolicy.filmPickerOrder(matches: [], current: nil), [])
    }

    func testShutterHapticIsLimitedToStillsThatStartFromReady() {
        for mode in CaptureMode.allCases {
            XCTAssertEqual(CaptureModesPolicy.playsShutterHaptic(mode: mode, phase: .ready),
                           [CaptureMode.photo, .burst, .macro, .portrait].contains(mode), mode.rawValue)
            for phase in [CaptureModesPhase.stopped, .configuring, .capturing, .recording, .processing, .unavailable] {
                XCTAssertFalse(CaptureModesPolicy.playsShutterHaptic(mode: mode, phase: phase), "\(mode.rawValue) \(phase.rawValue)")
            }
        }
    }

    func testUnavailableReasonExistsOnlyForHardwareGatedModes() {
        XCTAssertEqual(CaptureModesPolicy.unavailableReason(for: .macro), "Macro needs an ultra-wide camera that focuses up close.")
        XCTAssertEqual(CaptureModesPolicy.unavailableReason(for: .portrait), "Portrait needs a dual, triple or depth camera.")
        XCTAssertEqual(CaptureModesPolicy.unavailableReason(for: .spatialVideo), "Spatial video needs a device that records spatial video.")
        for mode in [CaptureMode.photo, .burst, .filmVideo, .night, .panorama] {
            XCTAssertNil(CaptureModesPolicy.unavailableReason(for: mode), mode.rawValue)
        }
    }

    func testScreenStaysAwakeOnlyWhileTheWorkspaceIsUsable() {
        for usable in [CaptureModesPhase.configuring, .ready, .capturing, .recording, .processing] {
            XCTAssertTrue(CaptureModesPolicy.keepsScreenAwake(sceneActive: true, cameraReleased: true, closing: false, phase: usable))
        }
        for dead in [CaptureModesPhase.unavailable, .stopped] {
            XCTAssertFalse(CaptureModesPolicy.keepsScreenAwake(sceneActive: true, cameraReleased: true, closing: false, phase: dead))
        }
        XCTAssertFalse(CaptureModesPolicy.keepsScreenAwake(sceneActive: false, cameraReleased: true, closing: false, phase: .ready))
        XCTAssertFalse(CaptureModesPolicy.keepsScreenAwake(sceneActive: true, cameraReleased: false, closing: false, phase: .ready))
        XCTAssertFalse(CaptureModesPolicy.keepsScreenAwake(sceneActive: true, cameraReleased: true, closing: true, phase: .ready))
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

    func testCaptureRotationAngleSnapsToQuarterTurnsAndNeverFails() {
        let rows: [(Double?, Double, Double)] = [
            (nil, 90, 90), (nil, 0, 0), (nil, 180, 180), (nil, 270, 270), (nil, 450, 90),
            (nil, Double.nan, 90), (nil, Double.infinity, 90), (Double.nan, 0, 0), (Double.infinity, 180, 180), (-Double.infinity, Double.nan, 90),
            (0, 45, 0), (90, 0, 90), (180, 0, 180), (270, 0, 270),
            (360, 90, 0), (450, 0, 90), (720, 90, 0), (-90, 90, 270), (-180, 90, 180), (-270, 0, 90),
            (-0.0, 90, 0), (-1e-20, 90, 0),
            (44.9, 90, 0), (45, 0, 90), (134.9, 0, 90), (135, 0, 180),
            (224.9, 0, 180), (225, 0, 270), (314.9, 0, 270), (315, 90, 0), (359.9, 90, 0)
        ]
        for row in rows {
            XCTAssertEqual(CaptureModesPolicy.captureRotationAngle(horizonLevel: row.0, fallback: row.1), row.2,
                           "horizon \(String(describing: row.0)) fallback \(row.1)")
        }
        XCTAssertTrue([0.0, 90, 180, 270].contains(CaptureModesPolicy.captureRotationAngle(horizonLevel: 1e300, fallback: 90)))
    }

    func testCaptureRotationAngleIsCardinalAndIdempotent() {
        for fallback in [0.0, 90, 180, 270] {
            var angle = -1080.0
            while angle <= 1080 {
                let result = CaptureModesPolicy.captureRotationAngle(horizonLevel: angle, fallback: fallback)
                XCTAssertTrue([0.0, 90, 180, 270].contains(result), "\(angle)")
                XCTAssertEqual(CaptureModesPolicy.captureRotationAngle(horizonLevel: result, fallback: fallback), result, "\(angle)")
                angle += 7.5
            }
        }
    }

    func testEssentialsRowMatchesTheModeAndHardwareRanges() {
        func essentials(_ mode: CaptureMode, requested: CaptureMode? = nil, zoom: Double = 1,
                        minimum: Double = -2, maximum: Double = 2) -> [CaptureEssential] {
            CaptureModesPolicy.essentials(mode: mode, requestedMode: requested ?? mode, maximumZoom: zoom,
                                          minimumExposure: minimum, maximumExposure: maximum)
        }
        XCTAssertEqual(essentials(.photo), [.film, .exposure])
        XCTAssertEqual(essentials(.photo, zoom: 3), [.film, .zoom, .exposure])
        XCTAssertEqual(essentials(.filmVideo, zoom: 3), [.film, .zoom, .exposure, .microphone])
        XCTAssertEqual(essentials(.filmVideo), [.film, .exposure, .microphone])
        XCTAssertEqual(essentials(.spatialVideo, zoom: 3), [.microphone])
        XCTAssertEqual(essentials(.photo, minimum: 0, maximum: 0), [.film])
        XCTAssertEqual(essentials(.photo, zoom: 3, minimum: 1, maximum: 1), [.film, .zoom])
        // The microphone follows the requested mode while the configured mode is still the old one.
        XCTAssertEqual(essentials(.photo, requested: .filmVideo), [.film, .exposure, .microphone])
    }

    func testModeNotesKeepEveryCaption() {
        let video = "Up to three minutes per clip. Keep Filmy open while developing the film look."
        let spatial = "Up to three minutes per clip. Keep Filmy open while the video is saved."
        let portrait = "Depth-based center-subject bokeh at f/4. The original depth-bearing HEIC is always retained."
        let supported = "Camera Control: shutter, zoom, exposure, mode, film, and focus where supported."
        let unsupported = "On-screen controls remain available without Camera Control hardware."
        XCTAssertEqual(CaptureModesPolicy.modeNotes(requestedMode: .photo, configuredMode: .photo, controlsSupported: true), [supported])
        XCTAssertEqual(CaptureModesPolicy.modeNotes(requestedMode: .photo, configuredMode: .photo, controlsSupported: false), [unsupported])
        XCTAssertEqual(CaptureModesPolicy.modeNotes(requestedMode: .filmVideo, configuredMode: .filmVideo, controlsSupported: false),
                       [video, unsupported])
        XCTAssertEqual(CaptureModesPolicy.modeNotes(requestedMode: .spatialVideo, configuredMode: .spatialVideo, controlsSupported: true),
                       [spatial, supported])
        XCTAssertEqual(CaptureModesPolicy.modeNotes(requestedMode: .portrait, configuredMode: .portrait, controlsSupported: true),
                       [portrait, supported])
    }

    func testModeInfoOpensUnlessCapturing() {
        for open in [CaptureModesPhase.configuring, .ready, .stopped, .unavailable] {
            XCTAssertTrue(CaptureModesPolicy.allowsModeInfo(phase: open), open.rawValue)
        }
        for busy in [CaptureModesPhase.capturing, .recording, .processing] {
            XCTAssertFalse(CaptureModesPolicy.allowsModeInfo(phase: busy), busy.rawValue)
        }
    }

    func testUnavailableSummaryNamesEachMissingMode() {
        XCTAssertNil(CaptureModesPolicy.unavailableSummary([]))
        XCTAssertEqual(CaptureModesPolicy.unavailableSummary([.portrait]),
                       "Not on this device: Portrait needs a dual, triple or depth camera.")
        XCTAssertEqual(CaptureModesPolicy.unavailableSummary([.macro, .portrait, .spatialVideo]),
                       "Not on this device: Macro, Portrait, Spatial video. About this mode lists why.")
    }

    func testThumbnailFilePrefersDevelopedThenOriginalAndRejectsUnsafeNames() {
        XCTAssertEqual(CaptureModesPolicy.thumbnailFile(outputs: ["d.jpg"], originals: ["o.heic"]), "d.jpg")
        XCTAssertEqual(CaptureModesPolicy.thumbnailFile(outputs: [], originals: ["o.heic"]), "o.heic")
        XCTAssertNil(CaptureModesPolicy.thumbnailFile(outputs: [], originals: []))
        XCTAssertNil(CaptureModesPolicy.thumbnailFile(outputs: ["../x"], originals: ["o.heic"]))
    }

    func testPhotosStatusIsWordsNotColour() {
        var media = CaptureMedia(id: UUID(), mode: .burst, createdAt: Date(), recipeName: "Test")
        media.outputs = ["a.jpg", "b.jpg", "c.jpg"]
        let none = CaptureModesPolicy.photosStatus(media)
        XCTAssertEqual(none.text, "Not in Photos")
        XCTAssertEqual(none.symbol, "iphone")
        media.photosIdentifiers = ["a.jpg": "x"]
        let partly = CaptureModesPolicy.photosStatus(media)
        XCTAssertEqual(partly.text, "Partly in Photos")
        XCTAssertEqual(partly.symbol, "circle.lefthalf.filled")
        media.photosIdentifiers = ["a.jpg": "x", "b.jpg": "y", "c.jpg": "z"]
        let all = CaptureModesPolicy.photosStatus(media)
        XCTAssertEqual(all.text, "In Photos")
        XCTAssertEqual(all.symbol, "checkmark.circle")
        for status in [none, partly, all] {
            XCTAssertFalse(status.text.isEmpty)
            XCTAssertFalse(status.symbol.isEmpty)
            XCTAssertFalse(status.text.localizedCaseInsensitiveContains("originals"))
        }
    }

    func testShareLabelsAreNumberedByKindNotFileName() {
        XCTAssertEqual(CaptureModesPolicy.shareLabel(original: false, isVideo: false, index: 0), "Share photo 1")
        XCTAssertEqual(CaptureModesPolicy.shareLabel(original: false, isVideo: true, index: 1), "Share video 2")
        XCTAssertEqual(CaptureModesPolicy.shareLabel(original: true, isVideo: false, index: 0), "Share original 1")
    }

    func testShotStartsOnlyFromReadyAndNeverForSceneReading() {
        for next in [CaptureModesPhase.capturing, .recording, .processing] {
            XCTAssertTrue(CaptureModesPolicy.startsShot(from: .ready, to: next, scanning: false), next.rawValue)
        }
        XCTAssertFalse(CaptureModesPolicy.startsShot(from: .ready, to: .capturing, scanning: true))
        XCTAssertFalse(CaptureModesPolicy.startsShot(from: .capturing, to: .processing, scanning: false))
        XCTAssertFalse(CaptureModesPolicy.startsShot(from: .ready, to: .ready, scanning: false))
    }

    func testFinishedCaptureIgnoresKnownAndPreSessionRecords() {
        let opened = Date(timeIntervalSince1970: 1_000)
        let older = CaptureMedia(id: UUID(), mode: .burst, createdAt: opened.addingTimeInterval(-60), recipeName: "Test")
        let retried = CaptureMedia(id: UUID(), mode: .burst, createdAt: opened.addingTimeInterval(10), recipeName: "Test")
        let fresh = CaptureMedia(id: UUID(), mode: .burst, createdAt: opened.addingTimeInterval(20), recipeName: "Test")
        let newest = CaptureMedia(id: UUID(), mode: .burst, createdAt: opened.addingTimeInterval(30), recipeName: "Test")
        XCTAssertNil(CaptureModesPolicy.finishedCapture(in: [older], known: [], openedAt: opened))
        XCTAssertNil(CaptureModesPolicy.finishedCapture(in: [retried], known: [retried.id], openedAt: opened))
        XCTAssertEqual(CaptureModesPolicy.finishedCapture(in: [fresh, retried], known: [retried.id], openedAt: opened)?.id, fresh.id)
        XCTAssertEqual(CaptureModesPolicy.finishedCapture(in: [newest, fresh], known: [], openedAt: opened)?.id, newest.id)
    }

    func testSavedCardStatusSaysWhereTheShotIs() {
        var media = CaptureMedia(id: UUID(), mode: .burst, createdAt: Date(), recipeName: "Test")
        let notApplied = CaptureModesPolicy.savedCardStatus(media)
        XCTAssertEqual(notApplied.text, "Film look not applied. Open to retry.")
        media.outputs = ["a.jpg", "b.jpg"]
        let none = CaptureModesPolicy.savedCardStatus(media)
        XCTAssertEqual(none.text, "Not in Photos")
        media.photosIdentifiers = ["a.jpg": "x"]
        let partly = CaptureModesPolicy.savedCardStatus(media)
        XCTAssertEqual(partly.text, "Partly in Photos")
        media.photosIdentifiers = ["a.jpg": "x", "b.jpg": "y"]
        let all = CaptureModesPolicy.savedCardStatus(media)
        XCTAssertEqual(all.text, "In Photos")
        for status in [notApplied, none, partly, all] {
            XCTAssertFalse(status.symbol.isEmpty)
            XCTAssertFalse(status.text.localizedCaseInsensitiveContains("originals"))
            XCTAssertFalse(status.text.contains("Roll"))
        }
    }
}
