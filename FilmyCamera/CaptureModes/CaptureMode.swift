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

enum CaptureModesPolicy {
    static let maximumMovieSeconds: Double = 180
    static let maximumPanoramaPixels: Double = 24_000_000
    static let maximumPanoramaWidth: Double = 12_000
    static let maximumPanoramaHeight: Double = 12_000
    static let registrationLongEdge: Double = 1_536
    static let minimumFreeBytes: Int64 = 1_000_000_000

    static func supportsMacro(minimumFocusDistance: Int, autofocus: Bool) -> Bool {
        autofocus && minimumFocusDistance > 0 && minimumFocusDistance <= 50
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
}
