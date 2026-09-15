import Combine
@preconcurrency import CoreImage
import Foundation
import ImageIO
import UIKit
@preconcurrency import Vision

extension SmartRecipeProfile {
    init(recipe: FilmRecipe) {
        self.init(id: recipe.id, family: recipe.filmBase.rawValue, contrast: recipe.contrast,
                  saturation: recipe.saturation, highlights: recipe.tone.highlight, grain: recipe.grain,
                  warmth: recipe.whiteBalance.temperature + recipe.whiteBalance.mode.temperatureBias,
                  tint: recipe.whiteBalance.tint, exposure: recipe.exposure,
                  highlightProtection: max(recipe.dynamicRange.highlightProtection, recipe.dRangePriority.highlightProtection))
    }
}

struct SmartRecipeOption: Identifiable, Sendable {
    let recipe: FilmRecipe
    let reason: String
    var id: String { recipe.id }
}

/// Immutable, owned image copy, never a retained camera pixel buffer.
struct SmartRecipeSnapshot: @unchecked Sendable {
    let id: UUID
    let scene: SmartScene
    let image: CGImage
    let catalog: [FilmRecipe]
    let favoriteIDs: Set<String>
    let usedVision: Bool
    func options(intent: SmartRecipeIntent) -> [SmartRecipeOption] {
        let matches = SmartRecipeEngine.rank(scene: scene, profiles: catalog.map(SmartRecipeProfile.init(recipe:)),
                                             intent: intent, favoriteIDs: favoriteIDs)
        return matches.compactMap { match in
            guard let recipe = catalog.first(where: { $0.id == match.id }) else { return nil }
            return SmartRecipeOption(recipe: recipe, reason: match.reason)
        }
    }
}

/// Exclusive single-worker handoff; taking the image releases the box's reference.
final class SmartRecipeFrameBox: @unchecked Sendable {
    private var image: CIImage?
    init(_ image: CIImage) { self.image = image }
    func take() -> CIImage? { defer { image = nil }; return image }
}

struct SmartAnalyzedFrame: @unchecked Sendable {
    let scene: SmartScene
    let image: CGImage
    let usedVision: Bool
}

enum SmartRecipeAnalysisFailure: Error, Equatable, Sendable {
    case unusableFrame, renderingUnavailable
}

/// Core Image and Vision work, including context creation, stays on this private utility queue.
final class SmartRecipeImageWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.filmycamera.smart-recipes", qos: .utility)
    private var context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private func imageContext() -> CIContext {
        if let context { return context }
        let created = CIContext(options: [.cacheIntermediates: false])
        context = created
        return created
    }

    func analyze(frame: SmartRecipeFrameBox, viewport: CGSize,
                 completion: @escaping @Sendable (Result<SmartAnalyzedFrame, SmartRecipeAnalysisFailure>) -> Void) {
        queue.async { [self] in
            // Explicit eager rendering releases the camera-backed image before Vision begins.
            guard let image = autoreleasepool(invoking: { makeSnapshot(frame: frame, viewport: viewport) }) else {
                completion(.failure(.renderingUnavailable))
                return
            }
            let result: Result<SmartAnalyzedFrame, SmartRecipeAnalysisFailure> = autoreleasepool {
                guard let metrics = measure(image), metrics.isUsable else { return .failure(.unusableFrame) }
                let classifier = VNClassifyImageRequest()
                let faces = VNDetectFaceRectanglesRequest()
                classifier.preferBackgroundProcessing = true
                faces.preferBackgroundProcessing = true
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                var usedVision = false
                do {
                    try handler.perform([classifier, faces])
                    usedVision = true
                } catch {
                    // Metrics-only fallback describes light/color rather than asserting a subject.
                }
                let labels: [SmartSceneClassification] = usedVision
                    ? (classifier.results ?? []).prefix(16).map {
                        SmartSceneClassification(identifier: $0.identifier, confidence: Double($0.confidence))
                    } : []
                let observations = usedVision ? faces.results ?? [] : []
                let coverage = observations.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
                guard let scene = SmartScene.interpret(metrics: metrics, classifications: labels,
                    faceCount: observations.count, faceCoverage: min(coverage, 1)) else { return .failure(.unusableFrame) }
                return .success(SmartAnalyzedFrame(scene: scene, image: image, usedVision: usedVision))
            }
            completion(result)
        }
    }

    private func makeSnapshot(frame: SmartRecipeFrameBox, viewport: CGSize) -> CGImage? {
        guard let image = frame.take(), !image.extent.isEmpty, !image.extent.isInfinite, !image.extent.isNull,
              image.extent.width.isFinite, image.extent.height.isFinite,
              image.extent.origin.x.isFinite, image.extent.origin.y.isFinite else { return nil }
        let size = viewport.width > 0 && viewport.height > 0 && viewport.width.isFinite && viewport.height.isFinite
            ? viewport : image.extent.size
        let scale = 384 / max(size.width, size.height)
        let target = CGRect(x: 0, y: 0, width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        // Frames already have the display rotation/mirroring. Match the visible aspect-fill crop.
        let cropped = CameraFrameLayout.aspectFill(image, in: target)
        return imageContext().createCGImage(cropped, from: target, format: .RGBA8, colorSpace: colorSpace, deferred: false)
    }

    private func measure(_ image: CGImage) -> SmartSceneMetrics? {
        let size = 48
        let source = CIImage(cgImage: image).transformed(by: CGAffineTransform(
            scaleX: CGFloat(size) / CGFloat(image.width), y: CGFloat(size) / CGFloat(image.height)))
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            imageContext().render(source, toBitmap: address, rowBytes: size * 4,
                bounds: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBA8, colorSpace: colorSpace)
        }
        return SmartSceneMetrics.measure(rgba: bytes)
    }
}

@MainActor
final class SmartRecipeStore: ObservableObject {
    enum Status: Equatable {
        case off, waiting, analyzing, ready, insufficientLight, cooling, unavailable
        var title: String {
            switch self {
            case .off: return "Smart looks off"
            case .waiting: return "Smart looks"
            case .analyzing: return "Reading the scene"
            case .ready: return "Smart looks"
            case .insufficientLight: return "Point at a scene"
            case .cooling: return "Suggestions paused for heat"
            case .unavailable: return "Light-based suggestions unavailable"
            }
        }
    }
    static let enabledKey = "smartRecipes.enabled.v1"
    static let intentKey = "smartRecipes.intent.v1"
    @Published private(set) var isEnabled: Bool
    @Published private(set) var intent: SmartRecipeIntent
    @Published private(set) var snapshot: SmartRecipeSnapshot?
    @Published private(set) var status: Status = .waiting
    @Published private(set) var undo: SmartRecipeUndo?
    private let defaults: UserDefaults
    private let worker = SmartRecipeImageWorker()
    private weak var camera: CameraService?
    private var handlerID: UUID?
    private var gate = SmartRecipeAnalysisGate()
    private var stabilizer = SmartRecipeStabilizer()
    private var catalog: [FilmRecipe] = []
    private var favoriteIDs: Set<String> = []
    private var isActive = false
    private var lastFrameTime: TimeInterval?
    private var consecutiveFailures = 0

    init(defaults explicitDefaults: UserDefaults? = nil) {
        // Match the app's isolated UI-test preferences, never a developer's real settings.
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing") || arguments.contains("-ui-testing-real-roll")
            || arguments.contains("-ui-testing-onboarding")
        let suite = isUITesting ? ProcessInfo.processInfo.environment["FILMY_TEST_DEFAULTS_SUITE"] : nil
        let testDefaults = suite.flatMap { $0.hasPrefix("FilmyCameraUITests.") ? UserDefaults(suiteName: $0) : nil }
        let defaults = explicitDefaults ?? testDefaults ?? .standard
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey)
        intent = SmartRecipeIntent(rawValue: defaults.string(forKey: Self.intentKey) ?? "") ?? .balanced
        if !isEnabled { status = .off }
    }
    deinit { if let handlerID { camera?.removeFrameHandler(handlerID) } }
    var options: [SmartRecipeOption] { snapshot?.options(intent: intent) ?? [] }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { stop() }
        status = enabled ? .waiting : .off
    }
    func setIntent(_ value: SmartRecipeIntent) {
        guard intent != value else { return }
        intent = value
        defaults.set(value.rawValue, forKey: Self.intentKey)
        gate.invalidate()
        stabilizer.reset()
    }
    func configure(camera: CameraService, active: Bool, recipes: [FilmRecipe], favoriteIDs: Set<String> = []) {
        if self.camera !== camera { stop(); self.camera = camera }
        if catalog != recipes || self.favoriteIDs != favoriteIDs {
            catalog = recipes
            self.favoriteIDs = favoriteIDs
            invalidateScene()
        }
        guard active, isEnabled, !recipes.isEmpty else { stop(); return }
        isActive = true
        guard handlerID == nil else { return }
        status = .analyzing
        handlerID = camera.installFrameHandler { [weak self] image in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.receive(image) }
            } else {
                let box = SmartRecipeFrameBox(image)
                DispatchQueue.main.async { [weak self] in
                    if let image = box.take() { self?.receive(image) }
                }
            }
        }
    }
    func stop() {
        if let handlerID { camera?.removeFrameHandler(handlerID) }
        handlerID = nil
        isActive = false
        invalidateScene()
        status = isEnabled ? .waiting : .off
    }
    /// Invalidates analysis on lens, zoom, orientation, crop, and camera-position changes.
    func invalidateScene() {
        gate.invalidate()
        stabilizer.reset()
        snapshot = nil
        lastFrameTime = nil
        consecutiveFailures = 0
        if isEnabled && isActive { status = .analyzing }
    }
    func recordSelection(previousID: String, appliedID: String) {
        guard previousID != appliedID else { return }
        undo = SmartRecipeUndo(previousID: previousID, appliedID: appliedID)
    }
    func reconcileSelection(currentID: String, availableIDs: Set<String>) {
        if undo?.target(currentID: currentID, availableIDs: availableIDs) == nil { undo = nil }
    }
    func clearUndo() { undo = nil }

    private func receive(_ image: CIImage) {
        guard isActive, isEnabled, let camera else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastFrameTime, now - lastFrameTime > 6 { invalidateScene() }
        lastFrameTime = now
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            if status != .cooling { invalidateScene(); status = .cooling }
            return
        }
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 4.0 : thermal == .fair ? 3.0 : 1.5
        guard let ticket = gate.begin(now: now, interval: interval) else { return }
        if snapshot == nil { status = .analyzing }
        let recipes = catalog
        let favorites = favoriteIDs
        let requestedIntent = intent
        worker.analyze(frame: SmartRecipeFrameBox(image), viewport: camera.previewViewportSize) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.gate.finish(ticket), self.isActive, self.isEnabled else { return }
                switch result {
                case .success(let frame):
                    self.consecutiveFailures = 0
                    let candidate = SmartRecipeSnapshot(id: UUID(), scene: frame.scene, image: frame.image,
                        catalog: recipes, favoriteIDs: favorites, usedVision: frame.usedVision)
                    let identifiers = candidate.options(intent: requestedIntent).map(\.id)
                    let signature = ([frame.scene.kind.rawValue, requestedIntent.rawValue] + identifiers).joined(separator: "|")
                    if self.stabilizer.shouldPublish(signature: signature, now: ProcessInfo.processInfo.systemUptime) {
                        self.snapshot = candidate
                        self.status = identifiers.isEmpty ? .unavailable : .ready
                    } else if self.stabilizer.displayed == signature {
                        // Refresh the owned small frame without reshuffling tap targets.
                        self.snapshot = candidate
                        self.status = identifiers.isEmpty ? .unavailable : .ready
                    }
                case .failure(let error):
                    self.consecutiveFailures += 1
                    if error == .unusableFrame || self.consecutiveFailures >= 2 {
                        self.snapshot = nil
                        self.stabilizer.reset()
                        self.status = error == .unusableFrame ? .insufficientLight : .unavailable
                    }
                }
            }
        }
    }
}
