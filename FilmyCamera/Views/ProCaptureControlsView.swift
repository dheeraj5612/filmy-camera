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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture format").font(.headline)
            Picker("Resolution", selection: binding(\.resolution)) {
                ForEach(ProCaptureSettings.Resolution.allCases) { value in
                    Text(value.title).tag(value).disabled(!capabilities.resolutions.contains(value))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pro-resolution")
            Text("12 and 48 MP use supported sensor dimensions. 24 MP is developed from a 48 MP original, not Apple's deferred 24 MP fusion. These are requested resolutions; the camera can deliver fewer pixels. Cropping reduces the final pixel count. Manual and priority exposure use 12 MP.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("File format", selection: binding(\.format)) {
                ForEach(ProCaptureSettings.Format.allCases) { value in
                    Text(value.title).tag(value).disabled(!capabilities.formats.contains(value))
                }
            }
            .accessibilityIdentifier("pro-format")
            Picker("Output color", selection: binding(\.colorGamut)) {
                Text("sRGB").tag(ProCaptureSettings.ColorGamut.sRGB)
                Text("Display P3").tag(ProCaptureSettings.ColorGamut.displayP3)
            }
            .accessibilityIdentifier("pro-color-space")
            Toggle("HDR HEIF (10-bit PQ)", isOn: Binding(
                get: { settings.dynamicRange == .hdr },
                set: { value in var next = settings; next.dynamicRange = value ? .hdr : .sdr; camera.setProCaptureSettings(next) }
            ))
            .disabled(settings.format == .jpeg || settings.livePhoto)
            .accessibilityIdentifier("pro-hdr")
            Text("HDR preserves available captured highlight headroom. SDR originals are not given artificial HDR brightness. Filmy keeps the original alongside every edit.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Live Photo", isOn: binding(\.livePhoto))
                .disabled(!capabilities.livePhotoSupported || settings.format.retainsRAW || settings.resolution != .mp12 || settings.dynamicRange == .hdr)
                .accessibilityIdentifier("pro-live-photo")
            Text("Live uses 12 MP, standard dynamic range and Photo finish. RAW and Live cannot be combined. The film look is applied to the still and movie during Photos export.")
                .font(.caption).foregroundStyle(.secondary)
            if settings.livePhoto {
                Toggle("Include microphone audio", isOn: binding(\.livePhotoAudio))
                    .accessibilityIdentifier("pro-live-audio")
            }
            if let reason = capabilities.unavailableReason(for: settings) {
                Text(reason).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("pro-capture-unavailable")
            }

            Text(camera.statusMessage).font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Exposure program").font(.headline)
            Picker("Program", selection: Binding(get: { camera.exposureProgram }, set: { apply($0) })) {
                ForEach(CameraExposureProgram.allCases) { program in
                    Text(program.title).tag(program).disabled(!capabilities.exposurePrograms.contains(program))
                }
            }
            .accessibilityIdentifier("pro-exposure-program")
            if !capabilities.nativeExposureAPIAvailable {
                Text("Priority and variable-aperture controls require an iOS 27 SDK build, iOS 27, and a lens that exposes them. Coupled manual exposure remains available below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if priority {
                if camera.exposureProgram == .isoPriority {
                    Text("ISO \(Int(iso)) · shutter auto").monospacedDigit()
                    Slider(value: $iso, in: Double(max(controls.minimumISO, 1))...Double(max(controls.maximumISO, controls.minimumISO + 1)),
                           onEditingChanged: { if !$0 { apply(camera.exposureProgram) } })
                        .accessibilityLabel("Priority ISO").accessibilityIdentifier("pro-priority-iso")
                }
                if camera.exposureProgram == .shutterPriority {
                    Text("\(Self.shutterTitle(pow(2, shutterLog))) · ISO auto").monospacedDigit()
                    Slider(value: $shutterLog,
                           in: log2(max(controls.minimumExposureDurationSeconds, 0.00001))...log2(max(controls.maximumExposureDurationSeconds, 0.00002)),
                           onEditingChanged: { if !$0 { apply(camera.exposureProgram) } })
                        .accessibilityLabel("Priority shutter duration").accessibilityIdentifier("pro-priority-shutter")
                }
                Text("Applied: ISO \(Int(controls.iso)) · \(Self.shutterTitle(controls.exposureDurationSeconds))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if capabilities.variableApertureSupported {
                Text("Aperture f/\(aperture, specifier: "%.1f")").monospacedDigit()
                Slider(value: $aperture, in: Double(capabilities.minimumAperture)...Double(capabilities.maximumAperture), onEditingChanged: {
                    if !$0 { apply(camera.exposureProgram == .manual ? .manual : .aperturePriority, includeAperture: true) }
                })
                .accessibilityLabel("Lens aperture").accessibilityIdentifier("pro-aperture")
                Text("Moving aperture selects Aperture Priority, or keeps full Manual when already selected.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if capabilities.aperture > 0 {
                Text("Lens aperture: f/\(capabilities.aperture, specifier: "%.1f") · read-only on this lens/build")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Focus aids").font(.headline)
            Toggle("Focus loupe · 4× preview", isOn: Binding(get: { camera.focusLoupeEnabled }, set: camera.setFocusLoupeEnabled))
                .accessibilityIdentifier("pro-focus-loupe")
            Toggle("Track tapped subject", isOn: Binding(get: { camera.subjectTrackingEnabled }, set: camera.setSubjectTrackingEnabled))
                .disabled(!camera.isRunning).accessibilityIdentifier("pro-subject-tracking")
            Text("Tap a subject in the viewfinder. Supported iOS 27 lenses use native tracking; other lenses use on-device Vision. Lost subjects require another tap. Manual focus and AE/AF lock stop tracking.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(FilmyTheme.primary)
        .disabled(controls.isApplying)
        .onAppear(perform: sync)
        .onChange(of: camera.exposureProgram) { _, _ in sync() }
        .onChange(of: controls.activeDeviceID) { _, _ in sync() }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProCaptureSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in
            var next = settings
            next[keyPath: keyPath] = value
            camera.setProCaptureSettings(next)
        })
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

struct FocusAssistOverlay: View {
    @ObservedObject var camera: CameraService
    let size: CGSize
    let topClearance: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let rect = camera.trackedSubjectRectangle,
               let frame = Self.displayRect(rect, source: camera.previewFrameSize, viewport: size) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.yellow, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            VStack(alignment: .trailing, spacing: 6) {
                if camera.focusLoupeEnabled, let image = camera.focusLoupeImage {
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
