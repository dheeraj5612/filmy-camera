import SwiftUI

@main
struct FilmyCameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var cameraViewModel: CameraViewModel
    @StateObject private var photoLibrary = PhotoLibraryService()
    @AppStorage(OnboardingStore.hasCompletedKey) private var hasCompletedOnboarding = false

    @State private var isShowingOnboarding: Bool
    private let preferences: UserDefaults

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let isOnboardingUITesting = arguments.contains("-ui-testing-onboarding")
        // Each automated UI case owns its recipe/settings state. Reusing the
        // suite across relaunches still tests persistence without resetting
        // the developer's real preferences on a connected device.
        let requestedSuite = ProcessInfo.processInfo.environment["FILMY_TEST_DEFAULTS_SUITE"]
        let testSuite = (isUITesting || isOnboardingUITesting)
            ? requestedSuite.flatMap { $0.hasPrefix("FilmyCameraUITests.") ? $0 : nil }
            : nil
        let defaults = testSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        preferences = defaults
        _cameraViewModel = StateObject(wrappedValue: CameraViewModel(defaults: defaults))
        _hasCompletedOnboarding = AppStorage(
            wrappedValue: false, OnboardingStore.hasCompletedKey, store: defaults
        )
        let hasCompletedOnboarding = defaults.bool(
            forKey: OnboardingStore.hasCompletedKey
        )

        // The onboarding launch argument is a deterministic UI-test seed, not
        // a permanent routing override. Keeping that distinction in local
        // state lets the test tap through to ContentView after completion.
        _isShowingOnboarding = State(
            initialValue: isOnboardingUITesting
                || (!isUITesting && !hasCompletedOnboarding)
        )

        // Compile the film pipeline off the main thread while the camera
        // session configures, so the first live frame renders without a
        // shader-compilation stall.
        Task.detached(priority: .userInitiated) {
            let defaults = testSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
            FilmRenderer.warmUp(recipe: CameraViewModel.launchRecipe(defaults: defaults))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !isShowingOnboarding {
                    ContentView(
                        camera: camera,
                        cameraViewModel: cameraViewModel,
                        photoLibrary: photoLibrary
                    )
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                        isShowingOnboarding = false
                    }
                }
            }
            .defaultAppStorage(preferences)
        }
    }
}
