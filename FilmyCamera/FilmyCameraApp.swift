import SwiftUI

/// Automated tests may seed a Debug process, never a shipped app. Keeping all
/// argument parsing behind one compile-time boundary prevents test switches
/// from changing permissions, onboarding, or persistence in Release builds.
struct AppLaunchConfiguration: Equatable, Sendable {
    let isUITesting: Bool
    let isOnboardingUITesting: Bool
    let isViewfinderPreview: Bool
    let exposesPreviewStatus: Bool
    let isUnitTestHost: Bool
    let testDefaultsSuite: String?

    static let production = AppLaunchConfiguration(
        isUITesting: false,
        isOnboardingUITesting: false,
        isViewfinderPreview: false,
        exposesPreviewStatus: false,
        isUnitTestHost: false,
        testDefaultsSuite: nil
    )

    static let current: AppLaunchConfiguration = {
        #if DEBUG
        testing(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
        #else
        production
        #endif
    }()

    #if DEBUG
    static func testing(arguments: [String], environment: [String: String]) -> AppLaunchConfiguration {
        let isUITesting = arguments.contains("-ui-testing")
        let isOnboardingUITesting = arguments.contains("-ui-testing-onboarding")
        let requestedSuite = environment["FILMY_TEST_DEFAULTS_SUITE"]
        let suite = (isUITesting || isOnboardingUITesting)
            ? requestedSuite.flatMap { $0.hasPrefix("FilmyCameraUITests.") && $0.count > 19 ? $0 : nil }
            : nil
        return AppLaunchConfiguration(
            isUITesting: isUITesting,
            isOnboardingUITesting: isOnboardingUITesting,
            isViewfinderPreview: arguments.contains("-ui-testing-viewfinder-chrome"),
            exposesPreviewStatus: isUITesting || arguments.contains("-ui-testing-preview-status"),
            isUnitTestHost: environment["XCTestConfigurationFilePath"] != nil,
            testDefaultsSuite: suite
        )
    }
    #endif
}

@main
struct FilmyCameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var cameraViewModel: CameraViewModel
    @StateObject private var photoLibrary = PhotoLibraryService()
    @AppStorage(OnboardingStore.hasCompletedKey) private var hasCompletedOnboarding = false

    @State private var isShowingOnboarding: Bool
    private let preferences: UserDefaults

    init() {
        let launch = AppLaunchConfiguration.current
        let isUITesting = launch.isUITesting
        let isOnboardingUITesting = launch.isOnboardingUITesting
        // Each automated UI case owns its preferences, including relaunches.
        let testSuite = launch.testDefaultsSuite
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
                    OnboardingView(
                        recipes: cameraViewModel.recipes,
                        initialRecipeID: cameraViewModel.selectedRecipeID,
                        onSelectRecipe: { cameraViewModel.select(recipe: $0) }
                    ) {
                        hasCompletedOnboarding = true
                        isShowingOnboarding = false
                    }
                }
            }
            .defaultAppStorage(preferences)
        }
    }
}
