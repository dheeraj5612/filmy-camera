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
    @State private var showingFilmPicker = false
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(camera: CameraService, recipe: FilmRecipe, recipes: [FilmRecipe], mode: CaptureMode, onClose: @escaping () -> Void) {
        self.camera = camera
        self.onClose = onClose
        _model = StateObject(wrappedValue: CaptureModesModel(recipe: recipe, recipes: recipes, mode: mode))
    }

    private var interactionBlocked: Bool {
        showingCaptures || showingReferencePicker || showingFilmPicker || referenceBusy || model.analysis != nil
            || model.errorMessage != nil || model.requestingPermission || closing
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    page(geometry)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                // Controls stay reachable when the page is taller than the viewport.
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("capture-modes-scroll")
            }
            .background(.black)
            .foregroundStyle(.white)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { shutterBar }
            .photosPicker(isPresented: $showingReferencePicker, selection: $referenceItem, matching: .images,
                          preferredItemEncoding: .current)
            .sheet(isPresented: $showingCaptures) { CaptureModesLibrary(model: model) }
            .sheet(isPresented: $showingFilmPicker) {
                CaptureFilmPicker(recipes: model.recipes, currentName: model.state.recipeName, canSelect: model.canConfigure) { index in
                    model.engine.selectRecipe(index)
                }
            }
            .sheet(isPresented: Binding(get: { model.analysis != nil }, set: { if !$0 { model.analysis = nil } })) {
                if let analysis = model.analysis { CaptureSceneResults(analysis: analysis) }
            }
            .alert("Capture modes", isPresented: Binding(get: { model.errorMessage != nil },
                                                         set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
                // Only permission errors, which all name Settings, can be fixed there.
                if model.errorMessage?.contains("Settings") == true {
                    Button("Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            } message: { Text(model.errorMessage ?? "") }
            .onChange(of: interactionBlocked) { _, blocked in model.setInteractionAllowed(!blocked) }
            .onChange(of: referenceItem) { _, item in
                guard let item else { return }
                referenceItem = nil
                importReference(item)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, releasedLegacyCamera {
                    model.activate(); consumeLaunch()
                    updateIdleTimer(sceneActive: true)
                } else if phase != .active {
                    UIApplication.shared.isIdleTimerDisabled = false
                    model.deactivate(); cancelReference()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in model.updateOrientation() }
            .onReceive(NotificationCenter.default.publisher(for: CaptureModesLaunch.notification)) { _ in consumeLaunch() }
            .onChange(of: model.state.phase) { old, phase in
                updateIdleTimer(sceneActive: scenePhase == .active)
                if phase == .ready { consumeLaunch() }
                announcePhase(from: old, to: phase)
            }
            .task {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                // No fixed delay, polling, or competing session starts.
                await camera.suspendForCaptureModes()
                guard !Task.isCancelled else { return }
                releasedLegacyCamera = true
                if let requested = CaptureModesLaunch.take() { model.requestedMode = requested }
                if UIApplication.shared.applicationState == .active { model.activate() }
                updateIdleTimer(sceneActive: UIApplication.shared.applicationState == .active)
                loadReference()
            }
            .onDisappear {
                model.deactivate()
                cancelReference()
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }.preferredColorScheme(.dark)
    }

    private var pageScrolls: Bool { dynamicTypeSize.isAccessibilitySize }

    private func page(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            sizedViewfinder(geometry)
            statusBlock
            modePicker
            captureOptions
            referenceOptions
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// Fills spare height with a 200 pt floor; at accessibility text sizes the page scrolls around a fixed viewfinder.
    private func sizedViewfinder(_ geometry: GeometryProxy) -> some View {
        // One frame for both modes keeps the preview's identity stable when text size crosses the threshold.
        let fixedHeight: CGFloat = max(240, geometry.size.height * 0.53)
        let minHeight: CGFloat = pageScrolls ? fixedHeight : 200
        let maxHeight: CGFloat = pageScrolls ? fixedHeight : .infinity
        return viewfinder.frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: maxHeight)
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.state.message).font(.subheadline)
            if let warning = model.state.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
            if let note = filmLookNote {
                Text(note).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("capture-modes-film-note")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A 44 pt bar without a title: the mode is already named by the mode chips and the shutter bar.
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                backButton
                Spacer(minLength: 8)
                capturesButton
            }
            VStack(alignment: .leading, spacing: 8) {
                backButton
                capturesButton
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture modes")
    }

    private var backDisabled: Bool { !releasedLegacyCamera || !model.canClose || closing }

    private var backButton: some View {
        let handingOff = !releasedLegacyCamera || closing
        return Button {
            closing = true
            Task {
                await model.close()
                UIApplication.shared.isIdleTimerDisabled = false
                onClose()
            }
        } label: {
            Label {
                Text("Back")
            } icon: {
                if handingOff { ProgressView().controlSize(.small) } else { Image(systemName: "chevron.left") }
            }
            .modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .disabled(backDisabled)
        .accessibilityLabel("Back")
        .accessibilityHint(releasedLegacyCamera ? "" : "Getting the camera ready")
        .accessibilityIdentifier("capture-modes-back")
    }

    private var capturesDisabled: Bool { model.state.phase.isBusy || model.requestingPermission }

    private var capturesButton: some View {
        Button { model.refresh(); showingCaptures = true } label: {
            Label("Captures", systemImage: "photo.on.rectangle")
                .modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .disabled(capturesDisabled)
        .accessibilityIdentifier("open-mode-captures")
    }

    private var viewfinder: some View {
        HStack(spacing: referenceSplit && referenceImage != nil ? 8 : 0) {
            // The preview is the sizing base: reference images are overlays so their aspect-fit height
            // never inflates the flexible viewfinder.
            CaptureModesPreview(session: model.engine.session, enabled: model.canShoot,
                                focus: model.engine.focus, hardware: model.hardwareEvent)
                .overlay { referenceOverlay }
                .overlay { preparingOverlay }
                .clipped()
            if let referenceImage, referenceSplit {
                Color.clear
                    .overlay {
                        Image(uiImage: referenceImage).resizable().scaledToFit()
                            .scaleEffect(x: referenceMirror ? -1 : 1, y: 1)
                            .accessibilityLabel("Reference image, not included in captures")
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) { if showsFilmChip { filmChip } }
        .accessibilityIdentifier("capture-modes-viewfinder")
    }

    @ViewBuilder private var referenceOverlay: some View {
        if let referenceImage, !referenceSplit {
            Image(uiImage: referenceImage).resizable().scaledToFit()
                .scaleEffect(x: referenceMirror ? -referenceScale : referenceScale, y: referenceScale)
                .opacity(min(max(referenceOpacity, 0), 1))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var preparingOverlay: some View {
        if model.state.phase == .configuring || model.requestingPermission {
            ProgressView("Preparing camera").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var showsFilmChip: Bool {
        model.state.mode == .spatialVideo || !model.state.recipeName.isEmpty
    }

    private var filmChip: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !model.state.format.isEmpty { Text(model.state.format).font(.caption.monospacedDigit()) }
            Text(model.state.mode == .spatialVideo ? "Native stereo" : "Film: \(model.state.recipeName)")
                .font(.caption.weight(.semibold)).lineLimit(2)
                .accessibilityIdentifier("capture-modes-film-chip")
            if model.state.mode.isVideo { Text(model.state.microphoneEnabled ? "Audio on" : "Silent video").font(.caption2) }
            if model.state.focusLocked { Text("AE / AF / WB locked").font(.caption2) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            modeChips
            unavailableModesNote
        }
        .opacity(model.state.controlsExpanded ? 0 : 1)
        .allowsHitTesting(!model.state.controlsExpanded)
        .accessibilityHidden(model.state.controlsExpanded)
    }

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        if model.requestedMode != mode { HapticFeedback.play(.selection) }
                        model.open(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(model.requestedMode == mode ? Color.white.opacity(0.22) : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canConfigure || !CaptureModesEngine.supportedModes.contains(mode))
                    .accessibilityIdentifier("capture-mode-\(mode.rawValue)")
                    .accessibilityAddTraits(model.requestedMode == mode ? .isSelected : [])
                    .accessibilityHint(unavailableHint(for: mode))
                }
            }
        }
    }

    private var unavailableModes: [CaptureMode] {
        CaptureMode.allCases.filter { mode in
            !CaptureModesEngine.supportedModes.contains(mode) && CaptureModesPolicy.unavailableReason(for: mode) != nil
        }
    }

    private func unavailableHint(for mode: CaptureMode) -> String {
        guard !CaptureModesEngine.supportedModes.contains(mode) else { return "" }
        return CaptureModesPolicy.unavailableReason(for: mode) ?? ""
    }

    @ViewBuilder private var unavailableModesNote: some View {
        let modes = unavailableModes
        if !modes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Not on this device").font(.footnote.weight(.semibold))
                ForEach(modes) { mode in
                    Text(CaptureModesPolicy.unavailableReason(for: mode) ?? "").font(.footnote)
                }
            }
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture-modes-unavailable-note")
        }
    }

    private var filmPickerButton: some View {
        Button { showingFilmPicker = true } label: {
            HStack(spacing: 8) {
                Label(model.state.recipeName.isEmpty ? "Choose film" : "Film: \(model.state.recipeName)", systemImage: "film")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens the film list")
        .accessibilityIdentifier("capture-modes-film-picker-open")
    }

    private var captureOptions: some View {
        DisclosureGroup("Camera and film") {
            VStack(alignment: .leading, spacing: 14) {
                if model.state.mode != .spatialVideo {
                    filmPickerButton
                    if model.state.maximumZoom > 1 {
                        Text("Zoom \(model.state.zoom, specifier: "%.1f")×").accessibilityHidden(true)
                        Slider(value: Binding(get: { model.state.zoom }, set: model.engine.setZoom), in: 1...max(1.01, model.state.maximumZoom))
                            .accessibilityLabel("Zoom")
                            .accessibilityValue(String(format: "%.1f times", model.state.zoom))
                    }
                    if model.state.maximumExposure > model.state.minimumExposure {
                        Text("Exposure \(model.state.exposure, specifier: "%+.1f") EV").accessibilityHidden(true)
                        Slider(value: Binding(get: { model.state.exposure }, set: model.engine.setExposure),
                               in: model.state.minimumExposure...model.state.maximumExposure)
                            .accessibilityLabel("Exposure compensation")
                            .accessibilityValue(String(format: "%+.1f EV", model.state.exposure))
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
                            .accessibilityValue("\(Int((referenceOpacity * 100).rounded())) percent")
                        Text("Reference scale")
                        Slider(value: $referenceScale, in: 0.5...2).accessibilityLabel("Reference scale")
                            .accessibilityValue("\(Int((referenceScale * 100).rounded())) percent")
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

    private var stoppable: Bool {
        CaptureModesPolicy.isStoppable(phase: model.state.phase, scanning: model.state.scanning)
    }

    private var filmLookNote: String? {
        CaptureModesPolicy.filmLookNote(mode: model.state.mode, showingGuidance: model.state.message == model.state.mode.guidance)
    }

    private func shutterTapped() {
        if model.canShoot, CaptureModesPolicy.playsShutterHaptic(mode: model.state.mode, phase: model.state.phase) {
            HapticFeedback.play(.capture)
        }
        model.shutter()
    }

    private func burstHoldBegan() {
        let burst = model.state.mode == .burst
        if burst, model.canShoot, CaptureModesPolicy.playsShutterHaptic(mode: model.state.mode, phase: model.state.phase) {
            HapticFeedback.play(.capture)
        }
        model.beginBurstHold()
    }

    private func updateIdleTimer(sceneActive: Bool) {
        UIApplication.shared.isIdleTimerDisabled = CaptureModesPolicy.keepsScreenAwake(
            sceneActive: sceneActive, cameraReleased: releasedLegacyCamera, closing: closing, phase: model.state.phase)
    }

    private var shutterBar: some View {
        HStack(spacing: 22) {
            VStack(spacing: 2) {
                if model.state.phase == .recording {
                    let minutes = model.state.seconds / 60
                    let remainder = model.state.seconds % 60
                    Text(String(format: "%d:%02d", minutes, remainder))
                        .accessibilityLabel("Recording time")
                        .accessibilityValue("\(minutes) minutes \(remainder) seconds")
                }
                else if model.state.phase == .capturing, !model.state.scanning {
                    Text("\(model.state.frameCount)")
                        .accessibilityLabel("Frames captured")
                        .accessibilityValue("\(model.state.frameCount)")
                }
                else { Text(model.state.mode.title).lineLimit(2) }
            }.font(.caption.monospacedDigit()).frame(maxWidth: .infinity)
            CaptureModesShutter(enabled: model.canShoot,
                canHold: model.state.mode == .burst && model.state.phase == .ready,
                isRecording: stoppable,
                label: stoppable ? "Stop capture" : "Capture \(model.state.mode.title)",
                tap: { shutterTapped() }, beginHold: { burstHoldBegan() }, endHold: model.endBurstHold)
                .frame(width: 76, height: 76)
            VStack(spacing: 4) {
                if model.state.phase == .processing {
                    ProgressView()
                    Button { model.engine.pause(reason: model.state.scanning ? "Scene reading stopped. Reopen the mode to read the scene again." : "Processing paused. Retry it from Captures.") } label: {
                        Text("Pause").font(.caption).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Pause processing")
                    .accessibilityIdentifier("capture-modes-pause-processing")
                } else if model.state.phase == .unavailable || model.state.phase == .stopped {
                    if cameraDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            Text("Open Settings").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("capture-modes-open-settings")
                    } else {
                        Button { model.open(model.requestedMode) } label: {
                            Text("Reopen mode").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("capture-modes-reopen-mode")
                    }
                } else {
                    Button { model.engine.inspectScene() } label: { Label("Read scene", systemImage: "text.viewfinder").font(.caption).multilineTextAlignment(.center)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                        .disabled(!model.canConfigure || model.state.mode.isVideo)
                        .accessibilityIdentifier("read-camera-scene")
                }
            }.frame(maxWidth: .infinity, minHeight: 44).dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.black)
    }

    private var cameraDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .denied
    }

    private func announcePhase(from old: CaptureModesPhase, to phase: CaptureModesPhase) {
        guard scenePhase == .active, !closing, old != phase, old != .configuring, model.analysis == nil else { return }
        guard phase == .recording || phase == .processing || phase == .ready || phase == .stopped || phase == .unavailable else { return }
        UIAccessibility.post(notification: .announcement, argument: model.state.message)
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

/// Capsule look shared by the top bar buttons: 44 pt minimum target, one line, no truncation.
private struct CaptureModesCapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(FilmyTheme.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .background(FilmyTheme.panel.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(FilmyTheme.lineStrong, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Searchable film list. The current film comes from the model, not screen state: the Camera Control picker can change it.
/// The current mark matches by name: CaptureModesEngine publishes only `state.recipeName` (no id or index), and
/// built-in names are unique (RecipeInvariantsTests). A screen-local picked index would desync, because
/// `selectRecipe` silently ignores picks while the engine is busy.
private struct CaptureFilmPicker: View {
    let recipes: [FilmRecipe]
    let currentName: String
    let canSelect: Bool
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var detent: PresentationDetent = .large

    private var currentIndex: Int? { recipes.firstIndex { $0.name == currentName } }

    private func rows(current: Int?) -> [(offset: Int, element: FilmRecipe)] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let matches = recipes.map { recipe -> Bool in
            if words.isEmpty { return true }
            let text = RecipeCatalog.searchText(for: recipe)
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
        return CaptureModesPolicy.filmPickerOrder(matches: matches, current: current).map { (offset: $0, element: recipes[$0]) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose film")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search films")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("capture-film-picker-done")
                    }
                }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
    }

    @ViewBuilder private var content: some View {
        let current = currentIndex
        let listed = rows(current: current)
        if listed.isEmpty {
            ContentUnavailableView("No film matches", systemImage: "magnifyingglass",
                                   description: Text("Nothing matches \(query.trimmingCharacters(in: .whitespacesAndNewlines)). Try a shorter word."))
                .accessibilityIdentifier("capture-film-picker-empty")
        } else {
            List {
                Section {
                    ForEach(listed, id: \.offset) { row in
                        filmRow(index: row.offset, recipe: row.element, isCurrent: row.offset == current)
                    }
                } header: {
                    Text(canSelect ? "Used for shots taken here." : "Film changes are unavailable right now.")
                        .font(.footnote).textCase(nil)
                }
            }
        }
    }

    private func filmRow(index: Int, recipe: FilmRecipe, isCurrent: Bool) -> some View {
        Button {
            if !isCurrent { HapticFeedback.play(.selection) }
            select(index)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).font(.body).foregroundStyle(.primary)
                if !recipe.subtitle.isEmpty { Text(recipe.subtitle).font(.footnote).foregroundStyle(.secondary) }
                if isCurrent { Label("Current", systemImage: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!canSelect)
        .accessibilityIdentifier("capture-film-\(recipe.id)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
