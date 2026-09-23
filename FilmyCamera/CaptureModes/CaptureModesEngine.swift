@preconcurrency import AVFoundation
import Foundation
import ImageIO

struct CaptureSceneAnalysis: Sendable {
    var text: String
    var codes: [String]
    var labels: [String]
}

enum CaptureModesEvent: Sendable {
    case state(CaptureModesState)
    case saved(CaptureMedia)
    case failed(String)
    case analysis(CaptureSceneAnalysis)
    case requestedMode(CaptureMode)
}

/// All mutable capture state, configuration, delegates, and timers belong to queue.
/// The UI receives value snapshots; it never changes an AVFoundation device directly.
final class CaptureModesEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.dheeraj.filmycamera.capture-modes", qos: .userInitiated)
    private let photos = AVCapturePhotoOutput()
    private let movie = AVCaptureMovieFileOutput()
    private let emit: @Sendable (CaptureModesEvent) -> Void
    private let recipes: [FilmRecipe]
    private var recipe: FilmRecipe
    private var device: AVCaptureDevice?
    private var state = CaptureModesState()
    private var sequence: CaptureSequence?
    private var media: CaptureMedia?
    private var photoDelegate: ModesPhotoDelegate?
    private var processing: Task<Void, Never>?
    private var movieTimer: DispatchSourceTimer?
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var movieStart: Date?
    private var wantsRunning = false
    private var controlsAllowed = true
    private var pendingConfiguration: (CaptureMode, Bool)?
    private var spatialAngle: CGFloat?
    private var rotationAngle: CGFloat = 90
    private var observers: [NSObjectProtocol] = []
    private var savedMetering: (AVCaptureDevice.FocusMode, AVCaptureDevice.ExposureMode, AVCaptureDevice.WhiteBalanceMode)?

    init(recipe: FilmRecipe, recipes: [FilmRecipe], emit: @escaping @Sendable (CaptureModesEvent) -> Void) {
        self.recipe = recipe
        self.recipes = recipes.isEmpty ? [recipe] : recipes
        self.emit = emit
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.pause(reason: "Camera interrupted. Completed originals remain in Captures. Reopen the mode to continue.")
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                                 object: nil, queue: nil) { [weak self] _ in
            if ProcessInfo.processInfo.thermalState == .critical {
                self?.pause(reason: "The device is too warm to continue. Let it cool before reopening the mode.")
            }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        processing?.cancel()
        movieTimer?.cancel()
        // Normal ownership uses shutdown() before returning to the main camera.
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func configure(mode: CaptureMode, microphone: Bool) {
        queue.async { [self] in
            wantsRunning = true
            if state.phase.isBusy {
                pendingConfiguration = (mode, microphone)
                return
            }
            configureOnQueue(mode: mode, microphone: microphone)
        }
    }

    private func configureOnQueue(mode: CaptureMode, microphone: Bool) {
        state = CaptureModesState()
        state.mode = mode
        state.phase = .configuring
        state.message = "Preparing \(mode.title)"
        publish()
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        var configurationOpen = true
        do {
            if #available(iOS 18.0, *) { session.controls.forEach { session.removeControl($0) } }
            if #available(iOS 18.0, *), movie.isSpatialVideoCaptureEnabled { movie.isSpatialVideoCaptureEnabled = false }
            if photos.isDepthDataDeliveryEnabled { photos.isDepthDataDeliveryEnabled = false }
            if photos.isPortraitEffectsMatteDeliveryEnabled { photos.isPortraitEffectsMatteDeliveryEnabled = false }
            session.outputs.forEach { session.removeOutput($0) }
            session.inputs.forEach { session.removeInput($0) }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                throw CaptureModesError.unavailable("Camera access is disabled. Enable it in Settings to use capture modes.")
            }
            let selected = try selectDevice(for: mode)
            device = selected
            let input = try AVCaptureDeviceInput(device: selected)
            guard session.canAddInput(input) else { throw CaptureModesError.unavailable("This camera input is unavailable.") }
            session.addInput(input)
            guard session.canAddOutput(photos) else { throw CaptureModesError.unavailable("Photo capture is unavailable for this camera.") }
            session.addOutput(photos)
            if mode.isVideo {
                guard session.canAddOutput(movie) else { throw CaptureModesError.unavailable("Movie capture is unavailable for this camera.") }
                session.addOutput(movie)
            }
            if mode == .spatialVideo {
                try configureSpatial(selected)
            } else {
                let preset: AVCaptureSession.Preset = mode.isVideo
                    ? (session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .hd1920x1080) : .photo
                guard session.canSetSessionPreset(preset) else { throw CaptureModesError.unavailable("The requested capture format is unavailable.") }
                session.sessionPreset = preset
                if mode.isVideo { state.format = preset == .hd4K3840x2160 ? "4K / 30" : "1080p / 30 (4K unavailable)" }
            }
            try selected.lockForConfiguration()
            if selected.isFocusModeSupported(.continuousAutoFocus) { selected.focusMode = .continuousAutoFocus }
            if selected.isExposureModeSupported(.continuousAutoExposure) { selected.exposureMode = .continuousAutoExposure }
            if selected.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { selected.whiteBalanceMode = .continuousAutoWhiteBalance }
            if mode == .macro, selected.isAutoFocusRangeRestrictionSupported { selected.autoFocusRangeRestriction = .near }
            if mode.isVideo {
                let supports30 = selected.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
                if supports30 {
                    selected.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    selected.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                } else { state.format = state.format.replacingOccurrences(of: "/ 30", with: "/ device frame rate") }
            }
            selected.unlockForConfiguration()
            let dimensions = selected.activeFormat.supportedMaxPhotoDimensions.sorted {
                Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
            }
            guard let size = dimensions.last(where: { Int64($0.width) * Int64($0.height) <= 12_500_000 }) else {
                throw CaptureModesError.unavailable("A capture format at or below 12 MP is unavailable in this configuration.")
            }
            photos.maxPhotoDimensions = size
            photos.maxPhotoQualityPrioritization = .quality
            if !mode.isVideo { state.format = "\(size.width) × \(size.height)" }
            if mode == .portrait {
                guard photos.isDepthDataDeliverySupported, photos.availablePhotoCodecTypes.contains(.hevc) else {
                    throw CaptureModesError.unavailable("Depth capture is not supported by this camera configuration. Choose Photo or another device.")
                }
                photos.isDepthDataDeliveryEnabled = true
                if photos.isPortraitEffectsMatteDeliverySupported { photos.isPortraitEffectsMatteDeliveryEnabled = true }
                state.hasDepth = true
            } else if photos.isDepthDataDeliverySupported { photos.isDepthDataDeliveryEnabled = false }
            if mode.isVideo, microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let audio = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audio)
                guard session.canAddInput(audioInput) else { throw CaptureModesError.unavailable("Microphone input is unavailable. Turn audio off to record silently.") }
                session.addInput(audioInput)
                state.microphoneEnabled = true
            }
            for output in session.outputs {
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle), mode != .spatialVideo {
                    connection.videoRotationAngle = rotationAngle
                }
            }
            if mode.isVideo, let connection = movie.connection(with: .video) {
                if mode != .spatialVideo {
                    if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .standard }
                    if movie.availableVideoCodecTypes.contains(.hevc) {
                        movie.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
                    }
                }
                movie.maxRecordedDuration = CMTime(seconds: CaptureModesPolicy.maximumMovieSeconds, preferredTimescale: 600)
                movie.minFreeDiskSpaceLimit = 256_000_000
            }
            state.maximumZoom = Double(min(selected.maxAvailableVideoZoomFactor, 10))
            state.minimumExposure = Double(selected.minExposureTargetBias)
            state.maximumExposure = Double(selected.maxExposureTargetBias)
            state.zoom = Double(selected.videoZoomFactor)
            if #available(iOS 18.0, *) { installControls(selected) }
            session.commitConfiguration()
            configurationOpen = false
            guard wantsRunning else { state.phase = .stopped; publish(); return }
            session.startRunning()
            guard session.isRunning else { throw CaptureModesError.unavailable("The capture session did not start. Try reopening this mode.") }
            state.phase = .ready
            state.message = mode.guidance
            publish()
        } catch {
            if configurationOpen { session.commitConfiguration() }
            state.phase = .unavailable
            state.message = error.localizedDescription
            publish()
            emit(.failed(error.localizedDescription))
        }
    }

    private func selectDevice(for mode: CaptureMode) throws -> AVCaptureDevice {
        let result: AVCaptureDevice?
        if mode == .macro {
            result = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            guard let result, CaptureModesPolicy.supportsMacro(minimumFocusDistance: Int(result.minimumFocusDistance),
                autofocus: result.isFocusModeSupported(.continuousAutoFocus)) else {
                throw CaptureModesError.unavailable("Macro requires an autofocusing ultra-wide lens with a close focus distance. This device does not provide one.")
            }
            return result
        } else if mode == .portrait {
            result = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInTripleCamera, .builtInDualWideCamera],
                                                      mediaType: .video, position: .back).devices.first
                ?? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        } else if mode == .spatialVideo {
            result = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
        } else { result = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) }
        guard let result else { throw CaptureModesError.unavailable("\(mode.title) needs camera hardware that this device does not provide.") }
        return result
    }

    private func configureSpatial(_ device: AVCaptureDevice) throws {
        guard #available(iOS 18.0, *),
              let format = device.formats.first(where: { $0.isSpatialVideoCaptureSupported }) else {
            throw CaptureModesError.unavailable("Native spatial video is unavailable on this device or OS version.")
        }
        session.sessionPreset = .inputPriority
        try device.lockForConfiguration()
        device.activeFormat = format
        device.unlockForConfiguration()
        guard movie.isSpatialVideoCaptureSupported else { throw CaptureModesError.unavailable("The configured outputs cannot record native spatial video.") }
        movie.isSpatialVideoCaptureEnabled = true
        if let connection = movie.connection(with: .video), device.activeFormat.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
            connection.preferredVideoStabilizationMode = .cinematicExtendedEnhanced
        }
        state.format = "Native spatial / 30"
    }

    func setSpatialAngle(_ angle: CGFloat?) { queue.async { [self] in spatialAngle = angle } }

    /// Interface-orientation-derived rotation for non-spatial video/photo connections, matching
    /// the main capture path (CameraService.videoRotationAngle). Applied on the next configure and
    /// immediately to already-installed connections so landscape iPad captures aren't sideways.
    func setRotationAngle(_ angle: CGFloat) {
        queue.async { [self] in
            rotationAngle = angle
            guard state.mode != .spatialVideo else { return }
            for output in session.outputs {
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    func setZoom(_ value: Double) {
        queue.async { [self] in
            guard !state.phase.isBusy, state.mode != .spatialVideo, let device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = CGFloat(min(max(value, Double(device.minAvailableVideoZoomFactor)), state.maximumZoom))
                device.unlockForConfiguration()
                state.zoom = Double(device.videoZoomFactor); publish()
            } catch { emit(.failed(error.localizedDescription)) }
        }
    }

    func setExposure(_ value: Double) {
        queue.async { [self] in
            guard !state.phase.isBusy, let device, value.isFinite else { return }
            do {
                try device.lockForConfiguration()
                let bias = Float(min(max(value, state.minimumExposure), state.maximumExposure))
                device.setExposureTargetBias(bias, completionHandler: nil)
                device.unlockForConfiguration()
                state.exposure = Double(bias); publish()
            } catch { emit(.failed(error.localizedDescription)) }
        }
    }

    func focus(_ point: CGPoint) {
        queue.async { [self] in
            guard state.phase == .ready, let device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            } catch { emit(.failed(error.localizedDescription)) }
        }
    }

    func selectRecipe(_ index: Int) {
        queue.async { [self] in
            guard !state.phase.isBusy, recipes.indices.contains(index) else { return }
            recipe = recipes[index]
            publish()
        }
    }

    func shutter() {
        queue.async { [self] in
            if state.phase == .recording { movie.stopRecording(); return }
            if state.phase == .capturing { stopSequence(); return }
            guard state.phase == .ready, session.isRunning else { return }
            do {
                try CaptureMediaStore.preflight()
                if state.mode == .spatialVideo, spatialAngle == nil {
                    throw CaptureModesError.unavailable("Turn the phone horizontally before starting spatial video.")
                }
                let record = CaptureMedia(id: UUID(), mode: state.mode, createdAt: Date(), recipeName: recipe.name)
                try CaptureMediaStore.persist(record)
                try CaptureMediaStore.saveRecipe(recipe, in: record.id)
                media = record
                state.frameCount = 0
                if state.mode.isVideo {
                    if state.mode == .spatialVideo, let angle = spatialAngle, let connection = movie.connection(with: .video),
                       connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                    state.phase = .recording
                    state.seconds = 0
                    state.message = state.microphoneEnabled ? "Recording with audio" : "Recording silently"
                    publish()
                    movie.startRecording(to: try CaptureMediaStore.file("original-video.mov", in: record.id), recordingDelegate: self)
                    startMovieTimer()
                } else {
                    sequence = CaptureSequence(mode: state.mode, id: record.id)
                    if state.mode == .night || state.mode == .panorama { try lockMetering() }
                    state.phase = .capturing
                    publish()
                    requestFrame()
                }
            } catch { fail(error) }
        }
    }

    func stopSequenceCapture() { queue.async { [self] in stopSequence() } }
    private func stopSequence() {
        guard sequence != nil else { return }
        sequence?.requestStop()
        if sequence?.shouldFinish == true { finishSequence() }
    }

    private func requestFrame() {
        guard state.phase == .capturing, var current = sequence else { return }
        guard let index = current.reserveFrame() else { if current.shouldFinish { finishSequence() }; return }
        sequence = current
        let id = current.id
        let settings = makePhotoSettings()
        let delegate = ModesPhotoDelegate { [weak self] result in
            guard let self else { return }
            self.queue.async { [self] in
                guard sequence?.id == id else { return }
                photoDelegate = nil
                do {
                    let packet = try result.get()
                    guard var record = media else { throw CaptureModesError.cancelled }
                    let name = String(format: "original-%03d.%@", index, packet.isHEIF ? "heic" : "jpg")
                    try packet.data.write(to: CaptureMediaStore.file(name, in: id), options: .atomic)
                    record.originals.append(name)
                    try CaptureMediaStore.persist(record)
                    media = record
                    if state.mode == .portrait, !packet.hasDepth { throw CaptureModesError.unavailable("No depth was delivered. The original is retained. Try a well-lit subject farther from the lens.") }
                    guard sequence?.completeFrame(index) == true else { return }
                    state.frameCount = record.originals.count
                    state.message = "\(state.mode.title): \(state.frameCount) / \(state.mode.frameLimit)"
                    publish()
                    if sequence?.shouldFinish == true { finishSequence() }
                    else {
                        let delay = state.mode == .panorama ? 0.65 : 0.04
                        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard self?.sequence?.id == id else { return }
                            self?.requestFrame()
                        }
                    }
                } catch { fail(error) }
            }
        }
        photoDelegate = delegate
        photos.capturePhoto(with: settings, delegate: delegate)
    }

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings = photos.availablePhotoCodecTypes.contains(.hevc)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photos.maxPhotoDimensions
        settings.photoQualityPrioritization = [.burst, .night, .panorama].contains(state.mode) ? .speed : .quality
        settings.flashMode = .off
        if state.mode == .portrait {
            settings.isDepthDataDeliveryEnabled = true
            settings.embedsDepthDataInPhoto = true
            if photos.isPortraitEffectsMatteDeliveryEnabled {
                settings.isPortraitEffectsMatteDeliveryEnabled = true
                settings.embedsPortraitEffectsMatteInPhoto = true
            }
        }
        return settings
    }

    private func finishSequence() {
        sequence = nil
        restoreMetering()
        guard let record = media else { settle(); return }
        guard wantsRunning else {
            emit(.saved(record)); media = nil; settle(); return
        }
        process(record)
    }

    func retry(_ record: CaptureMedia) {
        queue.async { [self] in
            guard !state.phase.isBusy else { return }
            do {
                var recovered = try CaptureMediaStore.load(record.id)
                recovered.originals = try CaptureMediaStore.recoverableOriginals(recovered).map(\.lastPathComponent)
                try CaptureMediaStore.persist(recovered)
                let originalRecipe = try CaptureMediaStore.loadRecipe(in: record.id)
                process(recovered, using: originalRecipe)
            } catch { fail(error) }
        }
    }

    private func process(_ record: CaptureMedia, using storedRecipe: FilmRecipe? = nil) {
        media = record
        state.phase = .processing
        state.message = record.mode.isVideo ? "Rendering the film look. The original is safe." : "Developing \(record.mode.title). Originals are safe."
        publish()
        let snapshot = storedRecipe ?? recipe
        processing = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let completed = try await CaptureImageProcessor.process(record, recipe: snapshot)
                guard let self else { return }
                queue.async { [self] in
                    processing = nil; media = nil
                    emit(.saved(completed))
                    state.message = "Saved in Filmy Captures. Export to Photos or share."
                    settle()
                }
            } catch {
                guard let self else { return }
                let message = error.localizedDescription
                queue.async { [self] in processing = nil; fail(CaptureModesError.unavailable(message)) }
            }
        }
    }

    func inspectScene() {
        queue.async { [self] in
            guard state.phase == .ready, !state.mode.isVideo else { return }
            state.phase = .capturing
            state.message = "Reading text, codes, and scene labels on device"
            publish()
            let delegate = ModesPhotoDelegate { [weak self] result in
                guard let self else { return }
                self.queue.async { [self] in
                    photoDelegate = nil
                    do {
                        let packet = try result.get()
                        guard wantsRunning else { settle(); return }
                        state.phase = .processing
                        publish()
                        processing = Task.detached(priority: .userInitiated) { [weak self] in
                            do {
                                let analysis = try CaptureSceneReader.read(packet.data)
                                guard let self else { return }
                                queue.async { [self] in processing = nil; emit(.analysis(analysis)); settle() }
                            } catch {
                                guard let self else { return }
                                let message = error.localizedDescription
                                queue.async { [self] in processing = nil; fail(CaptureModesError.unavailable(message)) }
                            }
                        }
                    } catch { fail(error) }
                }
            }
            photoDelegate = delegate
            photos.capturePhoto(with: makePhotoSettings(), delegate: delegate)
        }
    }

    func pause(reason: String = "Capture paused. Completed originals remain in Captures.") {
        queue.async { [self] in pauseOnQueue(reason: reason) }
    }

    private func pauseOnQueue(reason: String) {
        wantsRunning = false
        pendingConfiguration = nil
        processing?.cancel()
        sequence?.requestStop()
        if movie.isRecording {
            // Wait for fileOutput(_:didFinishRecordingTo:from:error:) to stop the session so the
            // movie trailer is written before the capture session tears down.
            movie.stopRecording()
        } else if session.isRunning {
            session.stopRunning()
        }
        if sequence?.shouldFinish == true { finishSequence() }
        if photoDelegate == nil, processing == nil, !movie.isRecording { state.phase = .stopped }
        state.message = reason
        publish()
    }

    func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                pauseOnQueue(reason: "Camera closed")
                // A recording movie stops the session from its finish callback; resume then.
                if movie.isRecording { shutdownWaiters.append(continuation) } else { continuation.resume() }
            }
        }
    }

    private func settle() {
        if let next = pendingConfiguration, wantsRunning {
            pendingConfiguration = nil
            configureOnQueue(mode: next.0, microphone: next.1)
        } else {
            state.phase = wantsRunning && session.isRunning ? .ready : .stopped
            publish()
        }
    }

    private func fail(_ error: Error) {
        sequence = nil
        restoreMetering()
        if let record = media {
            if record.originals.isEmpty { try? CaptureMediaStore.delete(record.id) } else { emit(.saved(record)) }
            media = nil
        }
        state.message = error.localizedDescription
        emit(.failed(error.localizedDescription))
        if !wantsRunning, !movie.isRecording, session.isRunning { session.stopRunning() }
        settle()
    }

    func setControlsAllowed(_ allowed: Bool) { queue.async { [self] in controlsAllowed = allowed; publish() } }

    private func publish() {
        state.recipeName = recipe.name
        if #available(iOS 18.0, *) {
            for control in session.controls {
                control.isEnabled = controlsAllowed && (state.phase == .ready || (state.phase == .recording && state.mode != .spatialVideo
                    && !(control is AVCaptureIndexPicker) && !(control is AVCaptureSlider)))
            }
        }
        emit(.state(state))
    }

    private func lockMetering() throws {
        guard let device else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        savedMetering = (device.focusMode, device.exposureMode, device.whiteBalanceMode)
        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
        state.focusLocked = true
    }

    private func restoreMetering() {
        guard let device, let saved = savedMetering else { return }
        savedMetering = nil
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(saved.0) { device.focusMode = saved.0 }
            if device.isExposureModeSupported(saved.1) { device.exposureMode = saved.1 }
            if device.isWhiteBalanceModeSupported(saved.2) { device.whiteBalanceMode = saved.2 }
            device.unlockForConfiguration()
        } catch { emit(.failed("Automatic metering could not be restored. Reopen the mode.")) }
        state.focusLocked = false
    }

    private func startMovieTimer() {
        movieStart = Date()
        movieTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, let start = movieStart else { return }
            state.seconds = Int(Date().timeIntervalSince(start))
            if #available(iOS 18.0, *), state.mode == .spatialVideo, let device {
                let reasons = device.spatialCaptureDiscomfortReasons
                state.warning = reasons.isEmpty ? nil : "Spatial quality warning: add light, move farther from the subject, and hold level."
            }
            publish()
        }
        movieTimer = timer
        timer.resume()
    }
}

extension CaptureModesEngine: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let message = error?.localizedDescription
        let successfullyFinished = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        queue.async { [self] in
            defer {
                if !wantsRunning, session.isRunning { session.stopRunning() }
                let waiters = shutdownWaiters; shutdownWaiters = []
                waiters.forEach { $0.resume() }
            }
            movieTimer?.cancel(); movieTimer = nil; movieStart = nil
            guard var record = media else { settle(); return }
            do {
                guard successfullyFinished else { throw CaptureModesError.unavailable(message ?? "Movie recording failed. Any recoverable original remains in Captures.") }
                record.originals = [outputFileURL.lastPathComponent]
                if let message { record.notes.append(message) }
                try CaptureMediaStore.persist(record)
                media = record
                if wantsRunning { process(record) }
                else {
                    emit(.saved(record)); media = nil
                    if session.isRunning { session.stopRunning() }
                    settle()
                }
            } catch { fail(error) }
        }
    }
}

private struct ModesPhotoPacket: Sendable { let data: Data; let hasDepth: Bool; let isHEIF: Bool }

private final class ModesPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var packet: ModesPhotoPacket?
    private var failure: Error?
    private let completion: @Sendable (Result<ModesPhotoPacket, Error>) -> Void
    init(completion: @escaping @Sendable (Result<ModesPhotoPacket, Error>) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { failure = error; return }
        guard let data = photo.fileDataRepresentation() else { failure = CaptureModesError.invalidImage; return }
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let type = source.flatMap { CGImageSourceGetType($0) }.map { $0 as String }
        packet = ModesPhotoPacket(data: data, hasDepth: photo.depthData != nil, isHEIF: type == "public.heic" || type == "public.heif")
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? failure { completion(.failure(error)) }
        else if let packet { completion(.success(packet)) }
        else { completion(.failure(CaptureModesError.invalidImage)) }
    }
}

@available(iOS 18.0, *)
extension CaptureModesEngine: AVCaptureSessionControlsDelegate {
    private func installControls(_ device: AVCaptureDevice) {
        guard session.supportsControls else { return }
        session.setControlsDelegate(self, queue: queue)
        var controls: [AVCaptureControl] = []
        if state.mode != .spatialVideo {
            controls.append(AVCaptureSystemZoomSlider(device: device) { [weak self] factor in
                self?.queue.async { [weak self] in self?.state.zoom = Double(factor); self?.publish() }
            })
            controls.append(AVCaptureSystemExposureBiasSlider(device: device) { [weak self] bias in
                self?.queue.async { [weak self] in self?.state.exposure = Double(bias); self?.publish() }
            })
        }
        let modes = AVCaptureIndexPicker("Mode", symbolName: "camera", localizedIndexTitles: CaptureMode.allCases.map(\.title))
        modes.setActionQueue(queue) { [weak self] index in
            guard let self, state.phase == .ready, CaptureMode.allCases.indices.contains(index) else { return }
            emit(.requestedMode(CaptureMode.allCases[index]))
        }
        modes.selectedIndex = CaptureMode.allCases.firstIndex(of: state.mode) ?? 0
        controls.append(modes)
        if state.mode != .spatialVideo {
            let film = AVCaptureIndexPicker("Film", symbolName: "camera.filters", localizedIndexTitles: recipes.map(\.name))
            film.setActionQueue(queue) { [weak self] index in
                guard let self, state.phase == .ready, recipes.indices.contains(index) else { return }
                recipe = recipes[index]; publish()
            }
            film.selectedIndex = recipes.firstIndex(where: { $0.id == recipe.id }) ?? 0
            controls.append(film)
            if device.isLockingFocusWithCustomLensPositionSupported {
                let focus = AVCaptureSlider("Focus", symbolName: "scope", in: 0...1)
                focus.setActionQueue(queue) { [weak self] value in
                    guard let self, state.phase == .ready, let device = self.device else { return }
                    do {
                        try device.lockForConfiguration()
                        device.setFocusModeLocked(lensPosition: value, completionHandler: nil)
                        device.unlockForConfiguration()
                    } catch { emit(.failed(error.localizedDescription)) }
                }
                controls.append(focus)
            }
        }
        for control in controls where session.canAddControl(control) { session.addControl(control) }
        state.controlsSupported = !session.controls.isEmpty
    }

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) { state.controlsExpanded = true; publish() }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) { state.controlsExpanded = true; publish() }
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) { state.controlsExpanded = false; publish() }
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) { state.controlsExpanded = false; publish() }
}
