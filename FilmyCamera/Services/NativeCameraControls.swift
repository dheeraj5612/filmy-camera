@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// A compile-time AND runtime gate. No private selectors, guessed KVC keys,
/// device-name allowlists, or software 'aperture' blur stand in for hardware.
enum NativeCameraControls {
    struct ExposureRequest: Equatable, Sendable {
        var program: CameraExposureProgram
        var iso: Float
        var durationSeconds: Double
        var aperture: Float
    }

    static func populateCapabilities(for device: AVCaptureDevice, in result: inout ProCaptureCapabilities) {
        result.aperture = device.lensAperture
        if device.isExposureModeSupported(.custom) { result.exposurePrograms.append(.manual) }
#if FILMY_IOS27_SDK
        if #available(iOS 27.0, *) {
            result.nativeExposureAPIAvailable = true
            let format = device.activeFormat
            result.minimumAperture = format.minLensAperture
            result.maximumAperture = format.maxLensAperture
            let autoAperture = AVCaptureDevice.autoLensAperture
            let autoDuration = AVCaptureDevice.autoExposureDuration
            let autoISO = AVCaptureDevice.autoISO
            if format.supportsExposureModeCustom(
                lensAperture: autoAperture, duration: AVCaptureDevice.currentExposureDuration, iso: autoISO
            ) { result.exposurePrograms.append(.shutterPriority) }
            if format.supportsExposureModeCustom(
                lensAperture: autoAperture, duration: autoDuration, iso: AVCaptureDevice.currentISO
            ) { result.exposurePrograms.append(.isoPriority) }
            if format.maxLensAperture > format.minLensAperture,
               format.supportsExposureModeCustom(
                lensAperture: AVCaptureDevice.currentLensAperture, duration: autoDuration, iso: autoISO
               ) { result.exposurePrograms.append(.aperturePriority) }
        }
#endif
    }

    /// Caller holds the configuration lock and serializes completion readback.
    /// Returning false means no request was sent and the UI must not claim it
    /// was applied. Apple may support some, but not all, priority combinations.
    static func apply(
        _ request: ExposureRequest,
        to device: AVCaptureDevice,
        completion: @escaping @Sendable (CMTime) -> Void
    ) -> Bool {
#if FILMY_IOS27_SDK
        if #available(iOS 27.0, *) {
            let format = device.activeFormat
            let iso = min(max(request.iso, format.minISO), format.maxISO)
            let minimum = CMTimeGetSeconds(format.minExposureDuration)
            let maximum = CMTimeGetSeconds(format.maxExposureDuration)
            let seconds = min(max(request.durationSeconds, minimum), maximum)
            let duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
            let aperture = min(max(request.aperture, format.minLensAperture), format.maxLensAperture)
            let apertureValue = request.program == .aperturePriority || request.program == .manual
                ? aperture : AVCaptureDevice.autoLensAperture
            let durationValue = request.program == .shutterPriority || request.program == .manual
                ? duration : AVCaptureDevice.autoExposureDuration
            let isoValue = request.program == .isoPriority || request.program == .manual
                ? iso : AVCaptureDevice.autoISO
            guard iso.isFinite, seconds.isFinite, seconds > 0, aperture.isFinite,
                  format.supportsExposureModeCustom(lensAperture: apertureValue, duration: durationValue, iso: isoValue) else {
                return false
            }
            device.setExposureModeCustom(lensAperture: apertureValue, duration: durationValue, iso: isoValue, completionHandler: completion)
            return true
        }
#endif
        return false
    }

    static func subjectAcquired(_ device: AVCaptureDevice) -> Bool {
#if FILMY_IOS27_SDK
        if #available(iOS 27.0, *) { return device.isContinuousAutoFocusTrackingSubjectAcquired }
#endif
        return false
    }

    static func supportsSubjectTracking(_ device: AVCaptureDevice) -> Bool {
#if FILMY_IOS27_SDK
        if #available(iOS 27.0, *) { return device.activeFormat.isContinuousAutoFocusTrackingSupported }
#endif
        return false
    }

    /// Caller holds the device configuration lock. Vision supplies the older-
    /// system fallback; native tracking alone owns focus when available.
    static func setSubjectTracking(_ enabled: Bool, on device: AVCaptureDevice) {
#if FILMY_IOS27_SDK
        if #available(iOS 27.0, *), device.activeFormat.isContinuousAutoFocusTrackingSupported {
            device.isContinuousAutoFocusTrackingEnabled = enabled
            if enabled && device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        }
#endif
    }
}
