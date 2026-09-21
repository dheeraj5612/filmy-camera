import CoreImage
import Foundation
import UIKit

struct FujiPreShotFrame: @unchecked Sendable {
    let image: CGImage
    let capturedAt: Date
    let uptime: TimeInterval
    var byteCount: Int { image.bytesPerRow * image.height }
}

/// Pure bounded, timestamped storage. Images are owned copies, never camera
/// CVPixelBuffers, and snapshots cannot contain a frame after shutter release.
struct FujiPreShotRing {
    static let maximumBytes = 32 * 1024 * 1024
    private(set) var frames: [FujiPreShotFrame] = []
    private(set) var byteCount = 0
    mutating func append(_ frame: FujiPreShotFrame, seconds: Double) {
        guard seconds > 0, frame.byteCount <= Self.maximumBytes else { clear(); return }
        if let last = frames.last, frame.uptime <= last.uptime { return }
        frames.append(frame); byteCount += frame.byteCount
        while let first = frames.first,
              frame.uptime - first.uptime > seconds || byteCount > Self.maximumBytes || frames.count > 16 {
            byteCount -= frames.removeFirst().byteCount
        }
    }
    func snapshot(at uptime: TimeInterval, seconds: Double) -> [FujiPreShotFrame] {
        frames.filter { $0.uptime <= uptime && uptime - $0.uptime <= seconds }
    }
    mutating func clear() { frames.removeAll(keepingCapacity: false); byteCount = 0 }
}

struct FujiSamplerResult: @unchecked Sendable {
    var inset: CGImage?
    var focus: CGImage?
    var contrast: Double = 0
    var bufferedCount = 0
}

/// A single-in-flight preview side channel. The main preview keeps its sole
/// display-layer ownership. Expensive focus/inset work is limited to 5 Hz.
final class FujiFrameSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "filmy.fuji.preview", qos: .utility)
    private let lock = NSLock()
    private var inFlight = false
    private var generation: UInt64 = 0
    private var ring = FujiPreShotRing()
    private var lastUptime: TimeInterval = 0
    private var peakContrast: Double = 0.001
    private var settings = FujiShootingSettings()
    private var recipe: FilmRecipe?
    private var viewport = CGSize.zero
    private var active = false
    private var onResult: (@Sendable (FujiSamplerResult) -> Void)?
    private static let microprism = CIKernel(source: """
        kernel vec4 fujiMicroprism(sampler image, float displacement) {
            vec2 p = destCoord();
            float phase = mod(floor(p.x / 9.0) + floor(p.y / 9.0), 2.0) * 2.0 - 1.0;
            vec2 shifted = p + vec2(phase * displacement, -phase * displacement * 0.5);
            return sample(image, samplerTransform(image, shifted));
        }
        """)

    func configure(settings: FujiShootingSettings, recipe: FilmRecipe, viewport: CGSize, active: Bool,
                   onResult: @escaping @Sendable (FujiSamplerResult) -> Void) {
        lock.lock()
        self.settings = settings; self.recipe = recipe; self.viewport = viewport
        self.active = active; self.onResult = onResult
        generation &+= 1
        lock.unlock()
        queue.async { [weak self] in self?.ring.clear(); self?.peakContrast = 0.001; self?.lastUptime = 0 }
    }

    func reset() {
        lock.lock(); generation &+= 1; lock.unlock()
        queue.async { [weak self] in self?.ring.clear(); self?.lastUptime = 0; self?.peakContrast = 0.001 }
    }

    func submit(_ image: CIImage, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime, capturedAt: Date = Date()) {
        lock.lock()
        let settings = settings
        guard active, !inFlight, let recipe,
              settings.preShotSeconds > 0 || settings.viewfinder == .hybrid || settings.focusAssist != .off else {
            lock.unlock(); return
        }
        inFlight = true
        let generation = generation
        let viewport = viewport
        let callback = onResult
        lock.unlock()
        let box = FujiImage(image: image)
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.inFlight = false; self.lock.unlock() }
            self.lock.lock(); let valid = generation == self.generation; self.lock.unlock()
            guard valid, uptime - self.lastUptime >= (settings.preShotSeconds > 0 ? 0.1 : 0.2) else { return }
            self.lastUptime = uptime
            autoreleasepool {
                do {
                    // Rendering immediately releases the camera buffer after this
                    // block. The ring's 768 px images are independent allocations.
                    let copy = try FujiImageProcessor.thumbnail(box.image, edge: 768).image
                    if settings.preShotSeconds > 0 {
                        self.ring.append(FujiPreShotFrame(image: copy, capturedAt: capturedAt, uptime: uptime), seconds: settings.preShotSeconds)
                    }
                    var result = FujiSamplerResult(bufferedCount: self.ring.frames.count)
                    let input = CIImage(cgImage: copy)
                    let cropped = FujiImageProcessor.crop(input, factor: settings.digitalCrop, viewport: viewport)
                    if settings.viewfinder == .hybrid {
                        let small = FujiImageProcessor.bound(cropped, maximumEdge: 300)
                        let rendered = FilmRenderer.render(small, recipe: recipe, quality: .preview)
                        result.inset = try FujiImageProcessor.thumbnail(rendered, edge: 300).image
                    }
                    if settings.focusAssist != .off {
                        let extent = cropped.extent
                        let edge = min(extent.width, extent.height) * 0.28
                        let patch = CGRect(x: extent.midX - edge / 2, y: extent.midY - edge / 2, width: edge, height: edge)
                        let central = cropped.cropped(to: patch).transformed(by: CGAffineTransform(translationX: -patch.minX, y: -patch.minY))
                        let mono = central.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                        let energy = FujiImageProcessor.sharpness(mono).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: mono.extent)])
                        var pixel = [Float](repeating: 0, count: 4)
                        FujiImageProcessor.context.render(energy, toBitmap: &pixel, rowBytes: MemoryLayout<Float>.size * 4,
                                                          bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
                                                          colorSpace: FujiImageProcessor.linearSpace)
                        let contrast = max(Double(pixel[0]), 0)
                        self.peakContrast = max(self.peakContrast, contrast)
                        let relative = min(contrast / self.peakContrast, 1)
                        result.contrast = relative
                        // This visualizes relative local contrast, not phase or
                        // subject distance. The UI labels that distinction.
                        let displacement = CGFloat((1 - relative) * 9)
                        let aided: CIImage
                        if settings.focusAssist == .splitImage {
                            let upper = CGRect(x: 0, y: edge / 2, width: edge, height: edge / 2)
                            let lower = CGRect(x: 0, y: 0, width: edge, height: edge / 2)
                            let top = mono.clampedToExtent().transformed(by: CGAffineTransform(translationX: displacement, y: 0)).cropped(to: upper)
                            let bottom = mono.clampedToExtent().transformed(by: CGAffineTransform(translationX: -displacement, y: 0)).cropped(to: lower)
                            aided = top.composited(over: bottom)
                        } else {
                            guard let result = Self.microprism?.apply(extent: mono.extent,
                                    roiCallback: { _, rect in rect.insetBy(dx: -12, dy: -12) },
                                    arguments: [mono.clampedToExtent(), Double(displacement)]) else { throw FujiShootingError.processingFailed }
                            aided = result
                        }
                        result.focus = try FujiImageProcessor.thumbnail(aided, edge: 180).image
                    }
                    self.lock.lock(); let stillValid = generation == self.generation; self.lock.unlock()
                    if stillValid { callback?(result) }
                } catch {
                    // Preview assists are optional; never block the main preview.
                    // A clear result removes stale aids instead of freezing them.
                    callback?(FujiSamplerResult())
                }
            }
        }
    }

    func snapshot(at uptime: TimeInterval, seconds: Double) async -> [FujiPreShotFrame] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in continuation.resume(returning: self?.ring.snapshot(at: uptime, seconds: seconds) ?? []) }
        }
    }

    static func jpeg(_ frame: FujiPreShotFrame) throws -> Data {
        guard let data = UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.94) else { throw FujiShootingError.processingFailed }
        return data
    }
}
