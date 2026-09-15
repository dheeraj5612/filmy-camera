import SwiftUI

struct ProCaptureControlsView: View {
    @ObservedObject var camera: CameraService
    @AppStorage("proFocusLoupe") private var loupe = false
    @AppStorage("proFocusTracking") private var tracking = false
    @AppStorage("proFocusLoupeMagnification") private var magnification = 2.0
    @State private var fixedISO = 100.0
    @State private var fixedShutter = 1.0 / 125.0
    private static let shutterValues: [Double] = [8000, 4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 2, 1].map { 1.0 / $0 }
    private static let isoValues: [Double] = [25, 50, 100, 200, 400, 800, 1600, 3200]
    private var options: ProCaptureOptions { camera.captureOptions }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            captureFormatSection
            Divider()
            exposurePrioritySection
            Divider()
            focusAidsSection
            Divider()
            retentionSection
        }
        .foregroundStyle(FilmyTheme.primary)
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("pro-capture-controls")
    }

    private var captureFormatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture format").font(.headline)
            Picker("Resolution request", selection: binding(\.resolution)) {
                ForEach(ProCaptureOptions.Resolution.allCases, id: \.self) { resolution in
                    Text(resolution.title).tag(resolution)
                        .disabled(!camera.captureCapabilities.resolutions.contains(resolution))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pro-resolution")
            Text("Resolution is a sensor request before your crop. Actual dimensions appear in Filmy originals; images are never upscaled.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Photo output", selection: binding(\.codec)) {
                ForEach(ProCaptureOptions.Codec.allCases, id: \.self) { codec in
                    Text(codec.title).tag(codec).disabled(codec == .heif && !camera.captureCapabilities.supportsHEIF)
                }
            }
            .accessibilityIdentifier("pro-codec")
            Picker("Retain RAW", selection: binding(\.raw)) {
                ForEach(ProCaptureOptions.RawFormat.allCases, id: \.self) { format in
                    Text(format.title).tag(format).disabled(!rawSupported(format))
                }
            }
            .accessibilityIdentifier("pro-raw")
            Text("Bayer RAW requires a physical lens at native 1× zoom. RAW and Live originals are saved separately from the Filmy still in Photos.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("HDR highlight preservation", isOn: binding(\.hdr))
                .disabled(options.codec != .heif || !camera.captureCapabilities.supportsHDRExport)
                .accessibilityIdentifier("pro-hdr")
            Toggle("Live Photo · silent", isOn: binding(\.livePhoto))
                .disabled(!camera.captureCapabilities.supportsLivePhoto || options.raw != .off || camera.manualControls.exposureMode == .manual)
                .accessibilityIdentifier("pro-live-photo")
            ForEach(camera.captureNotices, id: \.self) { notice in
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    private var exposurePrioritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exposure priority").font(.headline)
            if camera.manualControls.manualExposureSupported {
                HStack {
                    Button("Shutter priority") { camera.setExposurePriority(.shutter, fixedValue: fixedShutter) }
                        .accessibilityIdentifier("pro-shutter-priority")
                    Button("ISO priority") { camera.setExposurePriority(.iso, fixedValue: fixedISO) }
                        .accessibilityIdentifier("pro-iso-priority")
                }
                .buttonStyle(.bordered)
                if camera.exposurePriority == .shutter {
                    Picker("Fixed shutter", selection: $fixedShutter) {
                        ForEach(Self.shutterValues, id: \.self) { duration in
                            Text(duration < 1 ? "1/\(Int((1 / duration).rounded())) s" : "1 s").tag(duration)
                        }
                    }
                    .onChange(of: fixedShutter) { _, value in camera.setExposurePriority(.shutter, fixedValue: value) }
                    Text("ISO follows the scene. Requested shutter is clamped to this lens's supported range.").font(.caption)
                } else if camera.exposurePriority == .iso {
                    Picker("Fixed ISO", selection: $fixedISO) {
                        ForEach(Self.isoValues, id: \.self) { iso in Text("ISO \(Int(iso))").tag(iso) }
                    }
                    .onChange(of: fixedISO) { _, value in camera.setExposurePriority(.iso, fixedValue: value) }
                    Text("Shutter follows the scene. Requested ISO is clamped to this lens's supported range.").font(.caption)
                }
                if let priority = camera.exposurePriority {
                    Text("\(priority.title) · ISO \(Int(camera.manualControls.iso)) · \(camera.manualControls.exposureDurationSeconds, specifier: "%.4f") s")
                        .font(.caption.monospacedDigit())
                    if camera.priorityAtLimit { Text("Exposure limit reached").font(.caption).foregroundStyle(FilmyTheme.danger) }
                    Button("Return to auto exposure") { camera.setAutoExposure() }.buttonStyle(.bordered)
                }
            } else {
                Text("Choose a physical lens that supports custom exposure to use priority modes.").font(.caption).foregroundStyle(.secondary)
            }

        }
    }

    private var focusAidsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus aids").font(.headline)
            Toggle("Focus loupe", isOn: $loupe).accessibilityIdentifier("pro-focus-loupe")
            if loupe {
                Picker("Preview magnification", selection: $magnification) {
                    Text("2×").tag(2.0)
                    Text("4×").tag(4.0)
                }.pickerStyle(.segmented)
            }
            Toggle("Track subject focus", isOn: $tracking).accessibilityIdentifier("pro-subject-tracking")
            Text("Tap a subject to follow it. Without a tap, the largest detected face is selected. Lost subjects require another tap. Tracking never overrides manual focus or AE/AF lock. The loupe only magnifies the preview.")
                .font(.caption).foregroundStyle(.secondary)

        }
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Lens aperture", value: camera.captureCapabilities.aperture > 0
                ? String(format: "ƒ/%.2f", camera.captureCapabilities.aperture) : "Unavailable")
                .accessibilityIdentifier("pro-aperture-readout")
            Text("Read-only with this app's public SDK. Variable-aperture control is not implemented; no exposure or blur slider is presented as an optical aperture.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Originals and edits remain in Roll → Filmy originals, even when Photos access is denied. These are user files, not an evictable cache; deleting the app removes its local originals.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }


    private func binding<Value>(_ keyPath: WritableKeyPath<ProCaptureOptions, Value>) -> Binding<Value> {
        Binding(get: { camera.captureOptions[keyPath: keyPath] }, set: { value in
            var next = camera.captureOptions
            next[keyPath: keyPath] = value
            camera.setCaptureOptions(next)
        })
    }
    private func rawSupported(_ format: ProCaptureOptions.RawFormat) -> Bool {
        switch format {
        case .off: return true
        case .bayer: return camera.captureCapabilities.supportsBayerRAW
        case .appleProRAW: return camera.captureCapabilities.supportsProRAW
        }
    }
}

struct FocusAssistOverlay: View {
    @ObservedObject var store: FocusAssistStore
    let size: CGSize
    let magnification: Double
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let box = store.box {
                let rect = FocusAssistGeometry.displayRect(box, size: size)
                RoundedRectangle(cornerRadius: 8).stroke(FilmyTheme.accent, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 4) {
                if store.subjectLost { Text("Subject lost · tap to track").font(.caption.weight(.semibold)).padding(6).background(.black.opacity(0.7)) }
                if let loupe = store.loupe {
                    Image(uiImage: loupe).resizable().interpolation(.none).scaledToFill()
                        .frame(width: min(size.width * 0.32, 156), height: min(size.width * 0.32, 156))
                        .clipped().overlay { Rectangle().stroke(.white, lineWidth: 1) }
                        .overlay(alignment: .bottomLeading) {
                            Text("\(Int(magnification))× preview").font(.caption2).padding(4).background(.black.opacity(0.7))
                        }
                        .accessibilityLabel("Focus loupe at \(Int(magnification)) times preview magnification")
                }
            }
            .foregroundStyle(.white)
            .padding(.trailing, 12).padding(.bottom, 66)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}
