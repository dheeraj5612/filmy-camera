@preconcurrency import CoreImage
import Foundation
import UIKit

struct FujiPreviewSample: @unchecked Sendable {
    let live: UIImage
    let developed: UIImage
    let contrast: UIImage
    let timestamp: TimeInterval
}

/// Keeps at most one camera buffer in flight. The ring owns materialized
/// CGImages, never CVPixelBuffers from AVFoundation's reusable buffer pool.
final class FujiPreviewWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.filmycamera.fuji-preview", qos: .userInitiated)
    private let gate = NSLock()
    private var inFlight = false
    private var generation: UInt64 = 0
    private var lastAccepted: TimeInterval = 0
    private var ring = FujiTimedBuffer<CGImage>(capacity: FujiLimits.maximumPreviewFrames, maximumAge: 2)
    private var accumulated: CIImage?
    private var accumulationCount = 0
    private var accumulationStart: TimeInterval?
    private var accumulationLast: TimeInterval?
    private var isAccumulating = false
    private var accumulationFailure: Error?

    func submit(_ image: CIImage, settings: FujiShootingSettings, recipe: FilmRecipe,
                completion: @escaping @MainActor @Sendable (FujiPreviewSample) -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        gate.lock()
        guard !inFlight, now - lastAccepted >= 0.125 else { gate.unlock(); return }
        inFlight = true
        lastAccepted = now
        let token = generation
        gate.unlock()
        queue.async { [self] in
            defer { gate.lock(); inFlight = false; gate.unlock() }
            autoreleasepool {
                gate.lock()
                let current = token == generation
                gate.unlock()
                guard current else { return }
                let small = FujiDevelopmentPipeline.bounded(image, longEdge: FujiLimits.previewLongEdge)
                guard let copied = FilmRenderer.outputCGImage(small) else { return }
                if settings.drive == .preShot { ring.append(copied, at: now) }
                let owned = CIImage(cgImage: copied)
                if isAccumulating {
                    do {
                        if let previous = accumulated {
                            accumulated = try FujiDevelopmentPipeline.blend(previous, owned, count: accumulationCount, mode: .average)
                        } else {
                            accumulated = try FujiDevelopmentPipeline.materializeLinear(owned)
                            accumulationStart = now
                        }
                        accumulationCount += 1
                        accumulationLast = now
                    } catch { accumulationFailure = error; isAccumulating = false }
                }
                // Focus and hybrid previews are bounded and optional. Ordinary
                // pre-shot collection does not pay for three extra film renders.
                guard settings.viewfinder == .hybrid || settings.focusAssist != .off else { return }
                let cropped = FujiDevelopmentPipeline.centerCrop(owned, factor: settings.cropFactor)
                let live = FujiDevelopmentPipeline.bounded(cropped, longEdge: 480)
                let detail = FujiDevelopmentPipeline.bounded(FujiDevelopmentPipeline.centerCrop(cropped, factor: 3), longEdge: 480)
                let contrast = detail.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3])
                    .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 3])
                guard let liveCG = FilmRenderer.outputCGImage(detail),
                      let contrastCG = FilmRenderer.outputCGImage(contrast),
                      let developedCG = FilmRenderer.outputCGImage(FilmRenderer.render(live, recipe: recipe)) else { return }
                let sample = FujiPreviewSample(live: UIImage(cgImage: liveCG), developed: UIImage(cgImage: developedCG),
                                               contrast: UIImage(cgImage: contrastCG), timestamp: now)
                Task { @MainActor in completion(sample) }
            }
        }
    }

    func clear() {
        gate.lock(); generation &+= 1; gate.unlock()
        queue.async { [self] in
            ring.removeAll()
            accumulated = nil
            accumulationCount = 0
            accumulationStart = nil
            accumulationLast = nil
            isAccumulating = false
            accumulationFailure = nil
        }
    }

    func beginAverage() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                accumulated = nil
                accumulationCount = 0
                accumulationStart = nil
                accumulationLast = nil
                accumulationFailure = nil
                isAccumulating = true
                continuation.resume()
            }
        }
    }

    func finishAverage(deviceID: String) async throws -> FujiSourceFrame {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                defer { accumulated = nil; isAccumulating = false }
                do {
                    if let accumulationFailure { throw accumulationFailure }
                    guard let accumulated, accumulationCount >= 2, let start = accumulationStart, let last = accumulationLast else {
                        throw FujiCaptureError.unavailable("Not enough live frames were received for computational ND.")
                    }
                    let metadata = FujiCaptureMetadata(capturedAt: Date(), sourceKind: .temporalAverage, deviceID: deviceID,
                        temporalFrameCount: accumulationCount, temporalElapsedSeconds: last - start)
                    continuation.resume(returning: try FujiDevelopmentPipeline.encodeSource(accumulated, metadata: metadata))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func takePreShot(seconds: Double, count: Int, deviceID: String) async throws -> [FujiSourceFrame] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let now = ProcessInfo.processInfo.systemUptime
                    let samples = ring.takeEntries(at: now).filter { now - $0.time <= seconds }.suffix(count)
                    let frames = try samples.map { sample in
                        let metadata = FujiCaptureMetadata(capturedAt: Date().addingTimeInterval(sample.time - now),
                                                           sourceKind: .preShotPreview, deviceID: deviceID)
                        return try FujiDevelopmentPipeline.encodeSource(CIImage(cgImage: sample.value), metadata: metadata)
                    }
                    continuation.resume(returning: frames)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
