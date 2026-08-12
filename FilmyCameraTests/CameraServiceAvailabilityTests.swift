import XCTest
@testable import FilmyCamera

@MainActor
final class CameraServiceAvailabilityTests: XCTestCase {
    func testCameraStartsWithAnExplicitIdleAvailability() {
        let camera = CameraService()

        XCTAssertEqual(camera.availability, .idle)
        XCTAssertFalse(camera.isRunning)
        XCTAssertEqual(camera.statusMessage, "Camera is ready")
    }

    func testAvailabilityCasesHaveStablePersistenceValues() {
        let cases: [CameraService.Availability] = [
            .idle,
            .starting,
            .requestingPermission,
            .running,
            .paused,
            .simulator,
            .permissionDenied,
            .interrupted,
            .needsRecovery,
            .unavailable
        ]

        XCTAssertEqual(Set(cases.map(\.rawValue)).count, cases.count)
        XCTAssertEqual(CameraService.Availability.permissionDenied.rawValue, "permissionDenied")
        XCTAssertEqual(CameraService.Availability.needsRecovery.rawValue, "needsRecovery")
    }
}
