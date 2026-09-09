import Combine
import CoreImage
import CoreGraphics
import CoreMotion
import UIKit

/// CIImage is immutable here but not declared Sendable on every supported
/// toolchain; box it for the hop between the capture callback and rendering.
private final class FrameBox: @unchecked Sendable {
    let image: CIImage

    init(_ image: CIImage) {
        self.image = image
    }
}

// MARK: - Live composition aids

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
    private var rendering = PreviewRenderState()
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
        let current = rendering.generation
        if desired.usesFrames {
            handlerID = camera.installFrameHandler { [weak self] image in
                // CameraService delivers immutable preview frames on main.
                MainActor.assumeIsolated {
                    guard let self, self.rendering.generation == current else { return }
                    self.receive(image)
                }
            }
        }
        if desired.level, motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                let x = motion?.gravity.x, y = motion?.gravity.y
                MainActor.assumeIsolated {
                    guard let self, self.rendering.generation == current else { return }
                    self.horizon = x.flatMap { x in y.flatMap { PreviewAnalysisMath.horizonDegrees(x: x, y: $0) } }
                }
            }
        }
    }

    func stop() {
        if let handlerID, let camera { camera.removeFrameHandler(handlerID) }
        handlerID = nil; camera = nil; rendering.invalidate()
        task?.cancel(); task = nil
        motion.stopDeviceMotionUpdates()
        histogram = []; overlay = nil; horizon = nil; clippingPercent = 0
        options = Options()
    }

    private func receive(_ image: CIImage) {
        let now = CACurrentMediaTime()
        guard now - lastSample >= 0.25, let camera else { return }
        let viewport = camera.previewViewportSize
        guard viewport.width > 0, viewport.height > 0,
              let ticket = rendering.begin() else { return }
        lastSample = now
        let options = options
        let box = FrameBox(image)
        task = Task.detached(priority: .utility) { [weak self] in
            let output = Self.analyze(box.image, viewport: viewport, options: options)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.task = nil
                guard self.rendering.finish(ticket), self.camera?.previewViewportSize == viewport else { return }
                guard let output else {
                    self.overlay = nil; self.histogram = []; self.clippingPercent = 0
                    return
                }
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
