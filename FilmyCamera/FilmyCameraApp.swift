import SwiftUI

@main
struct FilmyCameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var cameraViewModel = CameraViewModel()
    @StateObject private var photoLibrary = PhotoLibraryService()
    @AppStorage(OnboardingStore.hasCompletedKey) private var hasCompletedOnboarding = false

    @State private var isShowingOnboarding: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let isOnboardingUITesting = arguments.contains("-ui-testing-onboarding")
        let hasCompletedOnboarding = UserDefaults.standard.bool(
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
            FilmRenderer.warmUp(recipe: CameraViewModel.launchRecipe())
        }
    }

    var body: some Scene {
        WindowGroup {
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
    }
}
