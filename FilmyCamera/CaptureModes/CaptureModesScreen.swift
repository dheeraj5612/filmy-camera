import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CaptureModesScreen: View {
    let camera: CameraService
    let onClose: () -> Void
    @StateObject private var model: CaptureModesModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var releasedLegacyCamera = false
    @State private var showingCaptures = false
    @State private var showingReferencePicker = false
    @State private var referenceItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?
    @State private var referenceBusy = false
    @State private var referenceTask: Task<Void, Never>?
    @State private var referenceOperation = UUID()
    @AppStorage("FilmyCaptureReferenceOpacity") private var referenceOpacity = 0.35
    @AppStorage("FilmyCaptureReferenceMirror") private var referenceMirror = false
    @AppStorage("FilmyCaptureReferenceSplit") private var referenceSplit = false
    @State private var referenceScale = 1.0
    @State private var closing = false

    init(camera: CameraService, recipe: FilmRecipe, recipes: [FilmRecipe], mode: CaptureMode, onClose: @escaping () -> Void) {
        self.camera = camera
        self.onClose = onClose
        _model = StateObject(wrappedValue: CaptureModesModel(recipe: recipe, recipes: recipes, mode: mode))
    }

    private var interactionBlocked: Bool {
        showingCaptures || showingReferencePicker || referenceBusy || model.analysis != nil
            || model.errorMessage != nil || model.requestingPermission || closing
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        viewfinder.frame(height: max(240, geometry.size.height * 0.53))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.state.message).font(.subheadline)
                            if let warning = model.state.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
                            Text("Optical preview · Film applied after capture · Originals retained")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        modePicker
                        captureOptions
                        referenceOptions
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(.black)
            .foregroundStyle(.white)
            .navigationTitle("Capture modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        closing = true
                        Task { await model.close(); onClose() }
                    }.disabled(!releasedLegacyCamera || !model.canClose || closing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Captures") { model.refresh(); showingCaptures = true }
                        .disabled(model.state.phase.isBusy || model.requestingPermission)
                        .accessibilityIdentifier("open-mode-captures")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { shutterBar }
            .photosPicker(isPresented: $showingReferencePicker, selection: $referenceItem, matching: .images,
                          preferredItemEncoding: .current)
            .sheet(isPresented: $showingCaptures) { CaptureModesLibrary(model: model) }
            .sheet(isPresented: Binding(get: { model.analysis != nil }, set: { if !$0 { model.analysis = nil } })) {
                if let analysis = model.analysis { CaptureSceneResults(analysis: analysis) }
            }
            .alert("Capture modes", isPresented: Binding(get: { model.errorMessage != nil },
                                                         set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
                Button("Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            } message: { Text(model.errorMessage ?? "") }
            .onChange(of: interactionBlocked) { _, blocked in model.setInteractionAllowed(!blocked) }
            .onChange(of: referenceItem) { _, item in
                guard let item else { return }
                referenceItem = nil
                importReference(item)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, releasedLegacyCamera { model.activate(); consumeLaunch() }
                else if phase != .active { model.deactivate(); cancelReference() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in model.updateOrientation() }
            .onReceive(NotificationCenter.default.publisher(for: CaptureModesLaunch.notification)) { _ in consumeLaunch() }
            .onChange(of: model.state.phase) { _, phase in if phase == .ready { consumeLaunch() } }
            .task {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                // No fixed delay, polling, or competing session starts.
                await camera.suspendForCaptureModes()
                guard !Task.isCancelled else { return }
                releasedLegacyCamera = true
                if let requested = CaptureModesLaunch.take() { model.requestedMode = requested }
                if UIApplication.shared.applicationState == .active { model.activate() }
                loadReference()
            }
            .onDisappear {
                model.deactivate()
                cancelReference()
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }.preferredColorScheme(.dark)
    }

    private var viewfinder: some View {
        HStack(spacing: referenceSplit && referenceImage != nil ? 8 : 0) {
            ZStack {
                CaptureModesPreview(session: model.engine.session, enabled: model.canShoot,
                                    focus: model.engine.focus, hardware: model.hardwareEvent)
                if let referenceImage, !referenceSplit {
                    Image(uiImage: referenceImage).resizable().scaledToFit()
                        .scaleEffect(x: referenceMirror ? -referenceScale : referenceScale, y: referenceScale)
                        .opacity(min(max(referenceOpacity, 0), 1))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if model.state.phase == .configuring || model.requestingPermission {
                    ProgressView("Preparing camera").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .clipped()
            if let referenceImage, referenceSplit {
                Image(uiImage: referenceImage).resizable().scaledToFit()
                    .scaleEffect(x: referenceMirror ? -1 : 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Reference image, not included in captures")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.format).font(.caption.monospacedDigit())
                Text(model.state.mode == .spatialVideo ? "Native stereo" : model.state.recipeName).font(.caption.weight(.semibold))
                if model.state.mode.isVideo { Text(model.state.microphoneEnabled ? "Audio on" : "Silent video").font(.caption2) }
                if model.state.focusLocked { Text("AE / AF / WB locked").font(.caption2) }
            }.padding(10).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10)).padding(8)
        }
        .accessibilityIdentifier("capture-modes-viewfinder")
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CaptureMode.allCases) { mode in
                    Button { model.open(mode) } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(model.requestedMode == mode ? Color.white.opacity(0.22) : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canConfigure)
                    .accessibilityIdentifier("capture-mode-\(mode.rawValue)")
                    .accessibilityAddTraits(model.requestedMode == mode ? .isSelected : [])
                }
            }
        }.opacity(model.state.controlsExpanded ? 0 : 1)
            .allowsHitTesting(!model.state.controlsExpanded)
            .accessibilityHidden(model.state.controlsExpanded)
    }

    private var captureOptions: some View {
        DisclosureGroup("Camera and film") {
            VStack(alignment: .leading, spacing: 14) {
                if model.state.mode != .spatialVideo {
                    Menu("Film: \(model.state.recipeName)") {
                        ForEach(Array(model.recipes.enumerated()), id: \.offset) { index, recipe in
                            Button(recipe.name) { model.engine.selectRecipe(index) }
                        }
                    }
                    if model.state.maximumZoom > 1 {
                        Text("Zoom \(model.state.zoom, specifier: "%.1f")×")
                        Slider(value: Binding(get: { model.state.zoom }, set: model.engine.setZoom), in: 1...max(1.01, model.state.maximumZoom))
                            .accessibilityLabel("Zoom")
                    }
                    if model.state.maximumExposure > model.state.minimumExposure {
                        Text("Exposure \(model.state.exposure, specifier: "%+.1f") EV")
                        Slider(value: Binding(get: { model.state.exposure }, set: model.engine.setExposure),
                               in: model.state.minimumExposure...model.state.maximumExposure)
                            .accessibilityLabel("Exposure compensation")
                    }
                }
                if model.requestedMode.isVideo {
                    Toggle("Record microphone audio", isOn: $model.wantsMicrophone)
                        .onChange(of: model.wantsMicrophone) { _, _ in model.open(model.requestedMode) }
                    Text("Up to three minutes per clip. Keep Filmy open while developing the film look.").font(.caption).foregroundStyle(.secondary)
                }
                if model.state.mode == .portrait {
                    Text("Depth-based center-subject bokeh at f/4. The original depth-bearing HEIC is always retained.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(model.state.controlsSupported ? "Camera Control: shutter, zoom, exposure, mode, film, and focus where supported."
                     : "On-screen controls remain available without Camera Control hardware.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 12).disabled(!model.canConfigure)
        }.tint(.white)
    }

    private var referenceOptions: some View {
        DisclosureGroup("Reference image") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use an onion-skin overlay or compare side by side. Filmy uses the reference locally and never burns it into photos or movies.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(referenceImage == nil ? "Choose a reference" : "Replace reference") { showingReferencePicker = true }
                    .disabled(!model.canConfigure || referenceBusy)
                    .accessibilityIdentifier("choose-reference-image")
                if referenceBusy {
                    HStack { ProgressView(); Button("Cancel import") { cancelReference() } }
                }
                if referenceImage != nil {
                    Toggle("Side-by-side comparison", isOn: $referenceSplit)
                    Toggle("Mirror reference", isOn: $referenceMirror)
                    if !referenceSplit {
                        Text("Overlay opacity")
                        Slider(value: $referenceOpacity, in: 0...1).accessibilityLabel("Reference opacity")
                        Text("Reference scale")
                        Slider(value: $referenceScale, in: 0.5...2).accessibilityLabel("Reference scale")
                    }
                    Button("Remove reference", role: .destructive) {
                        cancelReference()
                        do {
                            let url = try CaptureReference.url()
                            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                            referenceImage = nil
                        } catch { model.errorMessage = error.localizedDescription }
                    }
                }
            }.padding(.top, 12)
        }.tint(.white)
    }

    private var shutterBar: some View {
        HStack(spacing: 22) {
            VStack(spacing: 2) {
                if model.state.phase == .recording { Text(String(format: "%d:%02d", model.state.seconds / 60, model.state.seconds % 60)) }
                else if model.state.phase == .capturing { Text("\(model.state.frameCount)") }
                else { Text(model.state.mode.title).lineLimit(2) }
            }.font(.caption.monospacedDigit()).frame(maxWidth: .infinity)
            CaptureModesShutter(enabled: model.canShoot,
                canHold: model.state.mode == .burst && model.state.phase == .ready,
                isRecording: model.state.phase == .recording || model.state.phase == .capturing,
                label: model.state.phase == .recording || model.state.phase == .capturing ? "Stop capture" : "Capture \(model.state.mode.title)",
                tap: model.shutter, beginHold: model.beginBurstHold, endHold: model.endBurstHold)
                .frame(width: 76, height: 76)
            VStack(spacing: 4) {
                if model.state.phase == .processing {
                    ProgressView()
                    Button("Pause") { model.engine.pause(reason: "Processing paused. Retry it from Captures.") }.font(.caption)
                } else if model.state.phase == .unavailable || model.state.phase == .stopped {
                    Button("Reopen mode") { model.open(model.requestedMode) }.font(.caption)
                } else {
                    Button { model.engine.inspectScene() } label: { Label("Read scene", systemImage: "text.viewfinder").font(.caption) }
                        .disabled(!model.canConfigure || model.state.mode.isVideo)
                        .accessibilityIdentifier("read-camera-scene")
                }
            }.frame(maxWidth: .infinity)
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.black)
    }

    private func consumeLaunch() {
        guard model.canConfigure, let mode = CaptureModesLaunch.take() else { return }
        model.open(mode)
    }

    private func cancelReference() {
        referenceOperation = UUID()
        referenceTask?.cancel()
        referenceTask = nil
        referenceBusy = false
    }

    private func importReference(_ item: PhotosPickerItem) {
        cancelReference()
        let id = UUID()
        referenceOperation = id
        referenceBusy = true
        referenceTask = Task {
            defer { if referenceOperation == id { referenceBusy = false; referenceTask = nil } }
            do {
                guard let file = try await item.loadTransferable(type: CaptureReferenceFile.self) else { throw CaptureModesError.invalidImage }
                try Task.checkCancellation()
                let task = Task.detached(priority: .userInitiated) { try CaptureReference.prepare(file.data) }
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard !Task.isCancelled, referenceOperation == id else { return }
                // This small atomic write is the acceptance boundary. Cancellation
                // cannot interleave between accepting the image and updating its UI.
                try result.jpeg.write(to: CaptureReference.url(), options: .atomic)
                referenceImage = UIImage(cgImage: result.image)
                referenceScale = 1
            } catch {
                if !Task.isCancelled, referenceOperation == id { model.errorMessage = error.localizedDescription }
            }
        }
    }

    private func loadReference() {
        let id = referenceOperation
        referenceTask = Task {
            do {
                let result = try await Task.detached(priority: .utility) { try CaptureReference.load() }.value
                guard !Task.isCancelled, referenceOperation == id, let result else { return }
                referenceImage = UIImage(cgImage: result.image)
            } catch { if !Task.isCancelled { model.errorMessage = error.localizedDescription } }
        }
    }
}
