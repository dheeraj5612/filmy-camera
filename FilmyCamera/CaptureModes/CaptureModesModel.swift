@preconcurrency import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class CaptureModesModel: ObservableObject {
    @Published var state = CaptureModesState()
    @Published var requestedMode: CaptureMode
    @Published var wantsMicrophone = true
    @Published var requestingPermission = false
    @Published var captures: [CaptureMedia] = []
    @Published var errorMessage: String?
    @Published var analysis: CaptureSceneAnalysis?
    @Published var exporting = false
    @Published var interactionAllowed = true
    private var foreground = false
    private var permissionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var requestID = UUID()
    let recipes: [FilmRecipe]
    private let launchRecipe: FilmRecipe

    lazy var engine: CaptureModesEngine = {
        CaptureModesEngine(recipe: launchRecipe, recipes: recipes) { [weak self] event in
            Task { @MainActor [weak self] in self?.receive(event) }
        }
    }()

    init(recipe: FilmRecipe, recipes: [FilmRecipe], mode: CaptureMode) {
        launchRecipe = recipe
        self.recipes = recipes.isEmpty ? [recipe] : recipes
        requestedMode = mode
        state.mode = mode
    }

    var canShoot: Bool {
        foreground && interactionAllowed && !requestingPermission && !exporting
            && [.ready, .capturing, .recording].contains(state.phase)
    }
    var canConfigure: Bool { foreground && !requestingPermission && !state.phase.isBusy && !exporting }
    var canClose: Bool { !requestingPermission && !state.phase.isBusy && !exporting }

    func activate() {
        foreground = true
        engine.setControlsAllowed(interactionAllowed)
        refresh()
        open(requestedMode, resuming: true)
    }

    func open(_ mode: CaptureMode, resuming: Bool = false) {
        guard foreground, (resuming || !state.phase.isBusy), !requestingPermission else { return }
        requestedMode = mode
        requestingPermission = true
        let id = UUID()
        requestID = id
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { requestingPermission = false } }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            var cameraAllowed = status == .authorized
            if status == .notDetermined { cameraAllowed = await AVCaptureDevice.requestAccess(for: .video) }
            guard !Task.isCancelled, foreground, requestID == id else { return }
            guard cameraAllowed else {
                state.phase = .unavailable
                state.message = "Enable Camera access in Settings to use capture modes."
                return
            }
            var audioAllowed = false
            if mode.isVideo, wantsMicrophone {
                let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                audioAllowed = audioStatus == .authorized
                if audioStatus == .notDetermined { audioAllowed = await AVCaptureDevice.requestAccess(for: .audio) }
            }
            guard !Task.isCancelled, foreground, requestID == id else { return }
            if mode.isVideo, wantsMicrophone, !audioAllowed {
                errorMessage = "Microphone access is disabled. Video will record silently; enable Microphone access in Settings to include audio."
            }
            updateOrientation()
            engine.configure(mode: mode, microphone: audioAllowed)
        }
    }

    func deactivate() {
        foreground = false
        requestID = UUID()
        requestingPermission = false
        permissionTask?.cancel()
        engine.pause()
    }

    func close() async {
        foreground = false
        permissionTask?.cancel()
        requestID = UUID()
        requestingPermission = false
        await engine.shutdown()
    }

    func updateOrientation() {
        let orientation = UIDevice.current.orientation
        let angle: CGFloat? = orientation == .landscapeLeft ? 0 : orientation == .landscapeRight ? 180 : nil
        engine.setSpatialAngle(angle)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let interfaceOrientation: UIInterfaceOrientation?
        if #available(iOS 26.0, *) {
            interfaceOrientation = scene?.effectiveGeometry.interfaceOrientation
        } else {
            interfaceOrientation = scene?.interfaceOrientation
        }
        let viewSize = scene?.screen.bounds.size ?? .zero
        engine.setRotationAngle(CameraService.videoRotationAngle(for: interfaceOrientation, fallbackViewSize: viewSize))
    }

    func setInteractionAllowed(_ allowed: Bool) {
        interactionAllowed = allowed
        engine.setControlsAllowed(allowed && foreground)
    }

    func shutter() { if canShoot { engine.shutter() } }
    func beginBurstHold() { if canShoot, state.mode == .burst, state.phase == .ready { engine.shutter() } }
    func endBurstHold() { engine.stopSequenceCapture() }

    func hardwareEvent(_ phase: Int) {
        guard canShoot else { return }
        if state.mode == .burst {
            if phase == 0 { beginBurstHold() }
            else { endBurstHold() }
        } else if phase == 1 { shutter() }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do {
                let records = try await Task.detached(priority: .utility) { try CaptureMediaStore.recent() }.value
                guard !Task.isCancelled else { return }
                self?.captures = records
            } catch { self?.errorMessage = error.localizedDescription }
        }
    }

    func export(_ media: CaptureMedia) {
        guard !exporting, !state.phase.isBusy else { return }
        exporting = true
        Task { [weak self] in
            guard let self else { return }
            defer { exporting = false; refresh() }
            do { _ = try await CaptureMediaStore.exportToPhotos(media) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func receive(_ event: CaptureModesEvent) {
        switch event {
        case .state(let value):
            state = value
        case .saved:
            refresh()
        case .failed(let message):
            errorMessage = message
            refresh()
        case .analysis(let value):
            if foreground { analysis = value }
        case .requestedMode(let mode):
            open(mode)
        }
    }
}
