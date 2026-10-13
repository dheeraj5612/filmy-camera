import AppIntents
import Foundation

/// A one-shot foreground route, not an instruction to capture without confirmation.
enum CaptureModesLaunch {
    static let key = "FilmyCaptureModesPendingRoute"
    static let notification = Notification.Name("FilmyCaptureModesRequested")
    static func peek() -> CaptureMode? {
        UserDefaults.standard.string(forKey: key).flatMap(CaptureMode.init(rawValue:))
    }
    static func take() -> CaptureMode? {
        let mode = peek()
        UserDefaults.standard.removeObject(forKey: key)
        return mode
    }
    @MainActor static func request(_ mode: CaptureMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

enum FilmyIntentMode: String, AppEnum {
    case photo, burst, macro, portrait, filmVideo, night, panorama, spatialVideo
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Capture mode")
    static let caseDisplayRepresentations: [FilmyIntentMode: DisplayRepresentation] = [
        .photo: "Photo", .burst: "Burst", .macro: "Macro", .portrait: "Portrait", .filmVideo: "Film video",
        .night: "Filmy Night", .panorama: "Panorama", .spatialVideo: "Spatial video"
    ]
}

struct OpenFilmyModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Filmy capture mode"
    static let description = IntentDescription("Open a capture mode in Filmy. Recording starts only after you press the shutter.")
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Mode", default: .photo) var mode: FilmyIntentMode
    init() {}
    init(mode: FilmyIntentMode) { self.mode = mode }
    @MainActor func perform() async throws -> some IntentResult {
        CaptureModesLaunch.request(CaptureMode(rawValue: mode.rawValue) ?? .photo)
        return .result()
    }
}

/// Makes Filmy discoverable to Camera quick actions. This opens the foreground app;
/// it does not claim to be a sandboxed LockedCameraCapture extension.
@available(iOS 18.0, *)
struct OpenFilmyCameraIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "Open Filmy Camera"
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        CaptureModesLaunch.request(.photo)
        return .result()
    }
}

struct FilmyCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFilmyModeIntent(mode: .photo), phrases: ["Open \(.applicationName) camera"],
                    shortTitle: "Open camera", systemImageName: "camera")
        AppShortcut(intent: OpenFilmyModeIntent(mode: .night), phrases: ["Open \(.applicationName) Night"],
                    shortTitle: "Filmy Night", systemImageName: "moon.stars")
        AppShortcut(intent: OpenFilmyModeIntent(mode: .filmVideo), phrases: ["Open \(.applicationName) video"],
                    shortTitle: "Film video", systemImageName: "video")
        AppShortcut(intent: OpenFilmyModeIntent(mode: .macro), phrases: ["Open \(.applicationName) macro"],
                    shortTitle: "Macro", systemImageName: "camera.macro")
    }
}
