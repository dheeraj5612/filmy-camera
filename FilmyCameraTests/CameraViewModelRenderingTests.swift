import CoreGraphics
import XCTest
@testable import FilmyCamera

final class CameraViewModelRenderingTests: XCTestCase {
    func testScaledGrainPhasePreservesValuesBeyondSeedBitRange() {
        let seed = UInt32(0x1FF) | (UInt32(0x1FF) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            grainSize: 1,
            previewSize: CGSize(width: 300, height: 600),
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 2044, accuracy: 0.001)
        XCTAssertEqual(phase.y, 2044, accuracy: 0.001)
    }

    func testScaledGrainPhaseUsesClampedRendererScaleForLargeGrain() {
        let phase = CameraViewModel.scaledGrainPhase(
            10 | (UInt32(20) << 9),
            grainSize: 2.5,
            previewSize: CGSize(width: 1080, height: 1080),
            stillSize: CGSize(width: 4320, height: 4320)
        )

        // Preview scale = 2.5; capture scale = min(2.5 * 4, 8) = 8.
        XCTAssertEqual(phase.x, 32, accuracy: 0.001)
        XCTAssertEqual(phase.y, 64, accuracy: 0.001)
        XCTAssertNotEqual(phase.x, 40, accuracy: 0.001)
        XCTAssertNotEqual(phase.y, 80, accuracy: 0.001)
    }

    func testScaledGrainPhaseFallsBackToPreviewPhaseForInvalidSizes() {
        let seed = UInt32(17) | (UInt32(29) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            grainSize: 1,
            previewSize: .zero,
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 17, accuracy: 0.001)
        XCTAssertEqual(phase.y, 29, accuracy: 0.001)
    }
}
