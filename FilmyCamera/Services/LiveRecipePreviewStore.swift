import Combine
import CoreImage
import CoreGraphics
import SwiftUI

/// A small, upright snapshot of what the camera currently sees, used so that
/// every recipe swatch can show the actual scene rendered through that recipe
/// instead of a synthetic test pattern. `version` changes whenever the
/// snapshot is refreshed so views can re-render only when needed.
public struct RecipePreviewScene: Equatable, @unchecked Sendable {
    public let image: CIImage
    public let version: Int

    public static func == (lhs: RecipePreviewScene, rhs: RecipePreviewScene) -> Bool {
        lhs.version == rhs.version
    }
}

private struct RecipePreviewSceneKey: EnvironmentKey {
    static let defaultValue: RecipePreviewScene? = nil
}

extension EnvironmentValues {
    /// The live scene recipe swatches should render themselves over. Nil
    /// falls back to the renderer's built-in sample scene.
    var recipePreviewScene: RecipePreviewScene? {
        get { self[RecipePreviewSceneKey.self] }
        set { self[RecipePreviewSceneKey.self] = newValue }
    }
}

/// Samples the live viewfinder at a gentle cadence and publishes a reduced
/// snapshot for recipe previews. Rendering happens off the main thread and a
/// snapshot is only taken when the previous one has finished, so the rail can
/// never queue GPU work behind the viewfinder.
@MainActor
final class LiveRecipePreviewStore: ObservableObject {
    static let snapshotSize = CGSize(width: 264, height: 176)
    static let snapshotInterval: TimeInterval = 2.0

    @Published private(set) var scene: RecipePreviewScene?

    private weak var camera: CameraService?
    private var frameHandlerID: UUID?
    private var lastSnapshotTime: TimeInterval = 0
    private var isRendering = false
    private var renderTask: Task<Void, Never>?
    private var version = 0
    /// Bumped by `detach()` and `clear()`; a render that started under an
    /// older generation discards its result instead of publishing it.
    private var generation = 0

    func attach(to camera: CameraService) {
        guard frameHandlerID == nil || self.camera !== camera else { return }
        detach()
        self.camera = camera
        frameHandlerID = camera.installFrameHandler { [weak self] image in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self.receive(image) }
            } else {
                let box = FrameBox(image)
                Task { @MainActor in self.receive(box.image) }
            }
        }
    }

    func detach() {
        if let frameHandlerID, let camera {
            camera.removeFrameHandler(frameHandlerID)
        }
        frameHandlerID = nil
        camera = nil
        invalidatePendingRenders()
    }

    /// Clears the live scene so swatches fall back to the sample scene, e.g.
    /// while a review sheet is up and the session is stopped. A render still
    /// in flight is discarded so it cannot republish the old scene.
    func clear() {
        if scene != nil {
            scene = nil
        }
        invalidatePendingRenders()
    }

    private func invalidatePendingRenders() {
        generation &+= 1
        renderTask?.cancel()
        renderTask = nil
        isRendering = false
    }

    private func receive(_ image: CIImage) {
        let now = CACurrentMediaTime()
        guard !isRendering, now - lastSnapshotTime >= Self.snapshotInterval else { return }
        isRendering = true
        lastSnapshotTime = now

        let box = FrameBox(image)
        let size = Self.snapshotSize
        let startedGeneration = generation
        renderTask = Task.detached(priority: .utility) { [weak self] in
            guard !Task.isCancelled else { return }
            let target = CGRect(origin: .zero, size: size)
            let framed = CameraFrameLayout.aspectFill(box.image, in: target)
            let rendered = FilmRenderer.outputCGImage(framed, from: target)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == startedGeneration else { return }
                self.renderTask = nil
                self.isRendering = false
                guard let rendered else { return }
                self.version += 1
                self.scene = RecipePreviewScene(
                    image: CIImage(cgImage: rendered),
                    version: self.version
                )
            }
        }
    }
}

/// CIImage is immutable here but not declared Sendable on every supported
/// toolchain; box it for the hop between the capture callback and rendering.
private final class FrameBox: @unchecked Sendable {
    let image: CIImage

    init(_ image: CIImage) {
        self.image = image
    }
}

// MARK: - Live composition aids

import CoreMotion
import UIKit

@MainActor
final class CaptureCountdown: ObservableObject {
    @Published private(set) var state = CaptureTimerState()
    private var task: Task<Void, Never>?

    func start(seconds: Int, onFire: @escaping @MainActor () -> Void) {
        guard let id = state.begin(seconds: seconds) else { return }
        let clock = ContinuousClock()
        let started = clock.now
        task = Task { [weak self] in
            do {
                for tick in 1...seconds {
                    try await clock.sleep(until: started.advanced(by: .seconds(tick)))
                    try Task.checkCancellation()
                    guard let self, self.state.operationID == id else { return }
                    if self.state.tick(id), self.state.consume(id) {
                        self.task = nil
                        onFire()
                    }
                }
            } catch { /* Cancellation is an expected, silent outcome. */ }
        }
    }
    func cancel() { task?.cancel(); task = nil; state.cancel() }
}

@MainActor
final class CompositionAssistStore: ObservableObject {
    @Published private(set) var histogram: [Int] = []
    @Published private(set) var clippingPercent: Double = 0
    @Published private(set) var overlay: UIImage?
    @Published private(set) var horizon: Double?

    private let motion = CMMotionManager()
    private weak var camera: CameraService?
    private var handlerID: UUID?
    private var generation = 0
    private var busy = false
    private var lastSample: TimeInterval = 0
    private var options = Options()
    private var task: Task<Void, Never>?

    struct Options: Equatable, Sendable {
        var histogram = false
        var zebras = false
        var peaking = false
        var level = false
        var usesFrames: Bool { histogram || zebras || peaking }
    }
    private struct Output: @unchecked Sendable {
        let result: PreviewAnalysisMath.Result
        let overlay: CGImage?
    }

    func configure(camera: CameraService, options: Options, active: Bool) {
        let desired = active ? options : Options()
        guard desired != self.options || (desired.usesFrames && self.camera !== camera) else { return }
        stop()
        self.options = desired
        self.camera = camera
        if desired.usesFrames {
            handlerID = camera.installFrameHandler { [weak self] image in
                // CameraService delivers immutable preview frames on main.
                MainActor.assumeIsolated { self?.receive(image) }
            }
        }
        if desired.level, motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            let current = generation
            motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                let x = motion?.gravity.x, y = motion?.gravity.y
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.horizon = x.flatMap { x in y.flatMap { PreviewAnalysisMath.horizonDegrees(x: x, y: $0) } }
                }
            }
        }
    }

    func stop() {
        if let handlerID, let camera { camera.removeFrameHandler(handlerID) }
        handlerID = nil; camera = nil; generation &+= 1
        task?.cancel(); task = nil
        motion.stopDeviceMotionUpdates()
        histogram = []; overlay = nil; horizon = nil; clippingPercent = 0
        options = Options()
        // Do not clear `busy`: a canceled GPU operation must drain before the
        // next frame can start, even across a detach/reattach generation.
    }

    private func receive(_ image: CIImage) {
        let now = CACurrentMediaTime()
        guard !busy, now - lastSample >= 0.25, let camera else { return }
        let viewport = camera.previewViewportSize
        guard viewport.width > 0, viewport.height > 0 else { return }
        busy = true; lastSample = now
        let current = generation, options = options
        let box = FrameBox(image)
        task = Task.detached(priority: .utility) { [weak self] in
            let output = Self.analyze(box.image, viewport: viewport, options: options)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.generation == current else { return }
                self.task = nil
                guard let output else { self.overlay = nil; self.histogram = []; return }
                self.histogram = output.result.histogram
                self.clippingPercent = 100 * Double(output.result.clippedPixels) / Double(output.result.pixelCount)
                self.overlay = output.overlay.map { UIImage(cgImage: $0) }
            }
        }
    }

    private nonisolated static func analyze(_ image: CIImage, viewport: CGSize, options: Options) -> Output? {
        guard !Task.isCancelled, viewport.width.isFinite, viewport.height.isFinite else { return nil }
        let scale = CGFloat(PreviewAnalysisMath.maximumDimension) / max(viewport.width, viewport.height)
        let width = max(1, Int((viewport.width * scale).rounded(.down)))
        let height = max(1, Int((viewport.height * scale).rounded(.down)))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let framed = CameraFrameLayout.aspectFill(image, in: bounds)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        FilmRenderer.sharedContext.render(framed, toBitmap: &rgba, rowBytes: width * 4,
                                          bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        guard !Task.isCancelled,
              let result = PreviewAnalysisMath.analyze(rgba: rgba, width: width, height: height,
                                                       zebras: options.zebras, peaking: options.peaking) else { return nil }
        var overlay: CGImage?
        if options.zebras || options.peaking {
            let mask = CIImage(bitmapData: Data(result.overlayRGBA), bytesPerRow: width * 4,
                               size: bounds.size, format: .RGBA8, colorSpace: colorSpace)
            overlay = FilmRenderer.outputCGImage(mask, from: bounds)
        }
        return Output(result: result, overlay: overlay)
    }
}
