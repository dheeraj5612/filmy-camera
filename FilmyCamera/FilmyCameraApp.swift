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
