import Foundation

/// Modes are persisted by stable identifiers, never by picker positions.
enum CaptureMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case photo, burst, macro, portrait, filmVideo, night, panorama, spatialVideo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .photo: return "Photo"
        case .burst: return "Burst"
        case .macro: return "Macro"
        case .portrait: return "Portrait"
        case .filmVideo: return "Film video"
        case .night: return "Filmy Night"
        case .panorama: return "Panorama"
        case .spatialVideo: return "Spatial video"
        }
    }
    var symbol: String {
        switch self {
        case .photo: return "camera"
        case .burst: return "square.stack.3d.up"
        case .macro: return "camera.macro"
        case .portrait: return "person.crop.rectangle"
        case .filmVideo: return "video"
        case .night: return "moon.stars"
        case .panorama: return "pano"
        case .spatialVideo: return "view.3d"
        }
    }
    var guidance: String {
        switch self {
        case .photo: return "Your film recipe, with reference and scene tools."
        case .burst: return "Hold to shoot. Release to finish, or tap to start and stop. Up to 40 frames."
        case .macro: return "Autofocusing ultra-wide lens. Move close, then tap your subject to focus."
        case .portrait: return "Real camera depth with center-subject bokeh. Keep your subject near the center; originals retain depth."
        case .filmVideo: return "4K where supported. The film look is rendered after recording; the original is retained."
        case .night: return "Hold still for 8 frames. Registration and motion rejection reduce noise before the film look."
        case .panorama: return "Experimental: sweep slowly left to right, keep the horizon level, then tap Stop."
        case .spatialVideo: return "Hold the phone horizontally. Native stereo is retained, without a flattening film filter."
        }
    }
    var isVideo: Bool { self == .filmVideo || self == .spatialVideo }
    var frameLimit: Int {
        switch self {
        case .burst: return 40
        case .night: return 8
        case .panorama: return 12
        default: return 1
        }
    }
    var minimumFrames: Int { self == .night || self == .panorama ? 3 : 1 }
}

enum CaptureModesPhase: String, Sendable {
    case stopped, configuring, ready, capturing, recording, processing, unavailable
    var isBusy: Bool { self == .capturing || self == .recording || self == .processing || self == .configuring }
}

/// The one-in-flight contract prevents burst/night/panorama from exhausting
/// AVCapturePhotoOutput or retaining an unbounded set of full-resolution buffers.
struct CaptureSequence: Sendable {
    let id: UUID
    let mode: CaptureMode
    private(set) var completedFrames = 0
    private(set) var inFlightIndex: Int?
    private(set) var stopRequested = false

    init(mode: CaptureMode, id: UUID = UUID()) {
        self.mode = mode
        self.id = id
    }

    mutating func reserveFrame() -> Int? {
        guard !stopRequested, inFlightIndex == nil, completedFrames < mode.frameLimit else { return nil }
        inFlightIndex = completedFrames
        return inFlightIndex
    }

    @discardableResult
    mutating func completeFrame(_ index: Int) -> Bool {
        guard inFlightIndex == index else { return false }
        inFlightIndex = nil
        completedFrames += 1
        return true
    }

    mutating func requestStop() { stopRequested = true }
    var shouldFinish: Bool { inFlightIndex == nil && (stopRequested || completedFrames >= mode.frameLimit) }
}

struct CaptureModesState: Sendable {
    var mode: CaptureMode = .photo
    var phase: CaptureModesPhase = .stopped
    var message = "Choose a capture mode."
    var format = ""
    var recipeName = ""
    var frameCount = 0
    var seconds = 0
    var microphoneEnabled = false
    var hasDepth = false
    var controlsSupported = false
    var controlsExpanded = false
    var zoom: Double = 1
    var maximumZoom: Double = 1
    var exposure: Double = 0
    var minimumExposure: Double = -2
    var maximumExposure: Double = 2
    var focusLocked = false
    var scanning = false
    var warning: String?
}

struct CaptureMedia: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case originalsOnly, ready }
    let id: UUID
    let mode: CaptureMode
    let createdAt: Date
    let recipeName: String
    var originals: [String] = []
    var outputs: [String] = []
    var status: Status = .originalsOnly
    var width = 0
    var height = 0
    var acceptedFrames = 0
    var notes: [String] = []
    /// One slot per output. A retried export skips slots already confirmed by Photos.
    var photosIdentifiers: [String: String] = [:]
    var isExported: Bool { !outputs.isEmpty && outputs.allSatisfy { photosIdentifiers[$0] != nil } }
}

enum CaptureModesError: LocalizedError, Sendable {
    case unavailable(String)
    case insufficientFrames(Int)
    case invalidImage
    case diskSpace
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .insufficientFrames(let count): return "Only \(count) usable frames were captured. Originals are retained. Try again more slowly."
        case .invalidImage: return "The image could not be decoded or rendered. Its original is retained."
        case .diskSpace: return "Free at least 1 GB of storage before capturing. Existing captures are unchanged."
        case .cancelled: return "Capture stopped. Any completed originals are retained in Captures."
        }
    }
}

/// A control the essentials row can offer for the open mode.
enum CaptureEssential: Equatable {
    case film, zoom, exposure, microphone
}

enum CaptureModesPolicy {
    static let maximumMovieSeconds: Double = 180
    static let maximumPanoramaPixels: Double = 24_000_000
    static let maximumPanoramaWidth: Double = 12_000
    static let maximumPanoramaHeight: Double = 12_000
    static let registrationLongEdge: Double = 1_536
    static let minimumFreeBytes: Int64 = 1_000_000_000

    /// Angle for the photo and movie connections: the rotation coordinator's horizon-level capture angle
    /// snapped to a quarter turn, else `fallback` snapped the same way, else portrait (90).
    /// Total: an unreadable angle can never block a capture.
    static func captureRotationAngle(horizonLevel: Double?, fallback: Double) -> Double {
        quarterTurn(horizonLevel) ?? quarterTurn(fallback) ?? 90
    }

    private static func quarterTurn(_ angle: Double?) -> Double? {
        guard let angle, angle.isFinite else { return nil }
        var turn = angle.truncatingRemainder(dividingBy: 360)
        if turn < 0 { turn += 360 }
        let quarters = Int((turn / 90).rounded()) % 4
        return Double(quarters * 90)
    }

    static func microphoneNotice(isVideo: Bool, wantsMicrophone: Bool, audioAllowed: Bool, alreadyShown: Bool) -> (show: Bool, shown: Bool) {
        var shown = alreadyShown
        if !wantsMicrophone || audioAllowed { shown = false }
        if isVideo, wantsMicrophone, !audioAllowed, !shown { return (true, true) }
        return (false, shown)
    }

    /// The shutter offers Stop only for work the user can end: a recording or a frame sequence, not the one-shot scene read.
    static func isStoppable(phase: CaptureModesPhase, scanning: Bool) -> Bool {
        phase == .recording || (phase == .capturing && !scanning)
    }

    /// Line under the viewfinder. The preview is always optical: this says when the film look reaches the picture.
    /// Nil for Spatial video (no film look) and while Film video shows its guidance, which already says it.
    static func filmLookNote(mode: CaptureMode, showingGuidance: Bool) -> String? {
        switch mode {
        case .spatialVideo: return nil
        case .filmVideo: return showingGuidance ? nil : "Film look is added after you stop recording. Originals are kept."
        case .photo, .burst, .macro, .portrait, .night, .panorama: return "Film look is added after you shoot. Originals are kept."
        }
    }

    /// Indexes the film list shows, in order. `matches[i]` says whether film `i` fits the search. Only matching films are
    /// listed, catalog order kept, except the current film, which comes first when it matches.
    static func filmPickerOrder(matches: [Bool], current: Int?) -> [Int] {
        let listed = matches.indices.filter { matches[$0] }
        guard let current, listed.contains(current) else { return listed }
        return [current] + listed.filter { $0 != current }
    }

    /// The shutter vibrates only when a tap starts a single still or a burst. Video, spatial video, Filmy Night
    /// and Panorama stay silent: the motor would reach the microphone or the frames held still. Stop taps never vibrate.
    static func playsShutterHaptic(mode: CaptureMode, phase: CaptureModesPhase) -> Bool {
        guard phase == .ready else { return false }
        switch mode {
        case .photo, .burst, .macro, .portrait: return true
        case .filmVideo, .night, .panorama, .spatialVideo: return false
        }
    }

    /// The display stays awake only while the workspace is usable; a denied or paused camera lets it sleep.
    static func keepsScreenAwake(sceneActive: Bool, cameraReleased: Bool, closing: Bool, phase: CaptureModesPhase) -> Bool {
        sceneActive && cameraReleased && !closing && phase != .unavailable && phase != .stopped
    }

    static func supportsMacro(minimumFocusDistance: Int, autofocus: Bool) -> Bool {
        autofocus && minimumFocusDistance > 0 && minimumFocusDistance <= 50
    }

    /// The essentials row for the open mode, in display order. Spatial video has no film look, zoom or exposure here;
    /// zoom and exposure appear only when the hardware range is wider than one step.
    static func essentials(mode: CaptureMode, requestedMode: CaptureMode, maximumZoom: Double,
                           minimumExposure: Double, maximumExposure: Double) -> [CaptureEssential] {
        var items: [CaptureEssential] = []
        if mode != .spatialVideo {
            items.append(.film)
            if maximumZoom > 1 { items.append(.zoom) }
            if maximumExposure > minimumExposure { items.append(.exposure) }
        }
        if requestedMode.isVideo { items.append(.microphone) }
        return items
    }

    /// Captions for the About sheet, in display order: video length, portrait depth, Camera Control.
    static func modeNotes(requestedMode: CaptureMode, configuredMode: CaptureMode, controlsSupported: Bool) -> [String] {
        var notes: [String] = []
        if requestedMode.isVideo {
            notes.append("Up to three minutes per clip. Keep Filmy open while developing the film look.")
        }
        if configuredMode == .portrait {
            notes.append("Depth-based center-subject bokeh at f/4. The original depth-bearing HEIC is always retained.")
        }
        notes.append(controlsSupported ? "Camera Control: shutter, zoom, exposure, mode, film, and focus where supported."
                     : "On-screen controls remain available without Camera Control hardware.")
        return notes
    }

    /// The About sheet stays closed while a capture runs, so the Stop control is never covered.
    static func allowsModeInfo(phase: CaptureModesPhase) -> Bool {
        switch phase {
        case .capturing, .recording, .processing: return false
        case .stopped, .configuring, .ready, .unavailable: return true
        }
    }

    /// Why a mode can be missing on some hardware, as a full sentence. Nil for modes every supported device offers.
    static func unavailableReason(for mode: CaptureMode) -> String? {
        switch mode {
        case .macro: return "Macro needs an ultra-wide camera that focuses up close."
        case .portrait: return "Portrait needs a dual, triple or depth camera."
        case .spatialVideo: return "Spatial video needs a device that records spatial video."
        case .photo, .burst, .filmVideo, .night, .panorama: return nil
        }
    }

    /// One line for the main screen: the reason when one mode is missing, the titles plus a pointer to About when several are.
    static func unavailableSummary(_ modes: [CaptureMode]) -> String? {
        let missing = modes.filter { unavailableReason(for: $0) != nil }
        guard let first = missing.first else { return nil }
        if missing.count == 1, let reason = unavailableReason(for: first) { return "Not on this device: " + reason }
        let titles = missing.map(\.title).joined(separator: ", ")
        return "Not on this device: " + titles + ". About this mode lists why."
    }

    static func acceptableNightTranslation(x: Double, y: Double, width: Double, height: Double) -> Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
            && abs(x) <= width * 0.08 && abs(y) <= height * 0.08
    }

    static func acceptablePanoramaBounds(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width >= 1 && height >= 1
            && width <= maximumPanoramaWidth && height <= maximumPanoramaHeight
            && width * height <= maximumPanoramaPixels
    }

    /// Never open executable/custom schemes, embedded credentials, or unparsed OCR text.
    static func safeWebURL(_ value: String) -> URL? {
        guard value.count <= 4_096,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return components.url
    }

    static func isSafeFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    /// File a Captures thumbnail is read from: the first developed file, else the first original. Nil when none or unsafe.
    static func thumbnailFile(outputs: [String], originals: [String]) -> String? {
        guard let name = outputs.first ?? originals.first, isSafeFilename(name) else { return nil }
        return name
    }

    /// Where the developed files are, always as words plus a symbol. Export persists one output at a time, so an
    /// interrupted export is partly in Photos.
    static func photosStatus(_ media: CaptureMedia) -> (text: String, symbol: String) {
        if media.isExported { return ("In Photos", "checkmark.circle") }
        if media.outputs.contains(where: { media.photosIdentifiers[$0] != nil }) { return ("Partly in Photos", "circle.lefthalf.filled") }
        return ("Not in Photos", "iphone")
    }

    /// Share rows are numbered by kind, never named by file. `index` is zero-based.
    static func shareLabel(original: Bool, isVideo: Bool, index: Int) -> String {
        if original { return "Share original \(index + 1)" }
        return isVideo ? "Share video \(index + 1)" : "Share photo \(index + 1)"
    }

    /// After-shot card status line. An originals-only record has nothing to export yet.
    static func savedCardStatus(_ media: CaptureMedia) -> (text: String, symbol: String) {
        if media.outputs.isEmpty { return ("Film look not applied. Open to retry.", "exclamationmark.circle") }
        return photosStatus(media)
    }

    /// A shot starts when the phase leaves Ready for capturing, recording or processing (SwiftUI may coalesce the
    /// intermediate phase). Read scene never counts.
    static func startsShot(from old: CaptureModesPhase, to new: CaptureModesPhase, scanning: Bool) -> Bool {
        old == .ready && !scanning && (new == .capturing || new == .recording || new == .processing)
    }

    /// The record a finished shot produced: the newest one not listed when the shot started and created after the
    /// workspace opened. Retries (already listed) and older captures loading late never qualify. `captures` is newest first.
    static func finishedCapture(in captures: [CaptureMedia], known: Set<UUID>, openedAt: Date) -> CaptureMedia? {
        captures.first { !known.contains($0.id) && $0.createdAt >= openedAt }
    }
}
