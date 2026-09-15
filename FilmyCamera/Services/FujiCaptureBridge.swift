@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ImageIO

// All mutable bridge state is confined to CameraService's session queue. This
// is deliberately not a second owner of AVCaptureSession or its inputs.
enum FujiCaptureError: Error, LocalizedError, Equatable, Sendable {
    case unavailable(String), busy, cancelled, timedOut, invalidImage, rawUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .busy: return "The camera is finishing another operation. Try again when it is ready."
        case .cancelled: return "Shooting canceled. Completed originals remain in the development library."
        case .timedOut: return "The camera did not finish its adjustment or capture. Reopen the camera before trying again."
        case .invalidImage: return "The camera returned an unreadable image. No substitute image was saved."
        case .rawUnavailable: return "RAW capture is unavailable on this lens. Select a supported physical rear lens, or use DR100 with RAW off."
        }
    }
}

enum FujiSourceKind: String, Codable, Sendable {
    case bayerRAW, appleProRAW, processedStill, preShotPreview, temporalAverage, composite
    var isRAW: Bool { self == .bayerRAW || self == .appleProRAW }
    var title: String {
        switch self {
        case .bayerRAW: return "Bayer RAW · DNG"
        case .appleProRAW: return "Apple ProRAW · DNG"
        case .processedStill: return "Processed camera original"
        case .preShotPreview: return "Pre-shot · preview resolution"
        case .temporalAverage: return "Temporal average · preview resolution"
        case .composite: return "Merged image · bounded to 4096 px"
        }
    }
}

struct FujiCaptureMetadata: Codable, Equatable, Sendable {
    var capturedAt: Date
    var sourceKind: FujiSourceKind
    var deviceID: String
    var iso: Double? = nil
    var durationSeconds: Double? = nil
    var lensPosition: Double? = nil
    var dynamicRange: FujiDynamicRange = .dr100
    var exposureBracketEV: Double = 0
    var isoBracketEV: Double = 0
    var flashFired = false
    var temporalFrameCount: Int? = nil
    var temporalElapsedSeconds: Double? = nil
}

struct FujiSourceFrame: Sendable {
    let data: Data
    let metadata: FujiCaptureMetadata
}

struct FujiDeviceSnapshot: Sendable {
    let deviceID: String
    let iso: Double
    let durationSeconds: Double
    let lensPosition: Double
    let kelvin: Double
    let tint: Double
    let isoBounds: ClosedRange<Double>
    let durationBounds: ClosedRange<Double>
    let supportsCustomExposure: Bool
    let supportsManualFocus: Bool
    let supportsRAW: Bool
}

struct FujiCaptureLease: Sendable {
    let id: UUID
    let snapshot: FujiDeviceSnapshot
}

final class FujiCaptureBridge: @unchecked Sendable {
    private struct DeviceState {
        let exposureMode: AVCaptureDevice.ExposureMode
        let iso: Float
        let duration: CMTime
        let focusMode: AVCaptureDevice.FocusMode
        let lensPosition: Float
        let whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode
        let gains: AVCaptureDevice.WhiteBalanceGains
        let maximumFrameDuration: CMTime
        let proRAWEnabled: Bool
    }

    private final class Pending: @unchecked Sendable {
        let id = UUID()
        var continuation: CheckedContinuation<FujiSourceFrame, Error>?
        var delegate: FujiPhotoDelegate?
        init(_ continuation: CheckedContinuation<FujiSourceFrame, Error>) { self.continuation = continuation }
    }

    private let queue: DispatchQueue
    private var lease: FujiCaptureLease?
    private var settings: FujiShootingSettings?
    private var device: AVCaptureDevice?
    private var output: AVCapturePhotoOutput?
    private var originalState: DeviceState?
    private var pending: Pending?
    private var ending: CheckedContinuation<Void, Never>?
    private var isEnding = false
    private var isRestoring = false
    private var restorationCount = 0
    private var cancelled = false
    private var rawFormat: OSType?
    private var sourceKind: FujiSourceKind = .processedStill
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var recoveryRequired = false

    init(queue: DispatchQueue) { self.queue = queue }
    var isBusy: Bool { lease != nil || pending != nil || isRestoring || recoveryRequired }

    static func snapshot(device: AVCaptureDevice, output: AVCapturePhotoOutput) throws -> FujiDeviceSnapshot {
        let minimum = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        let maximum = min(
            CMTimeGetSeconds(device.activeFormat.maxExposureDuration),
            device.activeFormat.videoSupportedFrameRateRanges.map { CMTimeGetSeconds($0.maxFrameDuration) }.max() ?? 1
        )
        let isoMinimum = Double(device.activeFormat.minISO)
        let isoMaximum = Double(device.activeFormat.maxISO)
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard minimum.isFinite, maximum.isFinite, minimum > 0, maximum >= minimum,
              isoMinimum.isFinite, isoMaximum.isFinite, isoMinimum > 0, isoMaximum >= isoMinimum,
              duration.isFinite, duration > 0, device.iso.isFinite, device.iso > 0 else {
            throw FujiCaptureError.unavailable("This camera has not finished reporting its exposure bounds.")
        }
        let balance = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
        return FujiDeviceSnapshot(
            deviceID: device.uniqueID,
            iso: Double(device.iso),
            durationSeconds: duration,
            lensPosition: Double(device.lensPosition),
            kelvin: FujiLimits.finite(Double(balance.temperature), fallback: 5600, in: 2500...10000),
            tint: FujiLimits.finite(Double(balance.tint), fallback: 0, in: -150...150),
            isoBounds: isoMinimum...isoMaximum,
            durationBounds: minimum...maximum,
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            supportsManualFocus: device.isLockingFocusWithCustomLensPositionSupported && device.isFocusModeSupported(.locked),
            supportsRAW: !output.availableRawPhotoPixelFormatTypes.isEmpty || output.isAppleProRAWSupported
        )
    }

    func begin(
        device: AVCaptureDevice,
        output: AVCapturePhotoOutput,
        settings input: FujiShootingSettings,
        requestedFlash: AVCaptureDevice.FlashMode
    ) throws -> FujiCaptureLease {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !isBusy else { throw FujiCaptureError.busy }
        let settings = input.validated()
        let snapshot = try Self.snapshot(device: device, output: output)
        if (settings.drive.needsManualExposure || settings.dynamicRange != .dr100) && !snapshot.supportsCustomExposure {
            throw FujiCaptureError.unavailable("This drive mode needs manual exposure. Select a physical lens in Manual controls.")
        }
        if settings.drive.needsManualFocus && !snapshot.supportsManualFocus {
            throw FujiCaptureError.unavailable("Focus bracketing needs a lens with a controllable focus motor. Select a supported physical rear lens.")
        }
        if settings.needsRAW && !snapshot.supportsRAW { throw FujiCaptureError.rawUnavailable }
        let state = DeviceState(
            exposureMode: device.exposureMode, iso: device.iso, duration: device.exposureDuration,
            focusMode: device.focusMode, lensPosition: device.lensPosition,
            whiteBalanceMode: device.whiteBalanceMode, gains: device.deviceWhiteBalanceGains,
            maximumFrameDuration: device.activeVideoMaxFrameDuration, proRAWEnabled: output.isAppleProRAWEnabled
        )
        var selectedRAW: OSType?
        if settings.needsRAW {
            selectedRAW = output.availableRawPhotoPixelFormatTypes.first(where: AVCapturePhotoOutput.isBayerRAWPixelFormat)
            if selectedRAW == nil, output.isAppleProRAWSupported {
                output.isAppleProRAWEnabled = true
                selectedRAW = output.availableRawPhotoPixelFormatTypes.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat)
            }
            guard selectedRAW != nil else {
                if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = state.proRAWEnabled }
                throw FujiCaptureError.rawUnavailable
            }
        }
        do {
            try device.lockForConfiguration()
            // Meter exactly once for the sequence. Changes to ISO or focus in
            // individual steps must not cause the other automatic loops to chase.
            if device.isExposureModeSupported(.locked), device.exposureMode != .custom { device.exposureMode = .locked }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()
        } catch {
            if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = state.proRAWEnabled }
            throw FujiCaptureError.unavailable("The camera could not lock its settings. Try again.")
        }
        let lease = FujiCaptureLease(id: UUID(), snapshot: snapshot)
        self.lease = lease
        self.device = device
        self.output = output
        self.settings = settings
        self.originalState = state
        rawFormat = selectedRAW
        if let selectedRAW {
            sourceKind = AVCapturePhotoOutput.isAppleProRAWPixelFormat(selectedRAW) ? .appleProRAW : .bayerRAW
        } else {
            sourceKind = .processedStill
        }
        // Flash is only meaningful for a single, non-DR, non-manual still.
        let permitsFlash = settings.drive == .single && settings.dynamicRange == .dr100
            && !settings.needsRAW && state.exposureMode != .custom && settings.activeAutoISO == nil
        flashMode = permitsFlash && device.isFlashAvailable
            && output.supportedFlashModes.contains(requestedFlash) ? requestedFlash : .off
        cancelled = false
        isEnding = false
        return lease
    }

    func capture(leaseID: UUID, step: FujiCaptureStep, continuation: CheckedContinuation<FujiSourceFrame, Error>) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let lease, lease.id == leaseID, !cancelled, !isEnding,
              let device, output != nil else {
            continuation.resume(throwing: FujiCaptureError.cancelled)
            return
        }
        guard pending == nil else { continuation.resume(throwing: FujiCaptureError.busy); return }
        let request = Pending(continuation)
        pending = request
        // A timed-out continuation must not leave the UI spinning indefinitely.
        // The controller stops the session on timeout, which drains this lease.
        queue.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.pending?.id == request.id else { return }
            self.recoveryRequired = true
            self.completePending(.failure(.timedOut))
        }
        let requestedDuration = lease.snapshot.durationSeconds * pow(2, step.exposureEV - step.dynamicRange.stops)
        let requestedISO = lease.snapshot.iso * pow(2, step.isoEV)
        let requiresOverride = step.exposureEV != 0 || step.isoEV != 0 || step.dynamicRange != .dr100
            || settings?.drive.needsManualExposure == true || originalState?.exposureMode == .custom
        guard requestedDuration.isFinite, requestedISO.isFinite else {
            failBeforeCapture(.unavailable("The requested exposure is not finite."))
            return
        }
        if requiresOverride {
            // Reject impossible brackets instead of silently producing duplicate
            // exposures and labeling them DR200/400 or +/-EV.
            let durationBounds = lease.snapshot.durationBounds
            let isoBounds = lease.snapshot.isoBounds
            guard device.isExposureModeSupported(.custom),
                  requestedDuration >= durationBounds.lowerBound * 0.999,
                  requestedDuration <= durationBounds.upperBound * 1.001,
                  requestedISO >= isoBounds.lowerBound * 0.999,
                  requestedISO <= isoBounds.upperBound * 1.001 else {
                failBeforeCapture(.unavailable("This bracket exceeds the lens's ISO or shutter range. Reduce BKT spacing or change the base exposure."))
                return
            }
            do {
                try device.lockForConfiguration()
                let duration = CMTime(seconds: min(max(requestedDuration, durationBounds.lowerBound), durationBounds.upperBound), preferredTimescale: 1_000_000_000)
                if CMTimeCompare(duration, device.activeVideoMaxFrameDuration) > 0 { device.activeVideoMaxFrameDuration = duration }
                device.setExposureModeCustom(duration: duration, iso: Float(min(max(requestedISO, isoBounds.lowerBound), isoBounds.upperBound))) { [weak self] _ in
                    self?.queue.async { [weak self] in
                        self?.applyFocus(requestID: request.id, step: step, expectedDuration: requestedDuration, expectedISO: requestedISO)
                    }
                }
                device.unlockForConfiguration()
            } catch {
                failBeforeCapture(.unavailable("The exposure could not be applied."))
            }
        } else {
            applyFocus(requestID: request.id, step: step, expectedDuration: nil, expectedISO: nil)
        }
    }

    private func applyFocus(requestID: UUID, step: FujiCaptureStep, expectedDuration: Double?, expectedISO: Double?) {
        guard pending?.id == requestID, !cancelled, let device else { return }
        if let position = step.lensPosition {
            guard position.isFinite, (0...1).contains(position), device.isLockingFocusWithCustomLensPositionSupported else {
                failBeforeCapture(.unavailable("That focus position is not supported."))
                return
            }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: Float(position)) { [weak self] _ in
                    self?.queue.async { [weak self] in
                        self?.captureAfterSettling(requestID: requestID, step: step, expectedDuration: expectedDuration, expectedISO: expectedISO)
                    }
                }
                device.unlockForConfiguration()
            } catch {
                failBeforeCapture(.unavailable("The focus motor could not be adjusted."))
            }
        } else {
            captureAfterSettling(requestID: requestID, step: step, expectedDuration: expectedDuration, expectedISO: expectedISO)
        }
    }

    private func captureAfterSettling(requestID: UUID, step: FujiCaptureStep, expectedDuration: Double?, expectedISO: Double?) {
        guard pending?.id == requestID, !cancelled, let device else { return }
        // The callbacks above are the actual adjustment barriers. This extra
        // frame interval allows the still output to observe that sensor state.
        let delay = min(max(CMTimeGetSeconds(device.activeVideoMaxFrameDuration), 0.05), 1)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.pending?.id == requestID, !self.cancelled,
                  let device = self.device, let output = self.output else { return }
            let photoSettings: AVCapturePhotoSettings
            if let rawFormat = self.rawFormat {
                guard output.availableRawPhotoPixelFormatTypes.contains(rawFormat) else {
                    self.failBeforeCapture(.rawUnavailable)
                    return
                }
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            } else {
                photoSettings = AVCapturePhotoSettings()
            }
            photoSettings.flashMode = self.flashMode
            // Speed prioritization is the conservative manual-sensor path;
            // software sequence rate still depends on the hardware and RAW format.
            photoSettings.photoQualityPrioritization = .speed
            if output.maxPhotoDimensions.width > 0, output.maxPhotoDimensions.height > 0 {
                photoSettings.maxPhotoDimensions = output.maxPhotoDimensions
            }
            let metadata = FujiCaptureMetadata(
                capturedAt: Date(), sourceKind: self.sourceKind, deviceID: device.uniqueID,
                iso: nil, durationSeconds: nil, lensPosition: Double(device.lensPosition),
                dynamicRange: step.dynamicRange, exposureBracketEV: step.exposureEV, isoBracketEV: step.isoEV
            )
            let delegate = FujiPhotoDelegate(
                queue: self.queue, metadata: metadata,
                expectedDuration: expectedDuration, expectedISO: expectedISO
            ) { [weak self] result in
                guard let self, self.pending?.id == requestID else { return }
                self.completePending(result)
                self.pending = nil
                if self.isEnding { self.restoreAndFinish() }
            }
            self.pending?.delegate = delegate
            output.capturePhoto(with: photoSettings, delegate: delegate)
        }
    }

    private func completePending(_ result: Result<FujiSourceFrame, FujiCaptureError>) {
        let continuation = pending?.continuation
        pending?.continuation = nil
        switch result {
        case .success(let frame): continuation?.resume(returning: frame)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private func failBeforeCapture(_ error: FujiCaptureError) {
        completePending(.failure(error))
        pending = nil
        if isEnding { restoreAndFinish() }
    }

    func abort(leaseID: UUID) {
        guard lease?.id == leaseID else { return }
        cancelled = true
        completePending(.failure(.cancelled))
        // Retain an in-flight photo delegate until didFinishCaptureFor. A
        // cancellation must never admit a second photo while the first drains.
        if pending?.delegate == nil { pending = nil }
        if isEnding, pending == nil { restoreAndFinish() }
    }

    func end(leaseID: UUID, continuation: CheckedContinuation<Void, Never>) {
        guard lease?.id == leaseID else { continuation.resume(); return }
        guard ending == nil else { continuation.resume(); return }
        ending = continuation
        isEnding = true
        if pending == nil { restoreAndFinish() }
    }

    private func restoreAndFinish() {
        guard !isRestoring else { return }
        guard let device, let state = originalState, let leaseID = lease?.id else { finishLease(); return }
        isRestoring = true
        restorationCount = 0
        do {
            try device.lockForConfiguration()
            if state.exposureMode == .custom, device.isExposureModeSupported(.custom) {
                restorationCount += 1
                device.setExposureModeCustom(duration: state.duration, iso: state.iso) { [weak self] _ in
                    self?.queue.async { [weak self] in self?.restoredOne(leaseID: leaseID) }
                }
            } else if device.isExposureModeSupported(state.exposureMode) {
                device.exposureMode = state.exposureMode
            }
            if state.focusMode == .locked, device.isLockingFocusWithCustomLensPositionSupported {
                restorationCount += 1
                device.setFocusModeLocked(lensPosition: state.lensPosition) { [weak self] _ in
                    self?.queue.async { [weak self] in self?.restoredOne(leaseID: leaseID) }
                }
            } else if device.isFocusModeSupported(state.focusMode) {
                device.focusMode = state.focusMode
            }
            if state.whiteBalanceMode == .locked, device.isWhiteBalanceModeSupported(.locked) {
                restorationCount += 1
                device.setWhiteBalanceModeLocked(with: state.gains) { [weak self] _ in
                    self?.queue.async { [weak self] in self?.restoredOne(leaseID: leaseID) }
                }
            } else if device.isWhiteBalanceModeSupported(state.whiteBalanceMode) {
                device.whiteBalanceMode = state.whiteBalanceMode
            }
            device.unlockForConfiguration()
        } catch {
            recoveryRequired = true
            finishLease()
            return
        }
        if restorationCount == 0 { finishLease() }
        queue.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.lease?.id == leaseID, self.isRestoring else { return }
            self.recoveryRequired = true
            self.finishLease()
        }
    }

    private func restoredOne(leaseID: UUID) {
        guard lease?.id == leaseID, isRestoring else { return }
        restorationCount -= 1
        if restorationCount == 0 { finishLease() }
    }

    private func finishLease() {
        if let state = originalState {
            if let device {
                do {
                    try device.lockForConfiguration()
                    device.activeVideoMaxFrameDuration = state.maximumFrameDuration
                    device.unlockForConfiguration()
                } catch { recoveryRequired = true }
            }
            if let output, output.isAppleProRAWSupported { output.isAppleProRAWEnabled = state.proRAWEnabled }
        }
        let continuation = ending
        ending = nil
        lease = nil
        settings = nil
        device = nil
        output = nil
        originalState = nil
        pending = nil
        isRestoring = false
        isEnding = false
        rawFormat = nil
        continuation?.resume()
    }

    /// Called only when CameraService stops or rebuilds its session graph.
    /// Generation/ID checks make all late AVFoundation callbacks harmless.
    func sessionStopped() {
        completePending(.failure(.cancelled))
        pending = nil
        if let device, let state = originalState {
            do {
                try device.lockForConfiguration()
                if state.exposureMode == .custom, device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: state.duration, iso: state.iso, completionHandler: nil)
                } else if device.isExposureModeSupported(state.exposureMode) {
                    device.exposureMode = state.exposureMode
                }
                if device.isFocusModeSupported(state.focusMode) { device.focusMode = state.focusMode }
                if device.isWhiteBalanceModeSupported(state.whiteBalanceMode) { device.whiteBalanceMode = state.whiteBalanceMode }
                device.unlockForConfiguration()
            } catch { /* The stopped session is the recovery boundary. */ }
        }
        finishLease()
        recoveryRequired = false
    }
}

private final class FujiPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let queue: DispatchQueue
    private var metadata: FujiCaptureMetadata
    private let expectedDuration: Double?
    private let expectedISO: Double?
    private var data: Data?
    private var failure: FujiCaptureError?
    private var completed = false
    private let completion: @Sendable (Result<FujiSourceFrame, FujiCaptureError>) -> Void

    init(queue: DispatchQueue, metadata: FujiCaptureMetadata, expectedDuration: Double?, expectedISO: Double?,
         completion: @escaping @Sendable (Result<FujiSourceFrame, FujiCaptureError>) -> Void) {
        self.queue = queue
        self.metadata = metadata
        self.expectedDuration = expectedDuration
        self.expectedISO = expectedISO
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let bytes = error == nil ? photo.fileDataRepresentation() : nil
        let isRAW = photo.isRawPhoto
        let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let exposure = (exif?[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        let flash = photo.resolvedSettings.isFlashEnabled
        queue.async { [weak self] in
            guard let self, !self.completed else { return }
            guard let bytes, !bytes.isEmpty, bytes.count <= FujiLimits.maximumSourceBytes,
                  isRAW == self.metadata.sourceKind.isRAW else { self.failure = .invalidImage; return }
            self.data = bytes
            self.metadata.iso = iso
            self.metadata.durationSeconds = exposure
            self.metadata.flashFired = flash
            // Verify the camera honored actual bracket settings. Do not label
            // a platform-fused or clamped exposure as real DR/ISO/AE bracketing.
            if let expected = self.expectedDuration {
                guard let exposure, exposure > 0, abs(log2(exposure / expected)) < 0.2 else {
                    self.failure = .unavailable("This camera did not report the requested shutter exposure. The bracket was not exported as a verified DR/AE capture.")
                    return
                }
            }
            if let expected = self.expectedISO {
                guard let iso, iso > 0, abs(log2(iso / expected)) < 0.2 else {
                    self.failure = .unavailable("This camera did not report the requested ISO. The bracket was not exported as a verified sensor capture.")
                    return
                }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let terminalError = error != nil
        queue.async { [weak self] in
            guard let self, !self.completed else { return }
            self.completed = true
            if let failure = self.failure { self.completion(.failure(failure)) }
            else if terminalError { self.completion(.failure(.invalidImage)) }
            else if let data = self.data { self.completion(.success(FujiSourceFrame(data: data, metadata: self.metadata))) }
            else { self.completion(.failure(.invalidImage)) }
            self.data = nil
        }
    }
}
