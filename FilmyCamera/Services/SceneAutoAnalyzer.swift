import CoreGraphics
import CoreImage
import Foundation
import QuartzCore
import Vision

/// A bounded, best-effort observer. At most one thumbnail/face request is in
/// flight; incoming frames are discarded, never queued behind the viewfinder.
/// A dedicated serial queue also avoids blocking Swift's cooperative executor
/// with synchronous Vision work. No image, face, or statistic leaves the device.
final class SceneAutoAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var acceptedAt: Double = -.infinity
    private let queue = DispatchQueue(label: "com.dheeraj.filmycamera.scene-auto", qos: .utility)
    // The following state belongs only to queue.
    private var generation: UInt64?
    private var previousLuma: [Double]?
    private var previousSize: CGSize = .zero
    private var lastFaceAt: Double = -.infinity
    private var face: SceneAutoPoint?
    private var faceConfidence: Double = 0
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private final class ImageBox: @unchecked Sendable {
        let image: CIImage
        init(_ image: CIImage) { self.image = image }
    }

    func submit(
        _ image: CIImage,
        generation: UInt64,
        completion: @escaping @Sendable (SceneAutoObservation, UInt64) -> Void
    ) {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .critical else { return }
        let interval = thermal == .serious || ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.2 : SceneAutoPolicy.sampleInterval
        lock.lock()
        guard !busy, now - acceptedAt >= interval else { lock.unlock(); return }
        busy = true
        acceptedAt = now
        lock.unlock()
        let box = ImageBox(image)
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock(); self.busy = false; self.lock.unlock()
            }
            autoreleasepool {
                guard let observation = self.analyze(box.image, at: now, generation: generation, detectFaces: thermal != .serious) else { return }
                completion(observation, generation)
            }
        }
    }

    private func analyze(_ image: CIImage, at timestamp: Double, generation: UInt64, detectFaces: Bool) -> SceneAutoObservation? {
        let extent = image.extent
        guard !extent.isNull, !extent.isInfinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        let scale = CGFloat(SceneAutoStatistics.maximumDimension) / max(extent.width, extent.height)
        let width = max(1, Int((extent.width * scale).rounded(.down)))
        let height = max(1, Int((extent.height * scale).rounded(.down)))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let thumbnail = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: bounds)
        if self.generation != generation || previousSize != bounds.size {
            self.generation = generation
            previousLuma = nil
            previousSize = bounds.size
            face = nil
            faceConfidence = 0
            lastFaceAt = -.infinity
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        context.render(thumbnail, toBitmap: &rgba, rowBytes: width * 4, bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        guard let statistics = SceneAutoStatistics.measure(rgba: rgba, width: width, height: height, previousLuma: previousLuma) else { return nil }
        previousLuma = statistics.luma
        if detectFaces, timestamp - lastFaceAt >= 1.2 {
            lastFaceAt = timestamp
            // Never retain a face across a failed request or after it leaves.
            face = nil
            faceConfidence = 0
            let request = VNDetectFaceRectanglesRequest()
            request.preferBackgroundProcessing = true
            let handler = VNImageRequestHandler(ciImage: thumbnail, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                let largest = request.results?.filter { $0.confidence >= 0.75 }
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                if let largest {
                    face = SceneAutoPoint(x: Double(largest.boundingBox.midX), y: Double(1 - largest.boundingBox.midY))
                    faceConfidence = Double(largest.confidence)
                }
            } catch { /* Metering can continue without face detection. */ }
        }
        if timestamp - lastFaceAt > 1.6 { face = nil; faceConfidence = 0 }
        return SceneAutoObservation(
            timestamp: timestamp, median: statistics.median, center: statistics.center,
            highlights: statistics.highlights, shadows: statistics.shadows, motion: statistics.motion,
            neutralFraction: statistics.neutralFraction, redOverGreen: statistics.redOverGreen, blueOverGreen: statistics.blueOverGreen,
            face: face, faceConfidence: faceConfidence
        )
    }
}

extension SceneAutoDevelopment {
    /// The preview and shutter call this exact function. The original recipe,
    /// its stock identity, grain, palette, and persistent overrides stay intact.
    func applying(to recipe: FilmRecipe) -> FilmRecipe {
        guard self != SceneAutoDevelopment() else { return recipe }
        var adjusted = recipe
        adjusted.tone.highlight = min(max(recipe.tone.highlight + highlights, -1), 1)
        adjusted.tone.shadow = min(max(recipe.tone.shadow + shadows, -1), 1)
        adjusted.noiseReduction = min(max(recipe.noiseReduction + noiseReduction, 0), 1)
        adjusted.sharpness = min(max(recipe.sharpness + sharpness, -1), 1)
        return adjusted
    }
}
