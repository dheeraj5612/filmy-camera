import Combine
import CoreImage
import UIKit
import Vision

/// Preview-space geometry is deliberately separate from AVFoundation's sensor
/// coordinates. CameraScreen applies the same crop/rotation/mirror transform
/// as tap-to-focus before delivering a tracked point to CameraService.
enum FocusAssistGeometry {
    static func seed(at point: CGPoint) -> CGRect {
        let x = point.x.isFinite ? min(max(point.x, 0), 1) : 0.5
        let y = point.y.isFinite ? min(max(point.y, 0), 1) : 0.5
        return CGRect(x: min(max(x - 0.09, 0), 0.82), y: min(max(1 - y - 0.09, 0), 0.82), width: 0.18, height: 0.18)
    }
    static func displayPoint(_ visionBox: CGRect) -> CGPoint {
        CGPoint(x: visionBox.midX, y: 1 - visionBox.midY)
    }
    static func displayRect(_ visionBox: CGRect, size: CGSize) -> CGRect {
        CGRect(x: visionBox.minX * size.width, y: (1 - visionBox.maxY) * size.height,
               width: visionBox.width * size.width, height: visionBox.height * size.height)
    }
}

/// Only one task per worker exists. Reconfiguration creates a new worker,
/// rather than concurrently touching VNSequenceRequestHandler after cancel.
private final class FocusTrackingWorker: @unchecked Sendable {
    struct Output: @unchecked Sendable {
        let box: CGRect?
        let loupe: CGImage?
        let lost: Bool
    }
    private let sequence = VNSequenceRequestHandler()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var observation: VNDetectedObjectObservation?
    private var previousDisplayBox: CGRect?
    private var lost = false
    private let seed: CGPoint?
    private var initialFrame = true
    init(seed: CGPoint?) { self.seed = seed }

    func process(image: CIImage, viewport: CGSize, tracking: Bool, loupe: Bool, magnification: Double) -> Output {
        autoreleasepool {
            let ratio = viewport.width / max(viewport.height, 1)
            let size = ratio >= 1 ? CGSize(width: 720, height: 720 / ratio) : CGSize(width: 720 * ratio, height: 720)
            let framed = CameraFrameLayout.aspectFill(image, in: CGRect(origin: .zero, size: size))
            guard let cgImage = context.createCGImage(framed, from: framed.extent) else {
                return Output(box: nil, loupe: nil, lost: true)
            }
            var box: CGRect?
            if tracking, !lost {
                do {
                    if initialFrame, let seed {
                        observation = VNDetectedObjectObservation(boundingBox: FocusAssistGeometry.seed(at: seed))
                    } else if observation == nil {
                        let faces = VNDetectFaceRectanglesRequest()
                        try VNImageRequestHandler(cgImage: cgImage).perform([faces])
                        if let face = faces.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
                            observation = VNDetectedObjectObservation(boundingBox: face.boundingBox)
                        }
                    } else if let observation {
                        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                        request.trackingLevel = .accurate
                        try sequence.perform([request], on: cgImage)
                        guard let result = request.results?.first, result.confidence >= 0.55,
                              !result.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)).isEmpty else {
                            self.observation = nil
                            lost = true
                            return Output(box: nil, loupe: loupeImage(framed, point: seed ?? CGPoint(x: 0.5, y: 0.5),
                                enabled: loupe, magnification: magnification), lost: true)
                        }
                        self.observation = result
                    }
                    box = observation?.boundingBox
                    if let box, let previous = previousDisplayBox {
                        // Smooth display/AF coordinates, not Vision's next observation.
                        self.previousDisplayBox = CGRect(x: previous.minX * 0.4 + box.minX * 0.6,
                            y: previous.minY * 0.4 + box.minY * 0.6, width: box.width, height: box.height)
                    } else { previousDisplayBox = box }
                    box = previousDisplayBox
                } catch { observation = nil; lost = true }
            }
            initialFrame = false
            let point = box.map(FocusAssistGeometry.displayPoint) ?? seed ?? CGPoint(x: 0.5, y: 0.5)
            return Output(box: box, loupe: loupeImage(framed, point: point, enabled: loupe, magnification: magnification), lost: lost)
        }
    }

    private func loupeImage(_ image: CIImage, point: CGPoint, enabled: Bool, magnification: Double) -> CGImage? {
        guard enabled else { return nil }
        let zoom = magnification.isFinite ? min(max(magnification, 2), 4) : 2
        let extent = image.extent
        let side = min(extent.width, extent.height) / zoom
        let crop = CGRect(x: min(max(point.x * extent.width - side / 2, 0), extent.width - side),
            y: min(max((1 - point.y) * extent.height - side / 2, 0), extent.height - side), width: side, height: side)
        return context.createCGImage(image.cropped(to: crop), from: crop)
    }
}

@MainActor
final class FocusAssistStore: ObservableObject {
    @Published private(set) var box: CGRect?
    @Published private(set) var trackedPoint: CGPoint?
    @Published private(set) var loupe: UIImage?
    @Published private(set) var subjectLost = false
    private var worker = FocusTrackingWorker(seed: nil)
    private weak var camera: CameraService?
    private var handler: UUID?
    private var token = UUID()
    private var busy = false
    private var lastFrame: TimeInterval = 0
    private var task: Task<Void, Never>?
    private var options = Options()
    private var viewport = CGSize.zero
    struct Options: Equatable, Sendable {
        var tracking = false
        var loupe = false
        var magnification: Double = 2
    }
    private struct Input: @unchecked Sendable { let image: CIImage }

    func configure(camera: CameraService, options: Options, active: Bool) {
        let next = active ? options : Options()
        let size = camera.previewViewportSize
        guard next != self.options || size != viewport || (active && self.camera !== camera) else { return }
        stop()
        self.options = next
        viewport = size
        self.camera = camera
        guard (next.tracking || next.loupe), size.width > 0, size.height > 0 else { return }
        handler = camera.installFrameHandler { [weak self] image in
            MainActor.assumeIsolated { self?.receive(image) }
        }
    }

    func select(at point: CGPoint) {
        guard options.tracking || options.loupe else { return }
        reset(seed: point)
    }
    func reset(seed: CGPoint? = nil) {
        token = UUID()
        task?.cancel()
        task = nil
        busy = false
        worker = FocusTrackingWorker(seed: seed)
        box = nil; trackedPoint = nil; loupe = nil; subjectLost = false
    }
    func stop() {
        if let handler { camera?.removeFrameHandler(handler) }
        handler = nil
        camera = nil
        options = Options()
        reset()
    }
    private func receive(_ image: CIImage) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !busy, now - lastFrame >= 0.15 else { return }
        busy = true
        lastFrame = now
        let input = Input(image: image)
        let worker = self.worker
        let ticket = token
        let options = self.options
        let viewport = self.viewport
        task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                worker.process(image: input.image, viewport: viewport, tracking: options.tracking,
                               loupe: options.loupe, magnification: options.magnification)
            }.value
            guard let self, !Task.isCancelled, self.token == ticket else { return }
            self.busy = false
            self.box = result.box
            self.trackedPoint = result.box.map(FocusAssistGeometry.displayPoint)
            self.loupe = result.loupe.map { UIImage(cgImage: $0) }
            self.subjectLost = result.lost
        }
    }
}
