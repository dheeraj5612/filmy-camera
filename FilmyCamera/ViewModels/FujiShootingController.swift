import Combine
@preconcurrency import CoreImage
import Foundation
import UIKit

struct FujiBankHardware: Codable, Equatable, Sendable {
    var deviceID: String?
    var zoom: Double
    var flash: Int
    var exposureManual: Bool
    var iso: Double
    var duration: Double
    var whiteBalanceManual: Bool
    var kelvin: Double
    var tint: Double
    var focusManual: Bool
    var focus: Double
    var bias: Float
    var timer: Int
    var aspect: String
    var finish: String
}

struct FujiShootingBank: Codable, Identifiable, Sendable {
    let id: Int
    var name: String
    var settings: FujiShootingSettings?
    var recipe: FilmRecipe?
    var hardware: FujiBankHardware?
    static var empty: [Self] { (1...7).map { .init(id: $0, name: "C\($0)") } }
}

private struct FujiPreferenceEnvelope: Codable {
    var version = 1
    var settings = FujiShootingSettings()
    var banks = FujiShootingBank.empty
}

@MainActor
final class FujiShootingController: ObservableObject {
    @Published var settings = FujiShootingSettings() {
        didSet {
            if settings != settings.validated() { settings = settings.validated() }
            if oldValue.drive != settings.drive || oldValue.enabled != settings.enabled { clearPreview() }
            if oldValue.activeAutoISO != nil && settings.activeAutoISO == nil { camera?.setAutoExposure() }
            persist()
        }
    }
    @Published private(set) var banks = FujiShootingBank.empty
    @Published private(set) var selectedBank: Int?
    @Published private(set) var isBusy = false
    @Published private(set) var status = ""
    @Published var errorMessage: String?
    @Published private(set) var capabilities: FujiDeviceSnapshot?
    @Published private(set) var preview: FujiPreviewSample?
    @Published private(set) var focusReference: UIImage?
    @Published private(set) var multiplePreview: UIImage?
    @Published private(set) var multipleCount = 0
    @Published private(set) var storedPhotos: [FujiStoredPhoto] = []
    @Published private(set) var autoISOWarning: String?
    private let worker = FujiPreviewWorker()
    private let defaults: UserDefaults
    private weak var camera: CameraService?
    private weak var viewModel: CameraViewModel?
    private var frameToken: UUID?
    private var observationGeneration: UInt64 = 0
    private var task: Task<Void, Never>?
    private var autoISOTask: Task<Void, Never>?
    private var leaseID: UUID?
    private var multipleRecords: [FujiStoredPhoto] = []
    private var multipleSettings: FujiShootingSettings?
    private var loadingPreferences = true
    private let preferenceKey = "fuji.shooting.v1"
    var locksSettings: Bool { isBusy || multipleCount > 0 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: preferenceKey) {
            if data.count <= 1_000_000, let saved = try? JSONDecoder().decode(FujiPreferenceEnvelope.self, from: data), saved.version == 1 {
                settings = saved.settings.validated()
                banks = (1...7).map { index in saved.banks.first { $0.id == index } ?? .init(id: index, name: "C\(index)") }
            } else {
                defaults.set(data, forKey: preferenceKey + ".unreadable-backup")
                errorMessage = "Saved shooting settings could not be read. A backup was retained; safe defaults are active."
            }
        }
        loadingPreferences = false
    }

    private func persist() {
        guard !loadingPreferences else { return }
        do { defaults.set(try JSONEncoder().encode(FujiPreferenceEnvelope(settings: settings, banks: banks)), forKey: preferenceKey) }
        catch { errorMessage = "Shooting settings could not be saved." }
    }

    func attach(camera: CameraService, viewModel: CameraViewModel) {
        guard frameToken == nil else { return }
        self.camera = camera
        self.viewModel = viewModel
        observationGeneration &+= 1
        let generation = observationGeneration
        frameToken = camera.installFrameHandler { [weak self, weak viewModel] image in
            MainActor.assumeIsolated {
                guard let self, let viewModel, self.settings.enabled,
                      self.observationGeneration == generation else { return }
                let controls = self.settings
                guard controls.drive == .preShot || controls.drive == .computationalND
                    || controls.viewfinder == .hybrid || controls.focusAssist != .off else { return }
                self.worker.submit(image, settings: controls, recipe: viewModel.selectedRecipe) { [weak self] sample in
                    guard let self, self.observationGeneration == generation, self.settings.enabled else { return }
                    self.preview = sample
                }
            }
        }
        autoISOTask = Task { [weak self, weak camera] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                guard let self, let camera else { return }
                if !self.isBusy, self.multipleCount == 0, let profile = self.settings.activeAutoISO {
                    self.autoISOWarning = await camera.updateFujiAutoISO(profile)
                }
            }
        }
        Task { await refreshCapabilities(); await refreshLibrary() }
    }

    func detach() {
        cancel()
        if let frameToken { camera?.removeFrameHandler(frameToken) }
        frameToken = nil
        observationGeneration &+= 1
        autoISOTask?.cancel()
        autoISOTask = nil
        clearPreview()
    }

    func clearPreview() {
        worker.clear()
        preview = nil
        focusReference = nil
    }

    func refreshCapabilities() async {
        clearPreview()
        capabilities = try? await camera?.fujiSnapshot()
    }

    func refreshLibrary() async {
        do { storedPhotos = try await FujiDevelopmentLibrary.shared.list() }
        catch { errorMessage = "The development library could not be read: \(error.localizedDescription)" }
    }

    func freezeFocusReference() { focusReference = preview?.live }

    func saveBank(_ id: Int, name: String, camera: CameraService, viewModel: CameraViewModel) {
        guard !locksSettings, (1...7).contains(id) else { return }
        let manual = camera.manualControls
        let hardware = FujiBankHardware(deviceID: manual.activeDeviceID, zoom: Double(camera.zoomFactor), flash: camera.flashMode.rawValue,
            exposureManual: manual.exposureMode == .manual, iso: Double(manual.iso), duration: manual.exposureDurationSeconds,
            whiteBalanceManual: manual.whiteBalanceMode == .manual, kelvin: Double(manual.kelvin), tint: Double(manual.tint),
            focusManual: manual.focusMode == .manual, focus: Double(manual.lensPosition), bias: camera.exposureBias,
            timer: defaults.integer(forKey: "captureDelay"), aspect: defaults.string(forKey: "captureAspect") ?? "viewfinder",
            finish: defaults.string(forKey: "captureFinish") ?? "photo")
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        banks[id - 1] = FujiShootingBank(id: id, name: title.isEmpty ? "C\(id)" : title,
                                       settings: settings, recipe: viewModel.selectedRecipe, hardware: hardware)
        selectedBank = id
        persist()
        status = "Saved C\(id)"
    }

    func recallBank(_ id: Int, camera: CameraService, viewModel: CameraViewModel) {
        guard !locksSettings, banks.indices.contains(id - 1), let controls = banks[id - 1].settings,
              let recipe = banks[id - 1].recipe, let hardware = banks[id - 1].hardware else { return }
        guard hardware.deviceID == camera.manualControls.activeDeviceID else {
            errorMessage = "C\(id) was saved on another lens. Select that lens in Manual controls, then recall the bank. Nothing was changed."
            return
        }
        settings = controls.validated()
        viewModel.update(recipe: recipe)
        viewModel.select(recipe: recipe)
        camera.setZoom(CGFloat(hardware.zoom))
        if hardware.exposureManual { camera.setManualExposure(iso: Float(hardware.iso), durationSeconds: hardware.duration) }
        else { camera.setAutoExposure(); camera.setExposureBias(hardware.bias) }
        if hardware.whiteBalanceManual { camera.setManualWhiteBalance(kelvin: Float(hardware.kelvin), tint: Float(hardware.tint)) }
        else { camera.setAutoWhiteBalance() }
        if hardware.focusManual { camera.setManualFocus(lensPosition: Float(hardware.focus)) } else { camera.setAutoFocus() }
        camera.setFlashMode(CameraService.FlashMode(rawValue: hardware.flash) ?? .off)
        defaults.set(hardware.timer, forKey: "captureDelay")
        defaults.set(hardware.aspect, forKey: "captureAspect")
        defaults.set(hardware.finish, forKey: "captureFinish")
        selectedBank = id
        status = "Recalled C\(id)"
    }

    func bankIsModified(recipe: FilmRecipe) -> Bool {
        guard let selectedBank, banks.indices.contains(selectedBank - 1) else { return false }
        return banks[selectedBank - 1].settings != settings || banks[selectedBank - 1].recipe != recipe
    }

    func copyBank(from source: Int, to target: Int) {
        guard !locksSettings, (1...7).contains(source), (1...7).contains(target) else { return }
        let original = banks[source - 1]
        banks[target - 1] = FujiShootingBank(id: target, name: "C\(target) · \(original.name)", settings: original.settings,
                                           recipe: original.recipe, hardware: original.hardware)
        persist()
    }

    func capture(camera: CameraService, viewModel: CameraViewModel, photoLibrary: PhotoLibraryService, aspectRatio: Double?) {
        guard !isBusy, settings.enabled else { return }
        let controls = (multipleSettings ?? settings).validated()
        let recipe = multipleRecords.first?.recipe ?? viewModel.selectedRecipe
        let recipes = controls.filmRecipeIDs.compactMap { id in viewModel.recipes.first { $0.id == id }.map { viewModel.recipe(for: $0.id) } }
        isBusy = true
        errorMessage = nil
        task = Task {
            var records: [FujiStoredPhoto] = []
            let group = multipleRecords.first?.groupID ?? UUID()
            do {
                if controls.drive == .computationalND && controls.needsRAW {
                    throw FujiCaptureError.unavailable("Computational ND averages preview frames. Select DR100 and turn RAW off for this mode.")
                }
                if controls.drive == .filmBracket && (recipes.count < 2 || recipes.count != controls.filmRecipeIDs.count) {
                    throw FujiCaptureError.unavailable("Select two or three available bracketing recipes in Q > Film BKT.")
                }
                var preFrames: [FujiSourceFrame] = []
                if controls.drive == .preShot {
                    preFrames = try await worker.takePreShot(seconds: controls.preShotSeconds, count: controls.preShotCount,
                                                           deviceID: camera.manualControls.activeDeviceID ?? "unknown")
                }
                let lease = try await camera.beginFujiCapture(settings: controls)
                leaseID = lease.id
                if controls.drive == .computationalND {
                    status = "Averaging live frames. Keep the camera steady."
                    await worker.beginAverage()
                    try await Task.sleep(for: .seconds(controls.ndSeconds))
                    let source = try await worker.finishAverage(deviceID: lease.snapshot.deviceID)
                    records.append(try await store(source, recipe: recipe, group: group, controls: controls, aspect: aspectRatio))
                } else {
                    let steps = FujiCapturePlanner.steps(for: controls)
                    for (index, step) in steps.enumerated() {
                        try Task.checkCancellation()
                        if step.delayBefore > 0 { try await Task.sleep(for: .seconds(step.delayBefore)) }
                        status = "Capturing \(index + 1) of \(steps.count)"
                        let frame = try await camera.captureFujiFrame(lease: lease.id, step: step)
                        records.append(try await store(frame, recipe: recipe, group: group, controls: controls, aspect: aspectRatio))
                    }
                }
                await camera.endFujiCapture(lease: lease.id)
                leaseID = nil
                try Task.checkCancellation()
                for frame in preFrames {
                    records.append(try await store(frame, recipe: recipe, group: group, controls: controls, aspect: aspectRatio))
                }
                if controls.drive == .multipleExposure {
                    multipleSettings = controls
                    multipleRecords.append(contentsOf: records)
                    multipleCount = multipleRecords.count
                    if let last = records.last {
                        let frame = try await FujiDevelopmentLibrary.shared.frame(for: last)
                        let developed = try await FujiWork.run {
                            try FujiDevelopmentPipeline.develop(frame, recipe: recipe, cropFactor: controls.cropFactor,
                                                               aspectRatio: aspectRatio, longEdge: 700)
                        }
                        multiplePreview = developed.image
                    }
                    if multipleCount < controls.multipleExposureCount {
                        status = "Multiple exposure \(multipleCount)/\(controls.multipleExposureCount). Recompose and press the shutter."
                    } else {
                        let merged = try await merge(records: multipleRecords, focus: false, mode: controls.multipleExposureBlend)
                        let record = try await store(merged, recipe: recipe, group: group, controls: controls, aspect: aspectRatio)
                        try await export(record, photoLibrary: photoLibrary)
                        resetMultiple()
                        status = "Multiple exposure saved. Originals retained."
                    }
                } else if controls.drive == .focusStack {
                    status = "Merging focus planes. Originals retained."
                    let merged = try await merge(records: records, focus: true, mode: .average)
                    let record = try await store(merged, recipe: recipe, group: group, controls: controls, aspect: aspectRatio)
                    try await export(record, photoLibrary: photoLibrary)
                    status = "Focus stack saved. \(records.count) originals retained."
                } else if controls.drive == .filmBracket || controls.drive == .whiteBalanceBracket, let first = records.first {
                    let original = try await FujiDevelopmentLibrary.shared.frame(for: first)
                    if controls.drive == .filmBracket {
                        for selected in recipes {
                            let record = try await store(original, recipe: selected, group: group, controls: controls, aspect: aspectRatio)
                            try await export(record, photoLibrary: photoLibrary)
                        }
                    } else {
                        for offset in [-controls.whiteBalanceStep, 0, controls.whiteBalanceStep] {
                            var record = try await store(original, recipe: recipe, group: group, controls: controls, aspect: aspectRatio)
                            record.adjustments.temperature = min(max(lease.snapshot.kelvin + offset, 2500), 10000)
                            try await FujiDevelopmentLibrary.shared.update(record)
                            try await export(record, photoLibrary: photoLibrary)
                        }
                    }
                    status = "Bracket saved from one original."
                } else {
                    for record in records { try Task.checkCancellation(); try await export(record, photoLibrary: photoLibrary) }
                    status = "Saved \(records.count) frame\(records.count == 1 ? "" : "s"). Originals retained."
                    if controls.drive == .preShot && preFrames.isEmpty { status += " No recent pre-shot frames were available." }
                }
            } catch {
                if let id = leaseID {
                    camera.cancelFujiCapture(lease: id)
                    // A timed-out hardware callback cannot be safely reused.
                    if (error as? FujiCaptureError) == .timedOut { camera.stop() }
                    await camera.endFujiCapture(lease: id)
                    leaseID = nil
                }
                if Task.isCancelled { resetMultiple() }
                errorMessage = error is CancellationError ? "Shooting canceled. Completed originals remain in RAW development." : error.localizedDescription
                status = "Originals are retained in Q > RAW development."
            }
            isBusy = false
            task = nil
            await refreshLibrary()
        }
    }

    private func store(_ frame: FujiSourceFrame, recipe: FilmRecipe, group: UUID, controls: FujiShootingSettings,
                       aspect: Double?) async throws -> FujiStoredPhoto {
        var record = try await FujiDevelopmentLibrary.shared.store(frame, recipe: recipe, groupID: group, crop: controls.cropFactor, aspect: aspect)
        record.finish = PhotoFinish(rawValue: defaults.string(forKey: "captureFinish") ?? "") ?? .photo
        try await FujiDevelopmentLibrary.shared.update(record)
        return record
    }

    func export(_ record: FujiStoredPhoto, photoLibrary: PhotoLibraryService) async throws {
        status = "Developing \(record.recipe.name)"
        let frame = try await FujiDevelopmentLibrary.shared.frame(for: record)
        let developed = try await FujiWork.run {
            try FujiDevelopmentPipeline.develop(frame, recipe: record.recipe, adjustments: record.adjustments,
                                               cropFactor: record.cropFactor, aspectRatio: record.aspectRatio, finish: record.finish)
        }
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            photoLibrary.save(image: developed.image, imageData: developed.data, recipe: record.recipe, capturedAt: record.metadata.capturedAt) {
                switch $0 {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        var saved = record
        saved.exportedToPhotos = true
        try await FujiDevelopmentLibrary.shared.update(saved)
    }

    private func merge(records: [FujiStoredPhoto], focus: Bool, mode: FujiMultipleExposureBlend) async throws -> FujiSourceFrame {
        try await FujiWork.run {
            var combined: CIImage?
            var sharpest: CIImage?
            for (index, record) in records.enumerated() {
                try Task.checkCancellation()
                let frame = try await FujiDevelopmentLibrary.shared.frame(for: record)
                let image = try FujiDevelopmentPipeline.bounded(FujiDevelopmentPipeline.decode(frame), longEdge: FujiLimits.compositeLongEdge)
                if let previous = combined {
                    if focus {
                        let pair = try FujiDevelopmentPipeline.mergeFocusPair(previous, next: image, sharpest: sharpest!)
                        combined = pair.0
                        sharpest = pair.1
                    } else {
                        combined = try FujiDevelopmentPipeline.blend(previous, image, count: index, mode: mode)
                    }
                } else {
                    combined = try FujiDevelopmentPipeline.materializeLinear(image)
                    if focus { sharpest = try FujiDevelopmentPipeline.materializeLinear(FujiDevelopmentPipeline.sharpnessMask(image)) }
                }
            }
            guard let combined, let first = records.first else { throw FujiCaptureError.invalidImage }
            var metadata = first.metadata
            metadata.sourceKind = .composite
            metadata.dynamicRange = .dr100
            metadata.temporalFrameCount = records.count
            return try FujiDevelopmentPipeline.encodeSource(combined, metadata: metadata)
        }
    }

    func retakeMultiple() {
        guard !isBusy, !multipleRecords.isEmpty else { return }
        multipleRecords.removeLast()
        multipleCount = multipleRecords.count
        multiplePreview = nil
        if multipleCount == 0 { resetMultiple() }
        status = "Last exposure removed from the blend; its original is still retained."
    }

    func cancel() {
        task?.cancel()
        if let leaseID { camera?.cancelFujiCapture(lease: leaseID) }
        worker.clear()
        if !isBusy { resetMultiple(); status = "Shooting canceled. Originals retained." }
    }

    private func resetMultiple() {
        multipleRecords = []
        multipleSettings = nil
        multipleCount = 0
        multiplePreview = nil
    }
}
