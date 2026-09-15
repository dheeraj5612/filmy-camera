import Combine
import CoreImage
import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct FujiSequenceRequest: Sendable {
    let id = UUID()
    let settings: FujiShootingSettings
    let recipe: FilmRecipe
    let filmRecipes: [FilmRecipe]
    let viewport: CGSize
    let finish: PhotoFinish
    let grainSeed: UInt32
    let shutterUptime: TimeInterval
}

@MainActor
final class FujiShootingController: ObservableObject {
    @Published var preferences: FujiPreferences {
        didSet {
            preferences = preferences.normalized()
            do { defaults.set(try JSONEncoder().encode(preferences), forKey: "fuji.shooting.v1") }
            catch { errorMessage = "Shooting settings could not be saved." }
            refreshPreview()
        }
    }
    @Published private(set) var isBusy = false
    @Published private(set) var status = ""
    @Published var errorMessage: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var multipleCount = 0
    @Published private(set) var pendingExportCount = 0
    @Published private(set) var originals: [FujiOriginalRecord] = []
    @Published private(set) var hybridImage: UIImage?
    @Published private(set) var focusImage: UIImage?
    @Published private(set) var ghostImage: UIImage?
    @Published private(set) var focusContrast: Double = 0
    @Published private(set) var bufferedCount = 0
    private let defaults: UserDefaults
    private let library: FujiCaptureLibrary
    private let worker = FujiDevelopmentWorker()
    private let previewWorker = FujiDevelopmentWorker()
    private let sampler = FujiFrameSampler()
    private weak var camera: CameraService?
    private weak var viewModel: CameraViewModel?
    private var frameHandlerID: UUID?
    private var task: Task<Void, Never>?
    private var developmentTask: Task<Void, Error>?
    private var active = false
    private var multipleRequest: FujiSequenceRequest?
    private var multipleDeviceID: String?
    private var multipleCapturedAt: Date?
    private var appliedProfile: FujiAutoISOProfile?
    private var profileDeviceID: String?
    private var appliedPrimeLock = false
    @Published private(set) var settingUpPrime = false
    private var idleTimerWasDisabled: Bool?
    private var memoryObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, library: FujiCaptureLibrary = .shared) {
        self.defaults = defaults; self.library = library
        let loaded = FujiPreferences.load(from: defaults)
        preferences = loaded.preferences
        if loaded.recovered { errorMessage = "Shooting settings were recovered to defaults. The previous data was kept for recovery." }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cancel()
                    self?.sampler.reset()
                    self?.errorMessage = "Shooting stopped because memory is low. Already saved frames and originals are kept."
                }
            }
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if ProcessInfo.processInfo.thermalState == .critical {
                        self?.cancel()
                        self?.errorMessage = "The device needs to cool down before another sequence."
                    }
                }
            }
    }

    deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        task?.cancel()
        if let frameHandlerID { camera?.removeFrameHandler(frameHandlerID) }
    }

    var settings: FujiShootingSettings { preferences.settings }
    var isComposing: Bool { multipleRequest != nil }
    var settingsLocked: Bool { isBusy || isComposing || settingUpPrime }
    var validationMessage: String? {
        do { _ = try FujiCapturePlan.make(settings); return nil }
        catch { return error.localizedDescription }
    }
    var needsCoordinator: Bool { settings.needsCaptureCoordinator || isComposing }

    func attach(camera: CameraService, viewModel: CameraViewModel, active: Bool) {
        if self.camera !== camera {
            if let frameHandlerID { self.camera?.removeFrameHandler(frameHandlerID) }
            self.camera = camera
            frameHandlerID = camera.installFrameHandler { [weak self] image in
                self?.sampler.submit(image)
            }
        }
        self.viewModel = viewModel
        self.active = active
        if !active { cancel(); hybridImage = nil; focusImage = nil; bufferedCount = 0 }
        refreshPreview()
    }

    func invalidatePreview() { sampler.reset(); hybridImage = nil; focusImage = nil; bufferedCount = 0; refreshPreview() }

    func refreshPreview() {
        guard let camera, let viewModel else { return }
        let visible = active && !isBusy && camera.isRunning
        sampler.configure(settings: settings, recipe: viewModel.selectedRecipe, viewport: camera.previewViewportSize,
                          active: visible) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.active, !self.isBusy else { return }
                self.hybridImage = result.inset.map { UIImage(cgImage: $0) }
                self.focusImage = result.focus.map { UIImage(cgImage: $0) }
                self.focusContrast = result.contrast
                self.bufferedCount = result.bufferedCount
            }
        }
        if settings.viewfinder != .hybrid { hybridImage = nil }
        if settings.focusAssist == .off { focusImage = nil }
        let profile = active && camera.isRunning ? settings.autoISOProfile : nil
        if !isBusy && (profile != appliedProfile || profileDeviceID != camera.manualControls.activeDeviceID) {
            camera.configureFujiAutoISO(profile)
            appliedProfile = profile; profileDeviceID = camera.manualControls.activeDeviceID
        }
        if active && camera.isRunning && !isBusy && !settingUpPrime && appliedPrimeLock != settings.lockPrimeLens {
            settingUpPrime = true
            Task { [weak self, weak camera] in
                guard let self, let camera else { return }
                defer { self.settingUpPrime = false }
                do {
                    try await camera.configureFujiPrimeLock(self.settings.lockPrimeLens)
                    self.appliedPrimeLock = self.settings.lockPrimeLens
                    self.sampler.reset()
                } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func change<Value>(_ keyPath: WritableKeyPath<FujiShootingSettings, Value>, to value: Value) {
        guard !settingsLocked else { return }
        preferences.settings[keyPath: keyPath] = value
    }

    func bankIsDirty(_ bank: FujiShootingBank) -> Bool {
        guard let camera, let viewModel else { return false }
        return bank.settings != settings || bank.recipe != viewModel.selectedRecipe || bank.camera != preset(camera)
    }

    func saveBank(_ index: Int, name: String) {
        guard (1...7).contains(index), !settingsLocked, let camera, let viewModel else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        let bank = FujiShootingBank(id: index, name: trimmed.isEmpty ? "Custom \(index)" : trimmed,
                                   recipe: viewModel.selectedRecipe, settings: settings, camera: preset(camera), savedAt: Date())
        var updated = preferences
        updated.banks.removeAll { $0.id == index }; updated.banks.append(bank); updated.selectedBank = index
        preferences = updated
        status = "Saved C\(index). Changes are not written back until you save again."
    }

    func recallBank(_ bank: FujiShootingBank) {
        guard !settingsLocked, let camera, let viewModel else { return }
        isBusy = true; status = "Recalling C\(bank.id)…"; errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishActivity() }
            do {
                if camera.isRunning { try await camera.applyFujiPreset(bank.camera) }
                else if camera.availability != .simulator { throw FujiShootingError.unavailable }
                try Task.checkCancellation()
                viewModel.update(recipe: bank.recipe)
                viewModel.select(recipe: bank.recipe)
                defaults.set(bank.camera.aspect, forKey: "captureAspect")
                defaults.set(bank.camera.timer, forKey: "captureDelay")
                defaults.set(bank.camera.finish, forKey: "captureFinish")
                var updated = preferences
                updated.settings = bank.settings; updated.selectedBank = bank.id
                preferences = updated
                appliedProfile = nil; profileDeviceID = nil; appliedPrimeLock = false
                status = "C\(bank.id) · \(bank.name)"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func preset(_ camera: CameraService) -> FujiCameraPreset {
        let controls = camera.manualControls
        return FujiCameraPreset(cameraPosition: camera.cameraPosition.rawValue, deviceID: controls.activeDeviceID,
            zoom: Double(camera.zoomFactor), exposureBias: Double(camera.exposureBias),
            manualISO: controls.exposureMode == .manual && settings.autoISOIndex == nil ? Double(controls.iso) : nil,
            manualShutter: controls.exposureMode == .manual && settings.autoISOIndex == nil ? controls.exposureDurationSeconds : nil,
            manualKelvin: controls.whiteBalanceMode == .manual ? Double(controls.kelvin) : nil,
            manualTint: controls.whiteBalanceMode == .manual ? Double(controls.tint) : nil,
            manualFocus: controls.focusMode == .manual ? Double(controls.lensPosition) : nil,
            flashMode: camera.flashMode.rawValue, aspect: defaults.string(forKey: "captureAspect") ?? "viewfinder",
            timer: defaults.integer(forKey: "captureDelay"), finish: defaults.string(forKey: "captureFinish") ?? "photo")
    }

    func capture(camera: CameraService, viewModel: CameraViewModel, photoLibrary: any PhotoSaving) {
        guard !isBusy, !settingUpPrime, active, camera.isRunning else { return }
        let request = multipleRequest ?? FujiSequenceRequest(settings: settings.normalized(), recipe: viewModel.selectedRecipe,
            filmRecipes: settings.filmRecipeIDs.compactMap { id in viewModel.recipes.first { $0.id == id } },
            viewport: camera.previewViewportSize, finish: PhotoFinish(rawValue: defaults.string(forKey: "captureFinish") ?? "") ?? .photo,
            grainSeed: camera.previewGrainSeed, shutterUptime: ProcessInfo.processInfo.systemUptime)
        do { _ = try FujiCapturePlan.make(request.settings) }
        catch { errorMessage = error.localizedDescription; return }
        guard ProcessInfo.processInfo.thermalState != .critical else { errorMessage = "Let the device cool before shooting."; return }
        if request.settings.drive == .filmBracket && request.filmRecipes.count != 3 {
            errorMessage = "Select three available film recipes in Q → BKT settings."; return
        }
        isBusy = true; progress = 0; errorMessage = nil; status = request.settings.drive.title
        keepScreenAwake()
        task = Task { [weak self] in
            guard let self else { return }
            do { try await self.run(request, driver: camera, photoLibrary: photoLibrary) }
            catch {
                self.errorMessage = error is CancellationError ? FujiShootingError.cancelled.localizedDescription : error.localizedDescription
                // A partly assembled multiple exposure remains usable after a
                // capture error. Explicit cancel/background discards it.
            }
            self.finishActivity()
            await self.reloadLibrary()
        }
    }

    /// Cancellation is delivered to AVFoundation's pending continuation, not
    /// merely recorded as a Task flag while a native callback is outstanding.
    func run(_ request: FujiSequenceRequest, driver: any FujiCaptureDriver, photoLibrary: any PhotoSaving) async throws {
        try await withTaskCancellationHandler {
            try await execute(request, driver: driver, photoLibrary: photoLibrary)
        } onCancel: { driver.cancelFujiCapture() }
    }

    private func execute(_ request: FujiSequenceRequest, driver: any FujiCaptureDriver, photoLibrary: any PhotoSaving) async throws {
        let plan = try FujiCapturePlan.make(request.settings)
        let settings = plan.settings
        let variants = try Self.variants(for: request)
        let custom = settings.autoISOIndex != nil || settings.dynamicRange != .dr100 || settings.drive == .dynamicRangeBracket
            || settings.drive == .aeBracket || settings.drive == .computationalND || settings.drive.usesFocusSweep
        let preFrames = settings.preShotSeconds > 0
            ? await sampler.snapshot(at: request.shutterUptime, seconds: settings.preShotSeconds) : []
        sampler.configure(settings: settings, recipe: request.recipe, viewport: request.viewport, active: false) { _ in }
        var sensor: FujiSensorSnapshot?
        for attempt in 0..<8 {
            try Task.checkCancellation()
            do {
                sensor = try await driver.beginFujiCapture(requiresRAW: settings.needsRAW, requiresCustomExposure: custom,
                                                           requiresFocus: settings.drive.usesFocusSweep)
                break
            } catch FujiShootingError.busy where attempt < 7 { try await Task.sleep(for: .milliseconds(60)) }
        }
        guard let sensor else { throw FujiShootingError.busy }
        var captured: [FujiOriginalRecord] = []
        do {
            try Task.checkCancellation()
            if let multipleDeviceID, multipleDeviceID != sensor.deviceID {
                throw FujiShootingError.invalidCombination("The lens changed. Cancel this multiple exposure before continuing.")
            }
            let base = settings.autoISOProfile.map { FujiMath.autoExposure(metered: sensor.exposure, profile: $0,
                isoRange: sensor.isoRange, durationRange: sensor.durationRange) } ?? sensor.exposure
            let exposures = try plan.steps.map { step -> FujiExposure? in
                custom ? try FujiMath.shiftedExposure(base, stops: step.exposureOffset - step.dynamicRange.protectionStops,
                    isoRange: sensor.isoRange, durationRange: sensor.durationRange) : nil
            }
            // Capture first, develop second. Only filenames/metadata accumulate;
            // burst cadence is not throttled by FilmRenderer or Photos writes.
            for (index, step) in plan.steps.enumerated() {
                try Task.checkCancellation()
                let start = ProcessInfo.processInfo.systemUptime
                status = "Capturing \(settings.drive.title) · \(index + 1)/\(plan.steps.count)"
                try await driver.prepareFujiFrame(transactionID: sensor.transactionID, exposure: exposures[index], focusPosition: step.focusPosition)
                if step.focusPosition != nil { try await Task.sleep(for: .seconds(settings.focusInterval)) }
                try Task.checkCancellation()
                let frame = try await driver.captureFujiFrame(transactionID: sensor.transactionID, requiresRAW: settings.needsRAW)
                let data = frame.rawData ?? frame.processedData
                let label = settings.drive == .multipleExposure
                    ? "Multiple exposure layer \(multipleCount + 1)/\(settings.multipleExposureCount)"
                    : "\(settings.drive.title) \(index + 1)/\(plan.steps.count)"
                let record = originalRecord(dataIsRAW: frame.rawData != nil, request: request, recipe: request.recipe,
                    capturedAt: frame.capturedAt, step: step, exposure: frame.exposure, label: label)
                try await library.retainOriginal(data, record: record)
                captured.append(record)
                try Task.checkCancellation()
                if let expected = exposures[index], step.dynamicRange != .dr100 || settings.drive == .aeBracket {
                    guard frame.exposure.product.isFinite, frame.exposure.product > 0,
                          abs(log2(frame.exposure.product / expected.product)) < 0.15 else {
                        throw FujiShootingError.invalidCombination("The camera did not honor the requested exposure. The original was kept without exporting a misleading DR/bracket result.")
                    }
                }
                progress = 0.6 * Double(index + 1) / Double(plan.steps.count)
                if index + 1 < plan.steps.count, step.delayAfter > 0, !settings.drive.usesFocusSweep {
                    // Requested start-to-start interval; never emit a catch-up
                    // burst when capture or disk latency exceeds the interval.
                    let delay = max(0, step.delayAfter - (ProcessInfo.processInfo.systemUptime - start))
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                }
            }
            try await driver.endFujiCapture(transactionID: sensor.transactionID)
        } catch {
            do { try await driver.endFujiCapture(transactionID: sensor.transactionID) }
            catch { errorMessage = "Sensor restoration failed. Reopen the camera before continuing." }
            throw error
        }
        try Task.checkCancellation()
        if settings.drive.isComposite && multipleRequest == nil { await worker.reset() }
        var lastData = Data()
        var lastDate = Date()
        for (index, record) in captured.enumerated() {
            try Task.checkCancellation()
            status = "Developing \(settings.drive.title) · \(index + 1)/\(captured.count)"
            let data = try await library.originalData(record)
            lastData = data; lastDate = record.capturedAt
            if settings.drive.isComposite {
                let thumbnail = try await worker.append(data: data, record: record, focusStack: settings.drive == .focusStack,
                    blendMode: settings.drive == .computationalND ? .average : settings.blendMode)
                try Task.checkCancellation()
                if settings.drive == .multipleExposure {
                    multipleRequest = request; multipleDeviceID = sensor.deviceID
                    if multipleCapturedAt == nil { multipleCapturedAt = record.capturedAt }
                    multipleCount += 1; ghostImage = UIImage(cgImage: thumbnail.image)
                }
            } else {
                for (recipe, label) in variants {
                    try Task.checkCancellation()
                    var edited = record; edited.recipe = recipe
                    let result = try await worker.develop(data: data, record: edited, finish: request.finish, grainSeed: request.grainSeed)
                    try await export(result.data, recipe: recipe, capturedAt: record.capturedAt,
                                     label: "\(record.label) · \(label)", photoLibrary: photoLibrary)
                }
            }
            progress = 0.6 + 0.4 * Double(index + 1) / Double(captured.count)
        }
        try Task.checkCancellation()
        if settings.drive.isComposite {
            if settings.drive != .multipleExposure || multipleCount >= settings.multipleExposureCount {
                let capturedAt = multipleCapturedAt ?? lastDate
                let result = try await worker.finish(recipe: request.recipe, sourceData: lastData, capturedAt: capturedAt,
                                                     finish: request.finish, grainSeed: request.grainSeed)
                try await export(result.data, recipe: request.recipe, capturedAt: capturedAt,
                                 label: settings.drive.title, photoLibrary: photoLibrary, didPersist: { self.clearMultiple() })
                await worker.reset()
                status = "Saved \(settings.drive.title) · \(result.width) × \(result.height)"
            } else { status = "Multiple exposure \(multipleCount)/\(settings.multipleExposureCount) · Compose the next layer, then press the shutter." }
        } else { status = "Saved \(settings.drive.title)." }
        // Pre-shot writes follow the real shutter frame. Their date is the frame
        // timestamp, not the later date at which development or Photos finishes.
        for (index, frame) in preFrames.enumerated() {
            try Task.checkCancellation()
            let data = try await Task.detached(priority: .utility) { try FujiFrameSampler.jpeg(frame) }.value
            let record = originalRecord(dataIsRAW: false, request: request, recipe: request.recipe,
                capturedAt: frame.capturedAt, step: .init(), exposure: nil, label: "Pre-shot \(index + 1) · preview resolution")
            let result = try await worker.develop(data: data, record: record, finish: request.finish, grainSeed: request.grainSeed)
            try await export(result.data, recipe: request.recipe, capturedAt: frame.capturedAt,
                             label: record.label, photoLibrary: photoLibrary)
        }
        for record in captured where !record.isRAW && !(settings.drive.isComposite && settings.keepCompositeSources) {
            try await library.removeOriginal(id: record.id)
        }
    }

    static func variants(for request: FujiSequenceRequest) throws -> [(FilmRecipe, String)] {
        switch request.settings.drive {
        case .filmBracket:
            guard request.filmRecipes.count == 3 else { throw FujiShootingError.invalidCombination("Select three film recipes.") }
            return request.filmRecipes.map { ($0, $0.name) }
        case .isoBracket:
            return try [0, -request.settings.isoBracketStep, request.settings.isoBracketStep].map { offset in
                var recipe = request.recipe
                recipe.exposure += offset
                guard FilmRecipe.Control.exposure.editorRange.contains(recipe.exposure) else {
                    throw FujiShootingError.invalidCombination("The ISO bracket exceeds the recipe exposure range. Reduce the recipe's exposure first.")
                }
                return (recipe, String(format: "ISO BKT %+.2f EV · one source", offset))
            }
        case .whiteBalanceBracket:
            return try [0, -request.settings.whiteBalanceStep, request.settings.whiteBalanceStep].map { offset in
                var recipe = request.recipe
                recipe.whiteBalance.temperature += Double(offset) * 0.036
                guard (-1...1).contains(recipe.whiteBalance.temperature) else {
                    throw FujiShootingError.invalidCombination("The WB bracket exceeds the recipe temperature range.")
                }
                return (recipe, "WB BKT \(offset) · one source")
            }
        default: return [(request.recipe, request.recipe.name)]
        }
    }

    private func originalRecord(dataIsRAW: Bool, request: FujiSequenceRequest, recipe: FilmRecipe, capturedAt: Date,
                                step: FujiCaptureStep, exposure: FujiExposure?, label: String) -> FujiOriginalRecord {
        FujiOriginalRecord(id: UUID(), capturedAt: capturedAt, isRAW: dataIsRAW, sourceFilename: dataIsRAW ? "source.dng" : "source.jpg",
            sequenceID: request.id, dynamicRange: step.dynamicRange,
            captureExposure: exposure.map { FujiExposureRecord(iso: $0.iso, seconds: $0.seconds, bracketOffset: step.exposureOffset,
                                                               protectedStops: step.dynamicRange.protectionStops) },
            recipe: recipe, adjustment: .init(), cropFactor: request.settings.digitalCrop,
            viewportWidth: request.viewport.width, viewportHeight: request.viewport.height, label: label)
    }

    func export(_ data: Data, recipe: FilmRecipe, capturedAt: Date, label: String, photoLibrary: any PhotoSaving,
                didPersist: () -> Void = {}) async throws {
        let pending = try await library.enqueue(data, recipe: recipe, capturedAt: capturedAt, label: label)
        pendingExportCount += 1
        didPersist()
        try Task.checkCancellation()
        try await savePending(pending, data: data, photoLibrary: photoLibrary)
    }

    private func savePending(_ pending: FujiPendingExport, data: Data, photoLibrary: any PhotoSaving) async throws {
        // PhotoLibraryService receives the full JPEG bytes; its UIImage is only
        // a display/metadata companion, never a second full-size decode here.
        let thumbnail = try await Task.detached(priority: .utility) {
            guard let source = CIImage(data: data) else { throw FujiShootingError.processingFailed }
            return try FujiImageProcessor.thumbnail(source, edge: 512)
        }.value
        let image = UIImage(cgImage: thumbnail.image)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            photoLibrary.save(image: image, imageData: data, recipe: pending.recipe, capturedAt: pending.capturedAt) {
                continuation.resume(with: $0.mapError { $0 as Error })
            }
        }
        try await library.markExported(pending)
        pendingExportCount = max(0, pendingExportCount - 1)
    }

    func retryExports(photoLibrary: any PhotoSaving) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; status = "Retrying Photos exports…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let pending = try await library.pendingExports()
                for record in pending {
                    try Task.checkCancellation()
                    let data = try await library.exportData(record)
                    try await savePending(record, data: data, photoLibrary: photoLibrary)
                }
                status = "Pending exports saved."
            } catch { errorMessage = error.localizedDescription }
            finishActivity(); await reloadLibrary()
        }
    }

    func cancel() {
        task?.cancel()
        developmentTask?.cancel()
        camera?.cancelFujiCapture()
        clearMultiple()
        sampler.reset()
        // Actor serialization ensures an in-flight append finishes before reset.
        Task { await worker.reset() }
        if isBusy { status = "Canceling and restoring sensor controls…" }
    }

    private func clearMultiple() {
        multipleRequest = nil; multipleDeviceID = nil; multipleCapturedAt = nil
        multipleCount = 0; ghostImage = nil
    }

    private func keepScreenAwake() {
        if idleTimerWasDisabled == nil { idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func finishActivity() {
        isBusy = false; task = nil
        if let previous = idleTimerWasDisabled { UIApplication.shared.isIdleTimerDisabled = previous; idleTimerWasDisabled = nil }
        refreshPreview()
    }

    func reloadLibrary() async {
        do { originals = try await library.originals(); pendingExportCount = try await library.pendingExports().count }
        catch { errorMessage = "The capture library could not be read: \(error.localizedDescription)" }
    }

    func importRAW(_ url: URL, recipe: FilmRecipe) async throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= FujiCaptureLibrary.maximumImportBytes else {
                throw FujiShootingError.invalidCombination("Choose a supported RAW file smaller than 200 MB.")
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard FujiImageProcessor.isRAW(data) else { throw FujiShootingError.unsupportedRAW }
            _ = try FujiImageProcessor.decoded(data, isRAW: true, dynamicRange: .dr100, maximumEdge: 800)
            return data
        }.value
        let type = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) }
        let sourceExtension = type.flatMap { UTType($0 as String)?.preferredFilenameExtension }?.lowercased() ?? "raw"
        let safeExtension = FujiOriginalRecord.rawExtensions.contains(sourceExtension) ? sourceExtension : "raw"
        let record = FujiOriginalRecord(id: UUID(), capturedAt: Date(), isRAW: true, sourceFilename: "source.\(safeExtension)", sequenceID: UUID(),
            dynamicRange: .dr100, captureExposure: nil, recipe: recipe, adjustment: .init(), cropFactor: 1,
            viewportWidth: 0, viewportHeight: 0, label: "Imported RAW · \(url.lastPathComponent)")
        try await library.retainOriginal(data, record: record)
        await reloadLibrary()
    }

    func developPreview(_ record: FujiOriginalRecord) async throws -> Data {
        try Task.checkCancellation()
        let data = try await library.originalData(record)
        try Task.checkCancellation()
        return try await previewWorker.develop(data: data, record: record, maximumEdge: 1200).data
    }

    func saveDevelopment(_ record: FujiOriginalRecord, photoLibrary: any PhotoSaving) async throws {
        guard !settingsLocked else { throw FujiShootingError.busy }
        isBusy = true; status = "Developing original…"; errorMessage = nil
        keepScreenAwake()
        defer { developmentTask = nil; finishActivity() }
        let operation = Task { @MainActor in
            try Task.checkCancellation()
            try await library.updateOriginal(record)
            let data = try await library.originalData(record)
            try Task.checkCancellation()
            let developmentWorker = FujiDevelopmentWorker()
            let result = try await developmentWorker.develop(data: data, record: record)
            try Task.checkCancellation()
            try await export(result.data, recipe: record.recipe, capturedAt: record.capturedAt,
                             label: "RAW development", photoLibrary: photoLibrary)
            status = "Development saved. Original unchanged."
            await reloadLibrary()
        }
        developmentTask = operation
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: { operation.cancel() }
    }

    func originalURL(_ record: FujiOriginalRecord) async throws -> URL { try await library.originalURL(record) }
    func deleteOriginal(_ record: FujiOriginalRecord) async throws { try await library.removeOriginal(id: record.id); await reloadLibrary() }
}
