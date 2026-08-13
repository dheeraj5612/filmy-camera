import SwiftUI

@main
struct FilmyCameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var cameraViewModel = CameraViewModel()
    @StateObject private var photoLibrary = PhotoLibraryService()
    @AppStorage(OnboardingStore.hasCompletedKey) private var hasCompletedOnboarding = false

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding || isUITesting {
                ContentView(
                    camera: camera,
                    cameraViewModel: cameraViewModel,
                    photoLibrary: photoLibrary
                )
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}
