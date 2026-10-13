@preconcurrency import AVFoundation
import Foundation
import ImageIO

struct FujiCapturedFrame: Sendable {
    let processedData: Data
    let rawData: Data?
    let capturedAt: Date
    let exposure: FujiExposure
    let lensPosition: Double
}

/// Every native completion, timeout, cancellation and interruption races through
/// this gate. A checked continuation is resumed exactly once, on any queue.
final class FujiCompletionGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Value, Error>) -> Void)?
    init(_ completion: @escaping @Sendable (Result<Value, Error>) -> Void) { self.completion = completion }
    @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(result)
        return callback != nil
    }
}

final class FujiHardwareLease: @unchecked Sendable {
    let snapshot: FujiSensorSnapshot
    let device: AVCaptureDevice
    let exposureMode: AVCaptureDevice.ExposureMode
    let focusMode: AVCaptureDevice.FocusMode
    let whiteBalanceMode: AVCaptureDevice.WhiteBalanceMode
    let whiteBalanceGains: AVCaptureDevice.WhiteBalanceGains
    let minFrameDuration: CMTime
    let maxFrameDuration: CMTime
    let subjectAreaMonitoring: Bool
    var operationID: UUID?
    var cancelOperation: (@Sendable () -> Void)?
    var delegate: FujiPhotoDelegate?
    var restoring = false
    var restoreWaiters: [@Sendable (Result<Void, Error>) -> Void] = []

    init(snapshot: FujiSensorSnapshot, device: AVCaptureDevice) {
        self.snapshot = snapshot
        self.device = device
        exposureMode = device.exposureMode
        focusMode = device.focusMode
        whiteBalanceMode = device.whiteBalanceMode
        whiteBalanceGains = device.deviceWhiteBalanceGains
        minFrameDuration = device.activeVideoMinFrameDuration
        maxFrameDuration = device.activeVideoMaxFrameDuration
        subjectAreaMonitoring = device.isSubjectAreaChangeMonitoringEnabled
    }
}

/// RAW + processed captures deliver TWO processing callbacks and one final
/// callback. Neither processing callback is allowed to finish the transaction.
final class FujiPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var processed: Data?
    private var raw: Data?
    private var failure: Error?
    private let requiresRAW: Bool
    private let capturedAt: Date
    private var exposure: FujiExposure
    private let lensPosition: Double
    private let gate: FujiCompletionGate<FujiCapturedFrame>

    init(requiresRAW: Bool, exposure: FujiExposure, lensPosition: Double, gate: FujiCompletionGate<FujiCapturedFrame>) {
        self.requiresRAW = requiresRAW
        self.capturedAt = Date()
        self.exposure = exposure
        self.lensPosition = lensPosition
        self.gate = gate
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if let error { failure = error; return }
        guard let data = photo.fileDataRepresentation() else { failure = FujiShootingError.processingFailed; return }
        if photo.isRawPhoto { raw = data } else { processed = data }
        if photo.isRawPhoto || !requiresRAW,
           let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let duration = exif[kCGImagePropertyExifExposureTime as String] as? NSNumber,
           let values = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber], let iso = values.first,
           duration.doubleValue > 0, iso.doubleValue > 0 {
            exposure = FujiExposure(iso: iso.doubleValue, seconds: duration.doubleValue)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        lock.lock()
        let failure = error ?? failure
        let processed = processed
        let raw = raw
        let exposure = exposure
        lock.unlock()
        if let failure { gate.finish(.failure(failure)); return }
        guard let processed, !requiresRAW || raw != nil else {
            gate.finish(.failure(FujiShootingError.processingFailed)); return
        }
        gate.finish(.success(FujiCapturedFrame(processedData: processed, rawData: raw, capturedAt: capturedAt, exposure: exposure, lensPosition: lensPosition)))
    }
}

/// The sequence coordinator can be exercised with a deterministic fake sensor.
protocol FujiCaptureDriver: Sendable {
    func beginFujiCapture(requiresRAW: Bool, requiresCustomExposure: Bool, requiresFocus: Bool) async throws -> FujiSensorSnapshot
    func prepareFujiFrame(transactionID: UUID, exposure: FujiExposure?, focusPosition: Double?) async throws
    func captureFujiFrame(transactionID: UUID, requiresRAW: Bool) async throws -> FujiCapturedFrame
    func endFujiCapture(transactionID: UUID) async throws
    func cancelFujiCapture()
}
extension CameraService: FujiCaptureDriver {}
