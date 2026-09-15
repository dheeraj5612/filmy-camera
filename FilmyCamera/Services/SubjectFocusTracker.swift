import CoreImage
import Foundation
import Vision

/// Queue-confined, opt-in subject tracking. The preview buffers are already
/// rotated/mirrored, so Vision always sees .up and returns bottom-left boxes.
/// Losing a subject freezes the target instead of jumping to a different face.
final class SubjectFocusTracker {
    enum State: String, Sendable { case idle, acquiring, tracking, lost }
    struct Update: Sendable {
        let state: State
        let rectangle: CGRect?
    }

    private var sequence = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var seedPoint: CGPoint?
    private var lastUpdateTime: TimeInterval = 0
    private var lost = false

    func select(topLeftPoint: CGPoint) {
        seedPoint = CGPoint(x: min(max(topLeftPoint.x, 0), 1), y: 1 - min(max(topLeftPoint.y, 0), 1))
        request = nil
        sequence = VNSequenceRequestHandler()
        lost = false
        lastUpdateTime = 0
    }

    func reset() {
        request = nil
        seedPoint = nil
        sequence = VNSequenceRequestHandler()
        lost = false
        lastUpdateTime = 0
    }

    func process(_ image: CIImage, at time: TimeInterval) -> Update? {
        guard time - lastUpdateTime >= 0.12, !lost else { return nil }
        lastUpdateTime = time
        do {
            if let point = seedPoint {
                let faces = VNDetectFaceRectanglesRequest()
                let saliency = VNGenerateObjectnessBasedSaliencyImageRequest()
                let handler = VNImageRequestHandler(ciImage: image, options: [:])
                try handler.perform([faces, saliency])
                let rectangles = (faces.results ?? []).map(\.boundingBox)
                    + (saliency.results?.first?.salientObjects ?? []).map(\.boundingBox)
                let rectangle = Self.seedRectangle(near: point, candidates: rectangles)
                request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: rectangle))
                request?.trackingLevel = .accurate
                seedPoint = nil
            }
            guard let request else { return nil }
            try sequence.perform([request], on: image)
            guard let observation = request.results?.first,
                  Self.isUsable(rectangle: observation.boundingBox, confidence: observation.confidence) else {
                lost = true
                self.request = nil
                return Update(state: .lost, rectangle: nil)
            }
            request.inputObservation = observation
            return Update(state: .tracking, rectangle: observation.boundingBox)
        } catch {
            lost = true
            request = nil
            return Update(state: .lost, rectangle: nil)
        }
    }

    static func isUsable(rectangle: CGRect, confidence: Float) -> Bool {
        confidence.isFinite && confidence >= 0.45 && !rectangle.isNull && !rectangle.isInfinite
            && rectangle.width >= 0.02 && rectangle.height >= 0.02
            && rectangle.minX >= 0 && rectangle.minY >= 0 && rectangle.maxX <= 1 && rectangle.maxY <= 1
    }

    static func seedRectangle(near point: CGPoint, candidates: [CGRect]) -> CGRect {
        // Prefer the smallest detection containing the selected pixel. Do not
        // silently select a more prominent but unrelated person elsewhere.
        if let selected = candidates.filter({ $0.contains(point) && isUsable(rectangle: $0, confidence: 1) })
            .min(by: { $0.width * $0.height < $1.width * $1.height }) { return selected }
        return CGRect(x: min(max(point.x - 0.08, 0), 0.84), y: min(max(point.y - 0.08, 0), 0.84), width: 0.16, height: 0.16)
    }
}
