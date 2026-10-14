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
    @State private var showingModeInfo = false
    @State private var showingReferenceTray = false
    @State private var returnsFocusToReferenceChip = false
    @AccessibilityFocusState private var referenceFocus: ReferenceFocus?
    @State private var adjusting: Adjuster?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Adjuster { case zoom, exposure }
    private enum ReferenceFocus: Hashable { case header, chip }

    init(camera: CameraService, recipe: FilmRecipe, recipes: [FilmRecipe], mode: CaptureMode, onClose: @escaping () -> Void) {
        self.camera = camera
        self.onClose = onClose
        _model = StateObject(wrappedValue: CaptureModesModel(recipe: recipe, recipes: recipes, mode: mode))
    }

    private var interactionBlocked: Bool {
        showingCaptures || showingReferencePicker || showingFilmPicker || showingModeInfo || referenceBusy || model.analysis != nil
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
            .onChange(of: model.requestedMode) { _, _ in adjusting = nil }
            .onChange(of: model.canConfigure) { _, allowed in if !allowed { adjusting = nil } }
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
            if showingReferenceTray {
                referenceTray(geometry)
            } else {
                modePicker
                essentials
            }
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
            if let note = filmLookNote, !showingReferenceTray {
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
        .opacity(backDisabled ? 0.5 : 1)
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
        .opacity(capturesDisabled ? 0.5 : 1)
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
        if let summary = CaptureModesPolicy.unavailableSummary(modes) {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(unavailableNoteLabel(modes))
                .accessibilityIdentifier("capture-modes-unavailable-note")
        }
    }

    /// The summary is one line; VoiceOver still hears every reason.
    private func unavailableNoteLabel(_ modes: [CaptureMode]) -> String {
        let reasons: [String] = modes.compactMap { CaptureModesPolicy.unavailableReason(for: $0) }
        return "Not on this device. " + reasons.joined(separator: " ")
    }

    private var essentialItems: [CaptureEssential] {
        CaptureModesPolicy.essentials(
            mode: model.state.mode, requestedMode: model.requestedMode, maximumZoom: model.state.maximumZoom,
            minimumExposure: model.state.minimumExposure, maximumExposure: model.state.maximumExposure)
    }

    private var essentials: some View {
        VStack(alignment: .leading, spacing: 8) {
            if essentialItems.contains(.film) { filmPickerButton }
            if let adjuster = activeAdjuster(in: essentialItems) {
                adjustRow(adjuster)
            } else {
                chipRow(essentialItems)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.state.controlsExpanded ? 0 : 1)
        .allowsHitTesting(!model.state.controlsExpanded)
        .accessibilityHidden(model.state.controlsExpanded)
        .sheet(isPresented: $showingModeInfo) { modeInfoSheet }
    }

    private func activeAdjuster(in items: [CaptureEssential]) -> Adjuster? {
        switch adjusting {
        case .zoom?: return items.contains(.zoom) ? .zoom : nil
        case .exposure?: return items.contains(.exposure) ? .exposure : nil
        case nil: return nil
        }
    }

    private func setAdjusting(_ value: Adjuster?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { adjusting = value }
    }

    /// Opening swaps the mode chips and essentials for the tray; Reduce Motion swaps without animation.
    private func setReferenceTray(_ open: Bool) {
        if open { referenceFocus = nil } else { returnsFocusToReferenceChip = true }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            if open { adjusting = nil }
            showingReferenceTray = open
        }
    }

    private var filmPickerButton: some View {
        Button { showingFilmPicker = true } label: {
            HStack(spacing: 8) {
                Label(model.state.recipeName.isEmpty ? "Choose film" : "Film: \(model.state.recipeName)", systemImage: "film")
                    .lineLimit(pageScrolls ? 2 : 1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, pageScrolls ? 6 : 0)
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            .background(FilmyTheme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(FilmyTheme.lineStrong, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(!model.canConfigure)
        .opacity(model.canConfigure ? 1 : 0.5)
        .accessibilityHint("Opens the film list")
        .accessibilityIdentifier("capture-modes-film-picker-open")
    }

    /// Titled chips, then icon-only or value-only chips, then one chip per line: whichever fits the width without clipping.
    private func chipRow(_ items: [CaptureEssential]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips(items, compact: false) }
            HStack(spacing: 8) { chips(items, compact: true) }
            VStack(alignment: .leading, spacing: 8) { chips(items, compact: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func chips(_ items: [CaptureEssential], compact: Bool) -> some View {
        if items.contains(.zoom) { zoomChip(compact: compact) }
        if items.contains(.exposure) { exposureChip(compact: compact) }
        if items.contains(.microphone) { microphoneChip(compact: compact) }
        referenceChip(compact: compact)
        aboutChip
    }

    private func zoomChip(compact: Bool) -> some View {
        let value = String(format: "%.1f\u{00D7}", model.state.zoom)
        return Button { setAdjusting(.zoom) } label: {
            Group {
                if compact { Text(value) } else { Label(value, systemImage: "plus.magnifyingglass") }
            }
            .modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canConfigure)
        .opacity(model.canConfigure ? 1 : 0.5)
        .accessibilityLabel("Zoom")
        .accessibilityValue(String(format: "%.1f times", model.state.zoom))
        .accessibilityInputLabels(["Zoom", value])
        .accessibilityHint("Opens the zoom slider")
        .accessibilityIdentifier("capture-modes-zoom-chip")
    }

    private func exposureChip(compact: Bool) -> some View {
        let value = String(format: "%+.1f EV", model.state.exposure)
        return Button { setAdjusting(.exposure) } label: {
            Group {
                if compact { Text(value) } else { Label(value, systemImage: "plusminus.circle") }
            }
            .modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canConfigure)
        .opacity(model.canConfigure ? 1 : 0.5)
        .accessibilityLabel("Exposure")
        .accessibilityValue(value)
        .accessibilityInputLabels(["Exposure", "EV"])
        .accessibilityHint("Opens the exposure slider")
        .accessibilityIdentifier("capture-modes-exposure-chip")
    }

    /// Shows the request, as the old toggle did; the viewfinder chip says whether audio is actually on.
    private func microphoneChip(compact: Bool) -> some View {
        let wanted = model.wantsMicrophone
        let text = wanted ? "Mic on" : "Mic off"
        let symbol = wanted ? "mic" : "mic.slash"
        return Button {
            HapticFeedback.play(.selection)
            model.wantsMicrophone.toggle()
            model.open(model.requestedMode)
        } label: {
            Group {
                if compact { Image(systemName: symbol) } else { Label(text, systemImage: symbol) }
            }
            .modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canConfigure)
        .opacity(model.canConfigure ? 1 : 0.5)
        .accessibilityLabel("Record microphone audio")
        .accessibilityValue(wanted ? "On" : "Off")
        .accessibilityInputLabels(["Record microphone audio", "Mic"])
        .accessibilityHint("Records audio when microphone access is allowed. Changing it reopens the mode.")
        .accessibilityIdentifier("capture-modes-mic-chip")
    }

    private func referenceChip(compact: Bool) -> some View {
        let loaded = referenceImage != nil
        return Button { setReferenceTray(true) } label: {
            Group {
                if compact { referenceIcon(loaded: loaded) } else { referenceTitle(loaded: loaded) }
            }
            .modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reference image")
        .accessibilityValue(loaded ? "Loaded" : "None")
        .accessibilityInputLabels(["Reference image", "Reference"])
        .accessibilityHint("Opens the reference image tools")
        .accessibilityFocused($referenceFocus, equals: .chip)
        .onAppear {
            guard returnsFocusToReferenceChip else { return }
            returnsFocusToReferenceChip = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !showingReferenceTray else { return }
                referenceFocus = .chip
            }
        }
        .accessibilityIdentifier("capture-modes-reference-chip")
    }

    /// A loaded reference is shown by the badge shape, not by colour.
    private func referenceTitle(loaded: Bool) -> some View {
        HStack(spacing: 6) {
            Label("Reference", systemImage: "square.on.square.dashed")
            if loaded { Image(systemName: "checkmark.circle.fill") }
        }
    }

    private func referenceIcon(loaded: Bool) -> some View {
        Image(systemName: "square.on.square.dashed")
            .overlay(alignment: .topTrailing) {
                if loaded { Image(systemName: "checkmark.circle.fill").font(.caption2).offset(x: 9, y: -7) }
            }
    }

    private var aboutChip: some View {
        Button { showingModeInfo = true } label: {
            Image(systemName: "info.circle").modifier(CaptureModesCapsuleStyle())
        }
        .buttonStyle(.plain)
        .disabled(!CaptureModesPolicy.allowsModeInfo(phase: model.state.phase))
        .opacity(CaptureModesPolicy.allowsModeInfo(phase: model.state.phase) ? 1 : 0.5)
        .accessibilityLabel("About this mode")
        .accessibilityIdentifier("capture-modes-about-open")
    }

    private func adjustRow(_ adjuster: Adjuster) -> some View {
        HStack(spacing: 8) {
            switch adjuster {
            case .zoom: zoomSlider
            case .exposure: exposureSlider
            }
            Text(adjuster == .zoom ? String(format: "%.1f\u{00D7}", model.state.zoom) : String(format: "%+.1f EV", model.state.exposure))
                .font(.subheadline.monospacedDigit())
                .fixedSize()
                .accessibilityHidden(true)
            Button { setAdjusting(nil) } label: {
                Image(systemName: "checkmark").modifier(CaptureModesCapsuleStyle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(adjuster == .zoom ? "Done with zoom" : "Done with exposure")
            .accessibilityIdentifier("capture-modes-adjust-done")
        }
        .disabled(!model.canConfigure)
    }

    private var zoomSlider: some View {
        Slider(value: Binding(get: { model.state.zoom }, set: model.engine.setZoom), in: 1...max(1.01, model.state.maximumZoom))
            .tint(.white)
            .accessibilityLabel("Zoom")
            .accessibilityValue(String(format: "%.1f times", model.state.zoom))
    }

    private var exposureSlider: some View {
        Slider(value: Binding(get: { model.state.exposure }, set: model.engine.setExposure),
               in: model.state.minimumExposure...model.state.maximumExposure)
            .tint(.white)
            .accessibilityLabel("Exposure compensation")
            .accessibilityValue(String(format: "%+.1f EV", model.state.exposure))
    }

    private var modeInfoSheet: some View {
        CaptureModeInfoSheet(
            title: model.requestedMode.title,
            guidance: model.requestedMode.guidance,
            notes: CaptureModesPolicy.modeNotes(
                requestedMode: model.requestedMode, configuredMode: model.state.mode, controlsSupported: model.state.controlsSupported),
            unavailable: unavailableModes.compactMap { CaptureModesPolicy.unavailableReason(for: $0) })
    }

    private func referenceTray(_ geometry: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            referenceTrayHeader
            referenceTrayBody(geometry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.state.controlsExpanded ? 0 : 1)
        .allowsHitTesting(!model.state.controlsExpanded)
        .accessibilityHidden(model.state.controlsExpanded)
    }

    private var referenceTrayHeader: some View {
        HStack(spacing: 8) {
            Text("Reference image")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($referenceFocus, equals: .header)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { setReferenceTray(false) } label: {
                Image(systemName: "checkmark").modifier(CaptureModesCapsuleStyle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done with reference")
            .accessibilityIdentifier("capture-modes-reference-done")
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard showingReferenceTray else { return }
                referenceFocus = .header
            }
        }
    }

    /// Scrolls inside a capped height so the viewfinder keeps its floor; at accessibility sizes the page scrolls instead.
    @ViewBuilder private func referenceTrayBody(_ geometry: GeometryProxy) -> some View {
        if pageScrolls {
            referenceControls
        } else {
            ScrollView {
                referenceControls
            }
            .frame(maxHeight: geometry.size.height * 0.28)
            .accessibilityIdentifier("capture-modes-reference-scroll")
        }
    }

    private var referenceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use an onion-skin overlay or compare side by side. Filmy uses the reference locally and never burns it into photos or movies.")
                .font(.caption).foregroundStyle(.secondary)
            Button(referenceImage == nil ? "Choose a reference" : "Replace reference") { showingReferencePicker = true }
                .disabled(!model.canConfigure || referenceBusy)
                .accessibilityIdentifier("choose-reference-image")
            if referenceBusy {
                HStack { ProgressView(); Button("Cancel import") { cancelReference() } }
            }
            if referenceImage != nil { loadedReferenceControls }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(.white)
    }

    @ViewBuilder private var loadedReferenceControls: some View {
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
        Button("Remove reference", role: .destructive) { removeReference() }
    }

    private func removeReference() {
        cancelReference()
        do {
            let url = try CaptureReference.url()
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            referenceImage = nil
        } catch { model.errorMessage = error.localizedDescription }
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

/// What the open mode does, its notes, and the modes this device cannot offer.
private struct CaptureModeInfoSheet: View {
    let title: String
    let guidance: String
    let notes: [String]
    let unavailable: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(guidance).font(.body)
                    ForEach(notes, id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !unavailable.isEmpty { unavailableSection }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("About \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("capture-modes-about-done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Not on this device").font(.footnote.weight(.semibold))
            ForEach(unavailable, id: \.self) { reason in
                Text(reason).font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
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
