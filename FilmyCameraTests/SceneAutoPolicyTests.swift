import Foundation
import XCTest
#if canImport(SceneAutoCore)
@testable import SceneAutoCore
#else
@testable import FilmyCamera
#endif

final class SceneAutoPolicyTests: XCTestCase {
    private func observation(_ time: Double, motion: Double = 0) -> SceneAutoObservation {
        SceneAutoObservation(timestamp: time, median: 0.45, center: 0.45, highlights: 0.01, shadows: 0.02,
                             motion: motion, neutralFraction: 0.4, redOverGreen: 1, blueOverGreen: 1,
                             face: nil, faceConfidence: 0)
    }

    private func sensor(offset: Double = 0) -> SceneAutoSensor {
        SceneAutoSensor(iso: 100, duration: 1.0 / 60, minimumISO: 50, maximumISO: 12_800,
                        minimumDuration: 1.0 / 12_000, maximumDuration: 1.0 / 3,
                        aperture: 1.8, targetOffset: offset, zoom: 1, isAdjustingExposure: false,
                        isAdjustingWhiteBalance: false, isAdjustingFocus: false, supportsCustomExposure: true)
    }

    @discardableResult
    private func advance(_ policy: inout SceneAutoPolicy, to time: Double, observation input: SceneAutoObservation? = nil,
                         sensor hardware: SceneAutoSensor? = nil, lastTap: Double = -.infinity) -> SceneAutoDecision {
        var sample = input ?? observation(time)
        sample.timestamp = time
        return policy.update(observation: sample, sensor: hardware ?? sensor(), now: time, lastUserFocus: lastTap)!
    }

    func testDefaultIsOffAndDoesNotAcceptFrames() {
        XCTAssertEqual(SceneAutoState().phase, .off)
        XCTAssertFalse(SceneAutoState().isEnabled)
        XCTAssertFalse(SceneAutoState().acceptsFrames)
        XCTAssertEqual(SceneAutoState().development, SceneAutoDevelopment())
    }

    func testHoldAndVisibilityAreExplicitNoAnalysisStates() {
        for phase in [SceneAutoState.Phase.held, .paused] {
            let state = SceneAutoState(phase: phase)
            XCTAssertTrue(state.isEnabled)
            XCTAssertFalse(state.acceptsFrames)
        }
        XCTAssertTrue(SceneAutoState(phase: .metering).acceptsFrames)
        XCTAssertTrue(SceneAutoState(phase: .limited).acceptsFrames)
    }

    func testWarmupMakesNoSensorOrDevelopmentChanges() {
        var policy = SceneAutoPolicy()
        for time in [0.0, 0.4, 0.8] {
            let result = advance(&policy, to: time, sensor: sensor(offset: 2))
            XCTAssertTrue(result.isMetering)
            XCTAssertNil(result.exposure)
            XCTAssertNil(result.focus)
            XCTAssertEqual(result.whiteBalance, .unchanged)
            XCTAssertEqual(result.development, SceneAutoDevelopment())
        }
    }

    func testRejectsStaleFutureDuplicateAndOutOfOrderFrames() {
        var policy = SceneAutoPolicy()
        XCTAssertNil(policy.update(observation: observation(1), sensor: sensor(), now: 3))
        XCTAssertNil(policy.update(observation: observation(4), sensor: sensor(), now: 3))
        XCTAssertNotNil(policy.update(observation: observation(4), sensor: sensor(), now: 4))
        XCTAssertNil(policy.update(observation: observation(4), sensor: sensor(), now: 4.1))
        XCTAssertNil(policy.update(observation: observation(3.9), sensor: sensor(), now: 4.2))
        XCTAssertNil(policy.update(observation: observation(5), sensor: sensor(), now: .nan))
    }

    func testRejectsInvalidStatisticsWithoutPoisoningState() {
        var policy = SceneAutoPolicy()
        var invalid = observation(0)
        invalid.median = .nan
        XCTAssertNil(policy.update(observation: invalid, sensor: sensor(), now: 0))
        invalid = observation(0); invalid.motion = 1.1
        XCTAssertNil(policy.update(observation: invalid, sensor: sensor(), now: 0))
        invalid = observation(0); invalid.face = SceneAutoPoint(x: -0.1, y: 0.5)
        XCTAssertNil(policy.update(observation: invalid, sensor: sensor(), now: 0))
        invalid = observation(0); invalid.redOverGreen = 0
        XCTAssertNil(policy.update(observation: invalid, sensor: sensor(), now: 0))
        XCTAssertTrue(advance(&policy, to: 0).isMetering)
    }

    func testRejectsInvalidHardwareBoundsAndValues() {
        var policy = SceneAutoPolicy()
        var hardware = sensor(); hardware.iso = .infinity
        XCTAssertNil(policy.update(observation: observation(0), sensor: hardware, now: 0))
        hardware = sensor(); hardware.minimumISO = hardware.maximumISO + 1
        XCTAssertNil(policy.update(observation: observation(0), sensor: hardware, now: 0))
        hardware = sensor(); hardware.duration = 0
        XCTAssertNil(policy.update(observation: observation(0), sensor: hardware, now: 0))
        hardware = sensor(); hardware.targetOffset = .nan
        XCTAssertNil(policy.update(observation: observation(0), sensor: hardware, now: 0))
    }

    func testSteadySceneWithMeterNoiseDoesNotHunt() {
        var policy = SceneAutoPolicy()
        var exposures = 0, focusChanges = 0, whiteBalanceLocks = 0
        for tick in 0..<151 {
            let hardware = sensor(offset: tick.isMultiple(of: 2) ? 0.07 : -0.07)
            let decision = advance(&policy, to: Double(tick) * 0.4, sensor: hardware)
            if decision.exposure != nil { exposures += 1 }
            if decision.focus != nil { focusChanges += 1 }
            if decision.whiteBalance == .lock { whiteBalanceLocks += 1 }
            XCTAssertEqual(decision.scene, .balanced)
        }
        XCTAssertEqual(exposures, 0)
        XCTAssertEqual(focusChanges, 1)
        XCTAssertEqual(whiteBalanceLocks, 1)
    }

    func testSingleBrightFrameDoesNotCauseExposurePumping() {
        var policy = SceneAutoPolicy()
        for tick in 0..<80 {
            let decision = advance(&policy, to: Double(tick) * 0.4, sensor: sensor(offset: tick == 30 ? 1 : 0))
            XCTAssertNil(decision.exposure, "Transient command at tick \(tick)")
        }
    }

    func testFeedbackConvergesWithoutOvershootOrUnboundedEVSteps() {
        for startingOffset in [-2.8, 2.8] {
            var policy = SceneAutoPolicy()
            var hardware = sensor(offset: startingOffset)
            var corrections = 0
            var targetBias = 0.0
            for tick in 0..<180 {
                let decision = advance(&policy, to: Double(tick) * 0.4, sensor: hardware)
                targetBias = decision.fallbackBias
                if let requested = decision.exposure {
                    let delta = log2((requested.iso * requested.duration) / (hardware.iso * hardware.duration))
                    XCTAssertLessThanOrEqual(abs(delta), 0.400001)
                    hardware.targetOffset += delta
                    hardware.iso = requested.iso; hardware.duration = requested.duration
                    corrections += 1
                }
                XCTAssertGreaterThanOrEqual(hardware.targetOffset * startingOffset, -0.2)
            }
            XCTAssertLessThan(abs(hardware.targetOffset - targetBias), 0.17)
            XCTAssertGreaterThan(corrections, 0)
            XCTAssertLessThan(corrections, 45)
        }
    }

    func testNativeExposureAdjustmentIsNotFought() {
        var policy = SceneAutoPolicy()
        var hardware = sensor(offset: 2)
        hardware.isAdjustingExposure = true
        for tick in 0..<30 {
            XCTAssertNil(advance(&policy, to: Double(tick) * 0.4, sensor: hardware).exposure)
        }
    }

    func testLimitedHardwareReceivesNoCustomExposureRequest() {
        var policy = SceneAutoPolicy()
        var hardware = sensor(offset: 2)
        hardware.supportsCustomExposure = false
        for tick in 0..<30 {
            XCTAssertNil(advance(&policy, to: Double(tick) * 0.4, sensor: hardware).exposure)
        }
    }

    func testSceneLabelsRequireSustainedEvidence() {
        var policy = SceneAutoPolicy()
        for tick in 0..<40 {
            var sample = observation(Double(tick) * 0.4)
            if tick.isMultiple(of: 2) { sample.face = .center; sample.faceConfidence = 0.99 }
            XCTAssertEqual(advance(&policy, to: sample.timestamp, observation: sample).scene, .balanced)
        }
    }

    func testPortraitAndMotionHaveAppropriatePriority() {
        var policy = SceneAutoPolicy()
        var sample = observation(0)
        sample.face = .center; sample.faceConfidence = 0.99
        for tick in 0..<15 { advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        XCTAssertEqual(policy.scene, .portrait)
        sample.motion = 0.20
        for tick in 15..<40 { advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        XCTAssertEqual(policy.scene, .action)
    }

    func testHighlightEntryExitHysteresis() {
        var policy = SceneAutoPolicy()
        var sample = observation(0); sample.highlights = 0.09; sample.shadows = 0.2
        for tick in 0..<20 { advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        XCTAssertEqual(policy.scene, .highContrast)
        sample.highlights = 0.05
        for tick in 20..<40 { advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        XCTAssertEqual(policy.scene, .highContrast)
        sample.highlights = 0.01
        for tick in 40..<60 { advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        XCTAssertEqual(policy.scene, .balanced)
    }

    func testBacklightKeepsRestrainedExposureBias() {
        var policy = SceneAutoPolicy()
        var sample = observation(0); sample.highlights = 0.1; sample.shadows = 0.3; sample.center = 0.2
        var decision = advance(&policy, to: 0, observation: sample)
        for tick in 1..<20 { decision = advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        XCTAssertEqual(decision.scene, .backlit)
        XCTAssertEqual(decision.fallbackBias, -0.15)
        XCTAssertLessThanOrEqual(decision.development.shadows, 0, "Negative Fuji shadow tone lifts shadow detail")
    }

    func testLowLightHysteresisUsesMeteredBrightnessNotDarkImageContent() {
        var policy = SceneAutoPolicy()
        var hardware = sensor(); hardware.iso = 1600
        for tick in 0..<20 { advance(&policy, to: Double(tick) * 0.4, sensor: hardware) }
        XCTAssertEqual(policy.scene, .lowLight)
        var dark = observation(0); dark.median = 0.01; dark.center = 0.01; dark.shadows = 0.9
        var brightPolicy = SceneAutoPolicy()
        for tick in 0..<20 { advance(&brightPolicy, to: Double(tick) * 0.4, observation: dark) }
        XCTAssertEqual(brightPolicy.scene, .balanced)
    }

    func testExposureAllocationPreservesBrightnessWhenChangingMotionPriority() {
        let hardware = sensor()
        for scene in SceneAutoScene.allCases {
            let allocation = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: scene, motion: 0, correctionEV: 0)
            XCTAssertEqual(allocation.iso * allocation.duration, hardware.iso * hardware.duration, accuracy: 0.000001)
        }
    }

    func testMotionPortraitAndZoomShutterFloors() {
        var hardware = sensor(); hardware.iso = 800
        let motion = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: .action, motion: 0.2, correctionEV: 0)
        let portrait = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: .portrait, motion: 0, correctionEV: 0)
        XCTAssertLessThanOrEqual(motion.duration, 1.0 / 250)
        XCTAssertLessThanOrEqual(portrait.duration, 1.0 / 125)
        hardware.zoom = 6
        let zoomed = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: .balanced, motion: 0, correctionEV: 0)
        XCTAssertLessThanOrEqual(zoomed.duration, 1.0 / 180)
    }

    func testSteadyLowLightAllowsOneThirtiethNotLongHandheldExposure() {
        var hardware = sensor(); hardware.iso = 1600
        let still = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: .lowLight, motion: 0, correctionEV: 0)
        let moving = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: .lowLight, motion: 0.05, correctionEV: 0)
        XCTAssertEqual(still.duration, 1.0 / 30, accuracy: 0.000001)
        XCTAssertLessThanOrEqual(moving.duration, 1.0 / 60)
        XCTAssertLessThan(still.iso, moving.iso)
    }

    func testExposureRequestsRespectHardwareBoundsAcrossDeterministicGrid() {
        for iso in [50.0, 100, 800, 3200, 12_800] {
            for duration in [1.0 / 12_000, 1.0 / 60, 1.0 / 3] {
                for correction in [-8.0, -1, 0, 1, 8] {
                    for scene in SceneAutoScene.allCases {
                        var hardware = sensor(); hardware.iso = iso; hardware.duration = duration
                        let value = SceneAutoPolicy.allocateExposure(sensor: hardware, scene: scene, motion: 0.1, correctionEV: correction)
                        XCTAssertTrue(value.iso.isFinite && value.duration.isFinite)
                        XCTAssertTrue((hardware.minimumISO...hardware.maximumISO).contains(value.iso))
                        XCTAssertTrue((hardware.minimumDuration...hardware.maximumDuration).contains(value.duration))
                    }
                }
            }
        }
    }

    func testMeteredBrightnessCompensatesForExposureOffset() {
        let neutral = sensor()
        var overexposed = neutral; overexposed.iso *= 4; overexposed.targetOffset = 2
        XCTAssertEqual(neutral.meteredEV100, overexposed.meteredEV100, accuracy: 0.000001)
    }

    func testManualFocusTapGetsSixSecondGrace() {
        var policy = SceneAutoPolicy()
        for tick in 0..<15 {
            XCTAssertNil(advance(&policy, to: Double(tick) * 0.4, lastTap: 0).focus)
        }
    }

    func testTinyFaceJitterDoesNotRefocus() {
        var policy = SceneAutoPolicy()
        var refocuses = 0
        for tick in 0..<100 {
            var sample = observation(Double(tick) * 0.4)
            sample.face = SceneAutoPoint(x: tick.isMultiple(of: 2) ? 0.49 : 0.51, y: 0.5)
            sample.faceConfidence = 0.99
            if advance(&policy, to: sample.timestamp, observation: sample).focus != nil { refocuses += 1 }
        }
        XCTAssertEqual(refocuses, 1)
    }

    func testSceneReframeRefocusesOnlyAfterMotionSettles() {
        var policy = SceneAutoPolicy()
        var refocuses = 0
        for tick in 0..<65 {
            let motion = (20..<26).contains(tick) ? 0.2 : 0.0
            let result = advance(&policy, to: Double(tick) * 0.4, observation: observation(0, motion: motion))
            if result.focus != nil {
                refocuses += 1
                XCTAssertFalse((20..<26).contains(tick))
            }
        }
        XCTAssertEqual(refocuses, 2)
    }

    func testWhiteBalanceIgnoresSaturatedSceneAndTransientColorChange() {
        var policy = SceneAutoPolicy()
        for tick in 0..<70 {
            var sample = observation(Double(tick) * 0.4)
            if tick > 10 { sample.redOverGreen = 1.5; sample.neutralFraction = 0.05 }
            XCTAssertNotEqual(advance(&policy, to: sample.timestamp, observation: sample).whiteBalance, .meter)
        }
        var transientPolicy = SceneAutoPolicy()
        for tick in 0..<70 {
            var sample = observation(Double(tick) * 0.4)
            if tick == 40 { sample.redOverGreen = 1.5 }
            XCTAssertNotEqual(advance(&transientPolicy, to: sample.timestamp, observation: sample).whiteBalance, .meter)
        }
    }

    func testWhiteBalanceReacquiresOnlyAfterSustainedNeutralEvidenceAndCooldown() {
        var policy = SceneAutoPolicy()
        var meteringTimes: [Double] = [], locks = 0
        for tick in 0..<100 {
            let time = Double(tick) * 0.4
            var sample = observation(time)
            if tick > 20 { sample.redOverGreen = 1.4 }
            let result = advance(&policy, to: time, observation: sample)
            if result.whiteBalance == .meter { meteringTimes.append(time) }
            if result.whiteBalance == .lock { locks += 1 }
        }
        XCTAssertEqual(meteringTimes.count, 1)
        XCTAssertGreaterThanOrEqual(meteringTimes.first ?? 0, 10)
        XCTAssertEqual(locks, 2)
    }

    func testResumeRelocksWhiteBalanceAfterInterruptedReacquisition() {
        var policy = SceneAutoPolicy()
        for tick in 0..<24 { advance(&policy, to: Double(tick) * 0.4) }
        var changed = observation(0)
        changed.redOverGreen = 1.4
        var requestedMetering = false
        for tick in 24..<40 {
            let result = advance(&policy, to: Double(tick) * 0.4, observation: changed)
            if result.whiteBalance == .meter { requestedMetering = true; break }
        }
        XCTAssertTrue(requestedMetering)
        policy.resume()
        var locks = 0
        for tick in 0..<12 {
            let result = advance(&policy, to: 100 + Double(tick) * 0.4)
            if result.whiteBalance == .lock { locks += 1 }
            XCTAssertNotEqual(result.whiteBalance, .meter)
        }
        XCTAssertEqual(locks, 1)
    }

    func testHardwareWhiteBalanceSettlingIsGivenTimeButNotUnboundedTime() {
        var policy = SceneAutoPolicy()
        var hardware = sensor(); hardware.isAdjustingWhiteBalance = true
        var firstLock: Double?
        for tick in 0..<20 {
            let time = Double(tick) * 0.4
            if advance(&policy, to: time, sensor: hardware).whiteBalance == .lock, firstLock == nil { firstLock = time }
        }
        XCTAssertNotNil(firstLock)
        XCTAssertGreaterThan(firstLock ?? 0, 4)
    }

    func testDevelopmentIsSlewLimitedAndNeverExceedsItsBounds() {
        var policy = SceneAutoPolicy()
        var sample = observation(0); sample.highlights = 0.1; sample.shadows = 0.2
        var hardware = sensor(); hardware.iso = 3200; hardware.duration = 1.0 / 8000
        var previous = SceneAutoDevelopment()
        for tick in 0..<120 {
            let result = advance(&policy, to: Double(tick) * 0.4, observation: sample, sensor: hardware)
            let development = result.development
            XCTAssertLessThanOrEqual(abs(development.highlights - previous.highlights), 0.010001)
            XCTAssertLessThanOrEqual(abs(development.noiseReduction - previous.noiseReduction), 0.010001)
            XCTAssertTrue((-0.16...0).contains(development.highlights))
            XCTAssertTrue((-0.12...0).contains(development.shadows))
            XCTAssertTrue((0...0.16).contains(development.noiseReduction))
            XCTAssertTrue((-0.10...0).contains(development.sharpness))
            previous = development
        }
    }

    func testResumePreservesFinishingButRewarmsWithoutCatchUp() {
        var policy = SceneAutoPolicy()
        var sample = observation(0); sample.highlights = 0.1; sample.shadows = 0.2
        for tick in 0..<25 { advance(&policy, to: Double(tick) * 0.4, observation: sample) }
        let before = policy.development
        policy.resume()
        let resumed = advance(&policy, to: 100, sensor: sensor(offset: 3))
        XCTAssertTrue(resumed.isMetering)
        XCTAssertNil(resumed.exposure)
        XCTAssertEqual(resumed.development, before)
    }

    func testLongGapAutomaticallyRewarms() {
        var policy = SceneAutoPolicy()
        for tick in 0..<20 { advance(&policy, to: Double(tick) * 0.4) }
        XCTAssertTrue(advance(&policy, to: 50, sensor: sensor(offset: 3)).isMetering)
    }

    func testApproachRejectsNonfiniteInputs() {
        XCTAssertEqual(SceneAutoPolicy.approach(.nan, 2, by: 0.1), 0)
        XCTAssertEqual(SceneAutoPolicy.approach(1, .infinity, by: 0.1), 1)
        XCTAssertEqual(SceneAutoPolicy.approach(1, 2, by: -.infinity), 1)
        XCTAssertEqual(SceneAutoPolicy.approach(1, 2, by: 0.1), 1.1, accuracy: 0.000001)
    }

    func testStatisticsRejectInvalidSizesAndBuffers() {
        XCTAssertNil(SceneAutoStatistics.measure(rgba: [], width: 0, height: 0, previousLuma: nil))
        XCTAssertNil(SceneAutoStatistics.measure(rgba: [], width: 161, height: 1, previousLuma: nil))
        XCTAssertNil(SceneAutoStatistics.measure(rgba: [0, 0, 0], width: 1, height: 1, previousLuma: nil))
        XCTAssertNil(SceneAutoStatistics.measure(rgba: [], width: Int.max, height: Int.max, previousLuma: nil))
    }

    func testNeutralImageAndSingleChannelClippingStatistics() throws {
        let neutral = try XCTUnwrap(SceneAutoStatistics.measure(rgba: [128, 128, 128, 255], width: 1, height: 1, previousLuma: nil))
        XCTAssertEqual(neutral.neutralFraction, 1)
        XCTAssertEqual(neutral.redOverGreen, 1)
        XCTAssertEqual(neutral.motion, 0)
        let clipped = try XCTUnwrap(SceneAutoStatistics.measure(rgba: [255, 0, 0, 255], width: 1, height: 1, previousLuma: nil))
        XCTAssertEqual(clipped.highlights, 1)
        XCTAssertEqual(clipped.neutralFraction, 0)
    }

    func testGlobalExposureChangeIsNotMistakenForMotion() throws {
        let before = try XCTUnwrap(SceneAutoStatistics.measure(rgba: Array(repeating: [80, 80, 80, 255], count: 16).flatMap { $0 },
                                                               width: 4, height: 4, previousLuma: nil))
        let after = try XCTUnwrap(SceneAutoStatistics.measure(rgba: Array(repeating: [120, 120, 120, 255], count: 16).flatMap { $0 },
                                                              width: 4, height: 4, previousLuma: before.luma))
        XCTAssertEqual(after.motion, 0, accuracy: 0.000001)
    }

    func testSpatialChangesRegisterMotionAndBadHistoryDoesNotPoisonStatistics() throws {
        let pixels: [UInt8] = [20, 20, 20, 255, 240, 240, 240, 255]
        let moved = try XCTUnwrap(SceneAutoStatistics.measure(rgba: pixels, width: 2, height: 1, previousLuma: [240.0 / 255, 20.0 / 255]))
        XCTAssertGreaterThan(moved.motion, 0.8)
        let bad = try XCTUnwrap(SceneAutoStatistics.measure(rgba: pixels, width: 2, height: 1, previousLuma: [.nan, 0]))
        XCTAssertEqual(bad.motion, 0)
    }
}
