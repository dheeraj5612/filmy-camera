import CoreGraphics
import XCTest
@testable import FilmyCamera

final class CameraViewModelRenderingTests: XCTestCase {
    func testScaledGrainPhasePreservesValuesBeyondSeedBitRange() {
        let seed = UInt32(0x1FF) | (UInt32(0x1FF) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            previewSize: CGSize(width: 300, height: 600),
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 2044, accuracy: 0.001)
        XCTAssertEqual(phase.y, 2044, accuracy: 0.001)
    }

    func testScaledGrainPhaseFallsBackToPreviewPhaseForInvalidSizes() {
        let seed = UInt32(17) | (UInt32(29) << 9)
        let phase = CameraViewModel.scaledGrainPhase(
            seed,
            previewSize: .zero,
            stillSize: CGSize(width: 1200, height: 2400)
        )

        XCTAssertEqual(phase.x, 17, accuracy: 0.001)
        XCTAssertEqual(phase.y, 29, accuracy: 0.001)
    }
}
