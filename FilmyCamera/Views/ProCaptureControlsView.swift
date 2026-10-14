import SwiftUI

struct ProCaptureControlsView: View {
    @ObservedObject var camera: CameraService
    @State private var iso: Double = 100
    @State private var shutterLog: Double = -6
    @State private var aperture: Double = 1.8

    private var settings: ProCaptureSettings { camera.proCaptureSettings }
    private var capabilities: ProCaptureCapabilities { camera.proCaptureCapabilities }
    private var controls: CameraManualControls { camera.manualControls }
    private var priority: Bool { ![CameraExposureProgram.automatic, .manual].contains(camera.exposureProgram) }

    private var hdrDisabled: Bool {
        settings.dynamicRange != .hdr && (settings.format == .jpeg || settings.livePhoto)
    }

    private var livePhotoDisabled: Bool {
        !settings.livePhoto && (!capabilities.livePhotoSupported || settings.format.retainsRAW
            || settings.resolution != .mp12 || settings.dynamicRange == .hdr)
    }

    private var availableResolutions: [ProCaptureSettings.Resolution] {
        ProCaptureSettings.Resolution.allCases.filter { capabilities.resolutions.contains($0) || $0 == settings.resolution }
    }

    private var availableFormats: [ProCaptureSettings.Format] {
        ProCaptureSettings.Format.allCases.filter { capabilities.formats.contains($0) || $0 == settings.format }
    }

    private var availablePrograms: [CameraExposureProgram] {
        CameraExposureProgram.allCases.filter { capabilities.exposurePrograms.contains($0) || $0 == camera.exposureProgram }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            programGroup
            Divider()
            focusAidsGroup
            Divider()
            formatGroup
        }
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(FilmyTheme.primary)
        .disabled(controls.isApplying)
        .onAppear(perform: sync)
        .onChange(of: camera.exposureProgram) { _, _ in sync() }
        .onChange(of: controls.activeDeviceID) { _, _ in sync() }
    }

    @ViewBuilder private var programGroup: some View {
        groupHeading("Exposure program")
        ProChoiceRow(title: "Program") {
            Picker("Program", selection: Binding(get: { camera.exposureProgram }, set: { apply($0) })) {
                ForEach(availablePrograms) { program in
                    Text(program.title).tag(program)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            .accessibilityIdentifier("pro-exposure-program")
        }
        if !capabilities.nativeExposureAPIAvailable {
            captionLine("Priority modes need iOS 27 and a supported lens.")
        }
        if priority {
            priorityControls
        }
        apertureControls
    }

    @ViewBuilder private var priorityControls: some View {
        if camera.exposureProgram == .isoPriority {
            Text("ISO \(Int(iso)) · shutter auto").monospacedDigit()
            Slider(value: $iso, in: isoRange,
                   onEditingChanged: { if !$0 { apply(camera.exposureProgram) } })
                .accessibilityLabel("Priority ISO").accessibilityIdentifier("pro-priority-iso")
                .accessibilityValue("ISO \(Int(iso))")
                .accessibilityAdjustableAction { direction in
                    guard !controls.isApplying else { return }
                    guard let sign = Self.adjustSign(direction) else { return }
                    iso = Self.clamped(iso * pow(2, sign / 3), isoRange)
                    apply(camera.exposureProgram)
                }
        }
        if camera.exposureProgram == .shutterPriority {
            Text("\(Self.shutterTitle(pow(2, shutterLog))) · ISO auto").monospacedDigit()
            Slider(value: $shutterLog,
                   in: shutterLogRange,
                   onEditingChanged: { if !$0 { apply(camera.exposureProgram) } })
                .accessibilityLabel("Priority shutter duration").accessibilityIdentifier("pro-priority-shutter")
                .accessibilityValue(Self.shutterTitle(pow(2, shutterLog)))
                .accessibilityAdjustableAction { direction in
                    guard !controls.isApplying else { return }
                    guard let sign = Self.adjustSign(direction) else { return }
                    shutterLog = Self.clamped(shutterLog + sign / 3, shutterLogRange)
                    apply(camera.exposureProgram)
                }
        }
        Text("Applied: ISO \(Int(controls.iso)) · \(Self.shutterTitle(controls.exposureDurationSeconds))")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    @ViewBuilder private var apertureControls: some View {
        if capabilities.variableApertureSupported {
            Text("Aperture f/\(aperture, specifier: "%.1f")").monospacedDigit()
            Slider(value: $aperture, in: apertureRange, onEditingChanged: {
                if !$0 { apply(camera.exposureProgram == .manual ? .manual : .aperturePriority, includeAperture: true) }
            })
            .accessibilityLabel("Lens aperture").accessibilityIdentifier("pro-aperture")
            .accessibilityValue(String(format: "f/%.1f", aperture))
            .accessibilityAdjustableAction { direction in
                guard !controls.isApplying else { return }
                guard let sign = Self.adjustSign(direction) else { return }
                let step = (apertureRange.upperBound - apertureRange.lowerBound) / 20
                aperture = Self.clamped(aperture + sign * step, apertureRange)
                apply(camera.exposureProgram == .manual ? .manual : .aperturePriority, includeAperture: true)
            }
            captionLine("Sets Aperture priority, or stays in Manual.")
        } else if capabilities.aperture > 0 {
            captionLine(String(format: "Lens aperture: f/%.1f · not adjustable here", capabilities.aperture))
        }
    }

    @ViewBuilder private var focusAidsGroup: some View {
        groupHeading("Focus aids")
        Toggle("Focus loupe · 4× preview", isOn: Binding(get: { camera.focusLoupeEnabled }, set: camera.setFocusLoupeEnabled))
            .accessibilityIdentifier("pro-focus-loupe")
            .frame(minHeight: FilmyTheme.minimumHitTarget)
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Track tapped subject", isOn: Binding(get: { camera.subjectTrackingEnabled }, set: camera.setSubjectTrackingEnabled))
                .disabled(!camera.isRunning).accessibilityIdentifier("pro-subject-tracking")
                .frame(minHeight: FilmyTheme.minimumHitTarget)
            if !camera.isRunning {
                reasonLine("Needs the camera running.")
            } else {
                captionLine("Tap a subject in the viewfinder to follow it.")
            }
        }
    }

    @ViewBuilder private var formatGroup: some View {
        groupHeading("Capture format")
        VStack(alignment: .leading, spacing: 6) {
            Text("Resolution")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Picker("Resolution", selection: binding(\.resolution)) {
                ForEach(availableResolutions) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pro-resolution")
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            resolutionLine
        }
        ProChoiceRow(title: "File format") {
            Picker("File format", selection: binding(\.format)) {
                ForEach(availableFormats) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            .accessibilityIdentifier("pro-format")
        }
        VStack(alignment: .leading, spacing: 6) {
            ProChoiceRow(title: "Output color") {
                Picker("Output color", selection: binding(\.colorGamut)) {
                    Text("sRGB").tag(ProCaptureSettings.ColorGamut.sRGB)
                    Text("Display P3").tag(ProCaptureSettings.ColorGamut.displayP3)
                }
                .pickerStyle(.menu)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .disabled(settings.dynamicRange == .hdr)
                .accessibilityIdentifier("pro-color-space")
            }
            if settings.dynamicRange == .hdr {
                reasonLine("Not used while HDR is on.")
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Toggle("HDR HEIF (10-bit PQ)", isOn: Binding(
                get: { settings.dynamicRange == .hdr },
                set: { value in var next = settings; next.dynamicRange = value ? .hdr : .sdr; camera.setProCaptureSettings(next) }
            ))
            .disabled(hdrDisabled)
            .accessibilityIdentifier("pro-hdr")
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            if hdrDisabled {
                reasonLine("HDR needs HEIF or RAW without Live Photo.")
            } else {
                captionLine("Keeps extra highlight detail for HDR screens.")
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Live Photo", isOn: binding(\.livePhoto))
                .disabled(livePhotoDisabled)
                .accessibilityIdentifier("pro-live-photo")
                .frame(minHeight: FilmyTheme.minimumHitTarget)
            if livePhotoDisabled {
                reasonLine(livePhotoReason)
            } else {
                captionLine("Your look is applied to the still and the movie.")
            }
        }
        if settings.livePhoto {
            Toggle("Include microphone audio", isOn: binding(\.livePhotoAudio))
                .accessibilityIdentifier("pro-live-audio")
                .frame(minHeight: FilmyTheme.minimumHitTarget)
        }
        if let reason = capabilities.unavailableReason(for: settings) {
            Text(reason).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("pro-capture-unavailable")
        }
    }

    private var livePhotoReason: String {
        capabilities.livePhotoSupported ? "Needs 12 MP, no RAW, and HDR off." : "Live Photo is not available on this camera."
    }

    @ViewBuilder private var resolutionLine: some View {
        if settings.resolution != .mp12 && camera.exposureProgram != .automatic {
            reasonLine("Manual and priority exposure use 12 MP.")
        } else if settings.resolution == .mp24 {
            captionLine("24 MP is made from a 48 MP original.")
        } else {
            captionLine("Requested size. The camera may deliver fewer pixels.")
        }
    }

    private func captionLine(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func reasonLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private func groupHeading(_ text: String) -> some View {
        Text(text).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProCaptureSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in
            var next = settings
            next[keyPath: keyPath] = value
            camera.setProCaptureSettings(next)
        })
    }

    private var isoRange: ClosedRange<Double> {
        Double(max(controls.minimumISO, 1))...Double(max(controls.maximumISO, controls.minimumISO + 1))
    }

    private var shutterLogRange: ClosedRange<Double> {
        log2(max(controls.minimumExposureDurationSeconds, 0.00001))...log2(max(controls.maximumExposureDurationSeconds, 0.00002))
    }

    private var apertureRange: ClosedRange<Double> {
        Double(capabilities.minimumAperture)...Double(capabilities.maximumAperture)
    }

    private static func adjustSign(_ direction: AccessibilityAdjustmentDirection) -> Double? {
        switch direction {
        case .increment: return 1
        case .decrement: return -1
        @unknown default: return nil
        }
    }

    private static func clamped(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private func apply(_ program: CameraExposureProgram, includeAperture: Bool = false) {
        camera.setExposureProgram(program, iso: Float(iso), durationSeconds: pow(2, shutterLog),
                                  aperture: includeAperture || program == .aperturePriority ? Float(aperture) : nil)
    }

    private func sync() {
        iso = Double(max(controls.minimumISO, min(max(controls.iso, 1), max(controls.maximumISO, 1))))
        shutterLog = log2(max(controls.exposureDurationSeconds, 0.00001))
        aperture = Double(max(capabilities.aperture, 0.1))
    }

    private static func shutterTitle(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Auto" }
        return seconds < 1 ? "1/\(Int((1 / seconds).rounded())) s" : String(format: "%.1f s", seconds)
    }
}

private struct ProChoiceRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    control()
                }
            } else {
                HStack(spacing: 12) {
                    label
                    Spacer(minLength: 8)
                    control()
                }
            }
        }
        .frame(minHeight: FilmyTheme.minimumHitTarget)
    }

    private var label: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

struct FocusAssistOverlay: View {
    @ObservedObject var camera: CameraService
    let size: CGSize
    let topClearance: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TrackedSubjectBox(state: camera.focusAssistState, previewFrameSize: camera.previewFrameSize, viewport: size)
            VStack(alignment: .trailing, spacing: 6) {
                FocusLoupePreview(state: camera.focusAssistState, enabled: camera.focusLoupeEnabled, size: size)
                if camera.subjectTrackingEnabled {
                    Text(camera.subjectTrackingStatus).font(.caption.weight(.semibold))
                        .padding(8).background(.black.opacity(0.7), in: Capsule())
                        .accessibilityIdentifier("focus-tracking-status")
                }
            }
            .foregroundStyle(.white).padding(.top, topClearance).padding(.trailing, 12)
        }
        .frame(width: size.width, height: size.height)
        .clipped().allowsHitTesting(false)
    }

    nonisolated static func displayRect(_ rect: CGRect, source: CGSize, viewport: CGSize) -> CGRect? {
        guard source.width > 0, source.height > 0, viewport.width > 0, viewport.height > 0 else { return nil }
        let scale = max(viewport.width / source.width, viewport.height / source.height)
        let offset = CGPoint(x: (viewport.width - source.width * scale) / 2, y: (viewport.height - source.height * scale) / 2)
        return CGRect(x: offset.x + rect.minX * source.width * scale,
                      y: offset.y + (1 - rect.maxY) * source.height * scale,
                      width: rect.width * source.width * scale, height: rect.height * source.height * scale)
    }
}

/// Observes only the tracked-subject rectangle so its ticks do not re-render the whole overlay.
private struct TrackedSubjectBox: View {
    @ObservedObject var state: FocusAssistState
    let previewFrameSize: CGSize
    let viewport: CGSize

    var body: some View {
        if let rect = state.trackedSubjectRectangle,
           let frame = FocusAssistOverlay.displayRect(rect, source: previewFrameSize, viewport: viewport) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.yellow, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}

/// Observes only the loupe image so its ticks do not re-render the whole overlay.
private struct FocusLoupePreview: View {
    @ObservedObject var state: FocusAssistState
    let enabled: Bool
    let size: CGSize

    var body: some View {
        if enabled, let image = state.focusLoupeImage {
            VStack(spacing: 4) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
                    .frame(width: min(144, size.width * 0.38), height: min(144, size.width * 0.38))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("4× focus preview").font(.caption2.weight(.semibold))
            }
            .padding(6).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("Four times magnified focus preview")
            .accessibilityIdentifier("focus-loupe-preview")
        }
    }
}
