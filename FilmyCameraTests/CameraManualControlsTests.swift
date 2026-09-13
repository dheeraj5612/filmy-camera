import AVFoundation
import SwiftUI
import XCTest
@testable import FilmyCamera

final class CameraManualControlsTests: XCTestCase {
    func testExposureRequestClampsBothSensorValuesAndUsesLiveFallbacks() {
        let bounded = CameraManualControls.sanitizedExposureRequest(
            iso: 10_000,
            durationSeconds: 2,
            currentISO: 320,
            currentDurationSeconds: 1.0 / 120.0,
            isoRange: 50...1_600,
            durationRange: (1.0 / 8_000.0)...0.5
        )
        XCTAssertEqual(bounded.iso, 1_600)
        XCTAssertEqual(bounded.durationSeconds, 0.5, accuracy: 0.000_001)

        let liveFallback = CameraManualControls.sanitizedExposureRequest(
            iso: .nan,
            durationSeconds: .infinity,
            currentISO: 320,
            currentDurationSeconds: 1.0 / 120.0,
            isoRange: 50...1_600,
            durationRange: (1.0 / 8_000.0)...0.5
        )
        XCTAssertEqual(liveFallback.iso, 320)
        XCTAssertEqual(liveFallback.durationSeconds, 1.0 / 120.0, accuracy: 0.000_001)

        let fullyInvalid = CameraManualControls.sanitizedExposureRequest(
            iso: .nan,
            durationSeconds: .nan,
            currentISO: .infinity,
            currentDurationSeconds: -.infinity,
            isoRange: 50...1_600,
            durationRange: (1.0 / 8_000.0)...0.5
        )
        XCTAssertEqual(fullyInvalid.iso, 50)
        XCTAssertEqual(fullyInvalid.durationSeconds, 1.0 / 8_000.0, accuracy: 0.000_000_1)
    }

    func testWhiteBalanceAndFocusInputsNeverEscapeAdvertisedRanges() {
        let whiteBalance = CameraManualControls.sanitizedWhiteBalanceRequest(
            kelvin: 40_000,
            tint: -900,
            currentKelvin: 5_600,
            currentTint: 8
        )
        XCTAssertEqual(whiteBalance.kelvin, 10_000)
        XCTAssertEqual(whiteBalance.tint, -150)

        let invalidWhiteBalance = CameraManualControls.sanitizedWhiteBalanceRequest(
            kelvin: .nan,
            tint: .infinity,
            currentKelvin: .nan,
            currentTint: -.infinity
        )
        XCTAssertEqual(invalidWhiteBalance.kelvin, 2_500)
        XCTAssertEqual(invalidWhiteBalance.tint, -150)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(-4, current: 0.7), 0)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(4, current: 0.7), 1)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(.nan, current: 0.7), 0.7)
        XCTAssertEqual(CameraManualControls.sanitizedLensPosition(.nan, current: .nan), 0)
    }

    func testUnsupportedHardwareCannotPublishAnEnabledManualMode() {
        XCTAssertEqual(
            CameraManualControls.resolvedMode(requested: .manual, supported: false),
            .auto
        )
        XCTAssertEqual(
            CameraManualControls.resolvedMode(requested: .manual, supported: true),
            .manual
        )
        XCTAssertEqual(
            CameraManualControls.resolvedMode(requested: .auto, supported: true),
            .auto
        )
        XCTAssertEqual(CameraManualControls.unavailable.exposureMode, .auto)
        XCTAssertFalse(CameraManualControls.unavailable.manualExposureSupported)
        XCTAssertFalse(CameraManualControls.unavailable.isApplying)
        XCTAssertFalse(CameraManualControls.unavailable.flashRequiresAutoExposure)
    }

    func testWhiteBalanceGainsAreFiniteAndWithinDeviceBounds() {
        let gains = CameraService.clampedWhiteBalanceGains(
            AVCaptureDevice.WhiteBalanceGains(
                redGain: .nan,
                greenGain: 0.2,
                blueGain: 99
            ),
            maximumGain: 8
        )
        XCTAssertEqual(gains.redGain, 1)
        XCTAssertEqual(gains.greenGain, 1)
        XCTAssertEqual(gains.blueGain, 8)

        let invalidMaximum = CameraService.clampedWhiteBalanceGains(
            AVCaptureDevice.WhiteBalanceGains(redGain: 2, greenGain: 3, blueGain: 4),
            maximumGain: .nan
        )
        XCTAssertEqual(invalidMaximum.redGain, 1)
        XCTAssertEqual(invalidMaximum.greenGain, 1)
        XCTAssertEqual(invalidMaximum.blueGain, 1)
    }

    func testTransientCameraGainReadbackNeverReachesExceptionThrowingConversion() {
        for invalid: Float in [0, 0.99, -1, 8.01, .nan, .infinity, -.infinity] {
            for channel in 0..<3 {
                var channels: [Float] = [2, 3, 4]
                channels[channel] = invalid
                var didConvert = false
                let result = CameraService.validatedWhiteBalanceTemperatureAndTint(
                    for: .init(redGain: channels[0], greenGain: channels[1], blueGain: channels[2]),
                    maximumGain: 8
                ) { _ in
                    didConvert = true
                    return .init(temperature: 5600, tint: 0)
                }
                XCTAssertNil(result, "Invalid sensor readback must remain unavailable")
                XCTAssertFalse(didConvert, "AVFoundation must never receive the invalid gain")
            }
        }
        for maximum: Float in [0, 0.99, -1, .nan, .infinity, -.infinity] {
            let result = CameraService.validatedWhiteBalanceTemperatureAndTint(
                for: .init(redGain: 1, greenGain: 1, blueGain: 1), maximumGain: maximum
            ) { _ in
                XCTFail("An uninitialized gain bound must never reach AVFoundation")
                return .init(temperature: 5600, tint: 0)
            }
            XCTAssertNil(result)
        }
    }

    func testValidCameraWhiteBalanceReadbackPreservesSensorValuesWithoutClamping() throws {
        var conversionCount = 0
        let result = try XCTUnwrap(CameraService.validatedWhiteBalanceTemperatureAndTint(
            for: .init(redGain: 1, greenGain: 2.75, blueGain: 8), maximumGain: 8
        ) { gains in
            conversionCount += 1
            XCTAssertEqual(gains.redGain, 1)
            XCTAssertEqual(gains.greenGain, 2.75)
            XCTAssertEqual(gains.blueGain, 8)
            // Auto metering can lie outside the user's manual slider range.
            return .init(temperature: 12000, tint: 175)
        })
        XCTAssertEqual(conversionCount, 1)
        XCTAssertEqual(result.temperature, 12000)
        XCTAssertEqual(result.tint, 175)
    }

    func testInvalidConvertedWhiteBalanceReadbackRemainsUnavailable() {
        for values in [AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: .nan, tint: 0),
                       .init(temperature: .infinity, tint: 0), .init(temperature: 0, tint: 0),
                       .init(temperature: 5600, tint: .nan), .init(temperature: 5600, tint: .infinity)] {
            XCTAssertNil(CameraService.validatedWhiteBalanceTemperatureAndTint(
                for: .init(redGain: 2, greenGain: 3, blueGain: 4), maximumGain: 8
            ) { _ in values })
        }
    }

    func testManualFrameDurationKeepsExactThirtyFPSAndAccommodatesLongShutter() {
        let fastShutter = CameraService.manualFrameDuration(
            for: CMTime(value: 1, timescale: 8_000)
        )
        XCTAssertEqual(CMTimeCompare(fastShutter, CMTime(value: 1, timescale: 30)), 0)

        let longShutter = CameraService.manualFrameDuration(
            for: CMTime(value: 1, timescale: 4)
        )
        XCTAssertEqual(CMTimeCompare(longShutter, CMTime(value: 1, timescale: 4)), 0)

        let invalid = CameraService.manualFrameDuration(for: .invalid)
        XCTAssertEqual(CMTimeCompare(invalid, CMTime(value: 1, timescale: 30)), 0)
    }

    func testExposureDurationConversionCannotRoundOutsideHardwareRationals() throws {
        let minimum = CMTime(value: 1, timescale: 2_000_000_001)
        let maximum = CMTime(value: 1, timescale: 2)
        let clampedMinimum = try XCTUnwrap(
            CameraService.clampedManualExposureDuration(
                requestedSeconds: CMTimeGetSeconds(minimum),
                fallback: CMTime(value: 1, timescale: 60),
                minimum: minimum,
                maximum: maximum
            )
        )
        XCTAssertGreaterThanOrEqual(CMTimeCompare(clampedMinimum, minimum), 0)

        let clampedMaximum = try XCTUnwrap(
            CameraService.clampedManualExposureDuration(
                requestedSeconds: 5,
                fallback: CMTime(value: 1, timescale: 60),
                minimum: minimum,
                maximum: maximum
            )
        )
        XCTAssertEqual(CMTimeCompare(clampedMaximum, maximum), 0)

        XCTAssertNil(
            CameraService.clampedManualExposureDuration(
                requestedSeconds: 0.01,
                fallback: .invalid,
                minimum: maximum,
                maximum: minimum
            )
        )
    }

    func testManualExposureUsesCapturePriorityThatHonorsSensorSettings() {
        XCTAssertEqual(
            CameraService.photoQualityPrioritization(manualExposureEnabled: true),
            .speed
        )
        XCTAssertEqual(
            CameraService.photoQualityPrioritization(manualExposureEnabled: false),
            .quality
        )
    }

    func testLensOptionAdvertisesOnlyRealSupportedControls() {
        let exposureOnly = CameraManualControls.PhysicalLensOption(
            id: "wide",
            title: "1×",
            detail: "Wide",
            supportsManualExposure: true,
            supportsManualWhiteBalance: false,
            supportsManualFocus: false,
            isActive: false
        )
        let unsupported = CameraManualControls.PhysicalLensOption(
            id: "virtual",
            title: "Smart",
            detail: "Smart camera",
            supportsManualExposure: false,
            supportsManualWhiteBalance: false,
            supportsManualFocus: false,
            isActive: true
        )
        XCTAssertTrue(exposureOnly.supportsAnyManualControl)
        XCTAssertFalse(unsupported.supportsAnyManualControl)
    }
}


final class CaptureWorkflowPolicyTests: XCTestCase {
    @MainActor
    func testTopBarKeepsFiveControlsAndAdjustmentBadgeInsideNarrowWidths() async throws {
        for width: CGFloat in [296, 351, 406, 700] {
            let measurements = TopBarMeasurements()
            let content = CameraTopBarLayout {
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Button {} label: {
                            Image(systemName: "camera")
                                .frame(width: 44, height: 44)
                        }
                        .recordTopBarFrame("control-\(index)")
                    }
                    Spacer(minLength: 0)
                }
            } indicators: {
                Button {} label: {
                    HStack(spacing: 5) {
                        Text("+3.0 EV")
                        Label("AE/AF", systemImage: "lock.fill").labelStyle(.titleAndIcon)
                        Text("MANUAL")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                }
                .recordTopBarFrame("indicators")
            }
            .foregroundStyle(.white)
            .background(.black)
            .coordinateSpace(name: "camera-topbar-test")
            .onPreferenceChange(TopBarFramePreference.self) { frames in
                MainActor.assumeIsolated { measurements.frames = frames }
            }

            let host = UIHostingController(rootView: content)
            // This fixture is a camera chrome region, not a full-screen app.
            // Device safe-area insets can otherwise push its content outside
            // the 44/92pt bitmap while local layout measurements still pass.
            host.safeAreaRegions = []
            let fitted = host.sizeThatFits(in: CGSize(width: width, height: 300))
            let window = UIWindow(frame: CGRect(origin: .zero, size: fitted))
            window.rootViewController = host
            host.view.frame = window.bounds
            host.view.backgroundColor = .black
            window.isHidden = false
            host.view.layoutIfNeeded()
            for _ in 0..<20 where measurements.frames.count < 6 {
                try await Task.sleep(for: .milliseconds(10))
                host.view.layoutIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            defer { window.isHidden = true }

            XCTAssertEqual(measurements.frames.count, 6)
            let visibleBounds = CGRect(origin: .zero, size: CGSize(width: width, height: fitted.height))
                .insetBy(dx: -0.5, dy: -0.5)
            for (name, frame) in measurements.frames {
                XCTAssertTrue(visibleBounds.contains(frame), "\(name) is clipped at width \(width): \(frame)")
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
            }
            let badge = try XCTUnwrap(measurements.frames["indicators"])
            for index in 0..<5 {
                let control = try XCTUnwrap(measurements.frames["control-\(index)"])
                XCTAssertFalse(badge.intersects(control), "The badge must not cover a control")
            }
            let expectedHeight: CGFloat = width >= 700 ? 44 : 92
            XCTAssertEqual(fitted.height, expectedHeight, accuracy: 0.5)
            var drewHierarchy = false
            let snapshot = UIGraphicsImageRenderer(size: fitted).image { _ in
                drewHierarchy = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(drewHierarchy, "The attachment must contain the settled UIKit hierarchy")
            let bitmap = try XCTUnwrap(snapshot.cgImage)
            for (name, frame) in measurements.frames {
                let pixelRect = frame.applying(CGAffineTransform(scaleX: snapshot.scale, y: snapshot.scale)).integral
                let region = try XCTUnwrap(bitmap.cropping(to: pixelRect))
                var rgba = [UInt8](repeating: 0, count: region.width * region.height * 4)
                try rgba.withUnsafeMutableBytes { bytes in
                    let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: region.width, height: region.height,
                        bitsPerComponent: 8, bytesPerRow: region.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(region, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
                }
                let visibleChannels = rgba.enumerated().filter { $0.offset % 4 != 3 && $0.element > 128 }.count
                XCTAssertGreaterThan(visibleChannels, 6, "\(name) must actually render in the attachment at width \(width)")
            }
            let attachment = XCTAttachment(image: snapshot)
            attachment.name = "camera-topbar-\(Int(width))pt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testPreviewCancellationWaitsForTheOldRenderToDrain() throws {
        var state = PreviewRenderState()
        let stale = try XCTUnwrap(state.begin())
        state.invalidate()
        XCTAssertNil(state.begin(), "Canceling a GPU job does not stop its synchronous work")
        XCTAssertFalse(state.finish(stale), "The old crop cannot publish after invalidation")
        let current = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.finish(current))
    }

    func testStalePreviewCompletionCannotReleaseANewerRender() throws {
        var state = PreviewRenderState()
        let first = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.finish(first))
        let current = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.finish(first))
        XCTAssertNil(state.begin(), "A duplicate completion must not admit overlapping work")
        XCTAssertTrue(state.finish(current))
    }

    func testRepeatedPreviewInvalidationStillDrainsExactlyOneOperation() throws {
        var state = PreviewRenderState()
        let canceledBeforeStarting = try XCTUnwrap(state.begin())
        state.invalidate()
        state.invalidate()
        XCTAssertNil(state.begin())
        XCTAssertFalse(state.finish(canceledBeforeStarting))
        XCTAssertFalse(state.finish(canceledBeforeStarting))
        let current = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.finish(current))
    }

    func testCountdownRejectsDuplicateAndUnsupportedStarts() throws {
        var state = CaptureTimerState()
        for seconds in [-1, 0, 1, 4, 30] { XCTAssertNil(state.begin(seconds: seconds)) }
        _ = try XCTUnwrap(state.begin(seconds: 3))
        XCTAssertNil(state.begin(seconds: 5)); XCTAssertEqual(state.remaining, 3)
    }
    func testTimerCannotFireBeforeDeadlineOrMoreThanOnce() throws {
        var state = CaptureTimerState()
        let id = try XCTUnwrap(state.begin(seconds: 3))
        XCTAssertFalse(state.consume(id))
        XCTAssertFalse(state.tick(id)); XCTAssertFalse(state.tick(id)); XCTAssertTrue(state.tick(id))
        XCTAssertTrue(state.consume(id)); XCTAssertFalse(state.consume(id)); XCTAssertFalse(state.isActive)
    }
    func testCancelledCountdownCannotConsumeANewerCountdown() throws {
        var state = CaptureTimerState()
        let stale = try XCTUnwrap(state.begin(seconds: 3)); state.cancel()
        let current = try XCTUnwrap(state.begin(seconds: 5))
        XCTAssertFalse(state.tick(stale)); XCTAssertFalse(state.consume(stale))
        XCTAssertEqual(state.operationID, current); XCTAssertEqual(state.remaining, 5)
    }
    func testAllSupportedDurationsCountDownExactly() throws {
        for duration in [3, 5, 10] {
            var state = CaptureTimerState()
            let id = try XCTUnwrap(state.begin(seconds: duration))
            for tick in 1...duration { XCTAssertEqual(state.tick(id), tick == duration) }
            XCTAssertTrue(state.consume(id)); XCTAssertFalse(state.tick(id))
        }
    }
    func testPreviewHistogramCountsBlackWhiteAndSingleChannelClipping() throws {
        let rgba: [UInt8] = [0,0,0,255, 255,255,255,255, 255,0,0,255, 128,128,128,255]
        let result = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: rgba, width: 4, height: 1, zebras: false, peaking: false))
        XCTAssertEqual(result.histogram.reduce(0,+), 4)
        XCTAssertEqual(result.histogram[0], 1); XCTAssertEqual(result.histogram[63], 1)
        XCTAssertEqual(result.clippedPixels, 2)
        XCTAssertTrue(result.overlayRGBA.allSatisfy { $0 == 0 })
    }
    func testPreviewAnalysisRejectsInvalidAndUnboundedInputs() {
        for size in [(-1,1),(0,1),(1,0),(193,1),(1,193),(Int.max,Int.max)] {
            XCTAssertNil(PreviewAnalysisMath.analyze(rgba: [], width: size.0, height: size.1, zebras: true, peaking: true))
        }
        XCTAssertNil(PreviewAnalysisMath.analyze(rgba: [1], width: 1, height: 1, zebras: true, peaking: true))
    }
    func testFlatFieldHasNoFocusPeakingAndOpaqueChannelsStayPremultiplied() throws {
        var gray = [UInt8](repeating: 128, count: 8 * 8 * 4)
        for offset in stride(from: 3, to: gray.count, by: 4) { gray[offset] = 255 }
        let result = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: gray, width: 8, height: 8, zebras: false, peaking: true))
        XCTAssertTrue(result.overlayRGBA.allSatisfy { $0 == 0 })
        let white = [UInt8](repeating: 255, count: 8 * 8 * 4)
        let zebras = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: white, width: 8, height: 8, zebras: true, peaking: false))
        XCTAssertEqual(zebras.clippedPixels, 64)
        XCTAssertTrue(zebras.overlayRGBA.contains { $0 > 0 })
        for p in stride(from: 0, to: zebras.overlayRGBA.count, by: 4) {
            for c in 0...2 { XCTAssertLessThanOrEqual(zebras.overlayRGBA[p+c], zebras.overlayRGBA[p+3]) }
        }
    }
    func testPeakingFindsContrastEdgesButNotTheBorder() throws {
        var rgba = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<8 {
                let offset = (y*8+x)*4
                for c in 0...2 { rgba[offset+c] = x < 4 ? 60 : 190 }
            }
        }
        let result = try XCTUnwrap(PreviewAnalysisMath.analyze(rgba: rgba, width: 8, height: 8, zebras: false, peaking: true))
        XCTAssertTrue(result.overlayRGBA.contains { $0 > 0 })
        for x in 0..<8 { XCTAssertEqual(result.overlayRGBA[x*4+3], 0) }
    }
    func testLevelHandlesEveryOrientationAndRejectsFlatOrNonfiniteGravity() throws {
        for vector in [(0.0,-1.0),(1.0,0.0),(0.0,1.0),(-1.0,0.0)] {
            XCTAssertEqual(try XCTUnwrap(PreviewAnalysisMath.horizonDegrees(x: vector.0, y: vector.1)), 0, accuracy: 0.0001)
        }
        XCTAssertEqual(try XCTUnwrap(PreviewAnalysisMath.horizonDegrees(x: sin(.pi/18), y: -cos(.pi/18))), 10, accuracy: 0.0001)
        XCTAssertNil(PreviewAnalysisMath.horizonDegrees(x: 0, y: 0))
        XCTAssertNil(PreviewAnalysisMath.horizonDegrees(x: .nan, y: -1))
        XCTAssertNil(PreviewAnalysisMath.horizonDegrees(x: .infinity, y: 0))
    }
    func testExactAspectFramesFitPortraitLandscapeAndTinyWindows() {
        for size in [CGSize(width: 390,height: 500), CGSize(width: 700,height: 250), CGSize(width: 800,height: 1100)] {
            for aspect in CaptureAspect.allCases where aspect != .viewfinder {
                for landscape in [true, false] {
                    let result = ViewfinderLayout.size(available: size, isLandscape: landscape, aspect: aspect)
                    XCTAssertLessThanOrEqual(result.width, size.width + 0.001)
                    XCTAssertLessThanOrEqual(result.height, size.height + 0.001)
                    XCTAssertEqual(result.width/result.height, CGFloat(aspect.ratio(isLandscape: landscape)!), accuracy: 0.0001)
                }
            }
        }
    }
    func testInvalidViewfinderSizeCannotPublishNaN() {
        XCTAssertEqual(ViewfinderLayout.size(available: CGSize(width: CGFloat.nan,height: 2), isLandscape: false), .zero)
        XCTAssertEqual(ViewfinderLayout.size(available: .zero, isLandscape: true, aspect: .square), .zero)
    }
}

@MainActor
private final class TopBarMeasurements {
    var frames: [String: CGRect] = [:]
}

private struct TopBarFramePreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func recordTopBarFrame(_ name: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: TopBarFramePreference.self,
                                       value: [name: proxy.frame(in: .named("camera-topbar-test"))])
            }
        }
    }
}
