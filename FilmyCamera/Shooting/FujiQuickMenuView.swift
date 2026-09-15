import SwiftUI

struct FujiQuickMenuView: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("SHOOTING SYSTEM").font(.caption.weight(.semibold)).tracking(2)
                        Spacer()
                        Text(controller.preferences.selectedBank.map { "C\($0)" } ?? "Custom").font(.headline.monospaced())
                    }
                    Text("\(controller.settings.drive.title) · \(controller.settings.dynamicRange.title)")
                        .font(.title3.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(controller.preferences.quickControls) { control in
                            NavigationLink {
                                destination(control)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(control.title).font(.caption.weight(.semibold)).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Text(value(control)).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("fuji-q-\(control.rawValue)")
                            .disabled(controller.settingsLocked)
                        }
                    }
                    if let message = controller.validationMessage {
                        Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    }
                    if controller.settingsLocked {
                        Text(controller.isComposing ? "A multiple exposure is in progress. Finish or discard its layers before changing the shooting setup." : "Finish or cancel shooting before changing the setup.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Cancel shooting", role: .destructive) { controller.cancel() }.frame(minHeight: 44)
                    }
                    if controller.pendingExportCount > 0 {
                        Section {
                            Text("\(controller.pendingExportCount) finished photos are safely queued on this device.").font(.footnote)
                            Button("Retry saving to Photos") { controller.retryExports(photoLibrary: photoLibrary) }
                                .disabled(controller.isBusy).frame(minHeight: 44)
                        }
                    }
                    if let error = controller.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                    NavigationLink("All shooting controls") {
                        List(FujiQuickControl.allCases) { control in NavigationLink(control.title) { destination(control) } }
                            .navigationTitle("Shooting controls")
                    }.frame(minHeight: 44)
                    Text("OVF-style, focus aids and temporal ND are digital interpretations. RAW, custom exposure and manual focus depend on the selected lens.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .navigationTitle("Q Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("Customize") { FujiQEditor(controller: controller) }
                        .disabled(controller.settingsLocked)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task { await controller.reloadLibrary() }
        }
    }

    @ViewBuilder private func destination(_ control: FujiQuickControl) -> some View {
        switch control {
        case .banks: FujiBanksView(controller: controller)
        case .rawDevelopment: FujiRAWLibraryView(controller: controller, viewModel: viewModel, photoLibrary: photoLibrary)
        case .manual: ManualCameraControlsView(camera: camera)
        default: FujiControlDetail(control: control, controller: controller, camera: camera, viewModel: viewModel)
        }
    }

    private func value(_ control: FujiQuickControl) -> String {
        let settings = controller.settings
        switch control {
        case .banks: return controller.preferences.selectedBank.map { "C\($0)" } ?? "Not recalled"
        case .drive: return settings.drive.title
        case .autoISO: return settings.autoISOIndex.map { "AUTO \($0 + 1)" } ?? "Off"
        case .dynamicRange: return settings.dynamicRange.title
        case .teleconverter: return String(format: "%.1f× crop", settings.digitalCrop)
        case .viewfinder: return settings.viewfinder.title
        case .focusAssist: return settings.focusAssist.title
        case .naturalView: return settings.naturalLiveView ? "On" : "Off"
        case .nd: return "\(1 << settings.ndStops) frames"
        case .multipleExposure: return "\(settings.multipleExposureCount) · \(settings.blendMode.title)"
        case .preShot: return settings.preShotSeconds > 0 ? String(format: "%.1f seconds", settings.preShotSeconds) : "Off"
        case .rawDevelopment: return settings.captureRAW ? "RAW + JPEG" : "Originals"
        case .bracketing: return "\(settings.bracketCount) · \(settings.bracketStep.formatted()) EV"
        case .focusStack: return "\(settings.focusCount) positions"
        case .interval: return "\(settings.intervalCount) · \(Int(settings.intervalSeconds))s"
        case .manual: return camera.manualControls.activeDeviceName
        }
    }
}

private struct FujiQEditor: View {
    @ObservedObject var controller: FujiShootingController
    var body: some View {
        List {
            Section("Visible controls · drag to reorder") {
                ForEach(controller.preferences.quickControls) { control in Text(control.title).frame(minHeight: 36) }
                    .onMove { controller.preferences.quickControls.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { controller.preferences.quickControls.remove(atOffsets: $0) }
            }
            Section("Available controls") {
                ForEach(FujiQuickControl.allCases.filter { !controller.preferences.quickControls.contains($0) }) { control in
                    Button("Add \(control.title)") { controller.preferences.quickControls.append(control) }.frame(minHeight: 44)
                }
            }
            Button("Restore the 16-control layout") { controller.preferences.quickControls = FujiQuickControl.allCases }
        }
        .navigationTitle("Customize Q").toolbar { EditButton() }
        .disabled(controller.settingsLocked)
    }
}

private struct FujiBanksView: View {
    @ObservedObject var controller: FujiShootingController
    @State private var names: [Int: String] = [:]
    @State private var pendingOverwrite: Int?
    var body: some View {
        Form {
            Section {
                Text("Each bank saves the complete recipe, shooting setup, device, manual controls, crop, framing, timer and finish. Recall does not automatically overwrite a bank.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(1...7, id: \.self) { index in
                let bank = controller.preferences.banks.first { $0.id == index }
                Section {
                    TextField("Name", text: Binding(get: { names[index] ?? bank?.name ?? "Custom \(index)" },
                                                    set: { names[index] = String($0.prefix(32)) }))
                    if let bank {
                        Text(bank.recipe.name).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button("Recall C\(index)") { controller.recallBank(bank) }
                                .accessibilityIdentifier("fuji-bank-recall-\(index)")
                            Spacer()
                            if controller.preferences.selectedBank == index {
                                Text(controller.bankIsDirty(bank) ? "Edited" : "Active").font(.caption.weight(.semibold))
                            }
                        }.frame(minHeight: 44)
                    }
                    Button(bank == nil ? "Save current setup" : "Replace with current setup") {
                        if bank == nil { save(index) } else { pendingOverwrite = index }
                    }
                    .frame(minHeight: 44).accessibilityIdentifier("fuji-bank-save-\(index)")
                } header: { Text("C\(index)") }
            }
        }
        .navigationTitle("C1–C7 Shooting Banks")
        .disabled(controller.settingsLocked)
        .confirmationDialog("Replace the saved bank?", isPresented: Binding(get: { pendingOverwrite != nil },
            set: { if !$0 { pendingOverwrite = nil } }), titleVisibility: .visible) {
            Button("Replace bank", role: .destructive) { if let index = pendingOverwrite { save(index) }; pendingOverwrite = nil }
            Button("Cancel", role: .cancel) { pendingOverwrite = nil }
        }
    }
    private func save(_ index: Int) {
        controller.saveBank(index, name: names[index] ?? controller.preferences.banks.first(where: { $0.id == index })?.name ?? "Custom \(index)")
    }
}

private struct FujiControlDetail: View {
    let control: FujiQuickControl
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel

    private func bind<T>(_ key: WritableKeyPath<FujiShootingSettings, T>) -> Binding<T> {
        Binding(get: { controller.settings[keyPath: key] }, set: { controller.change(key, to: $0) })
    }
    var body: some View {
        Form { content }
            .navigationTitle(control.title).navigationBarTitleDisplayMode(.inline)
            .disabled(controller.settingsLocked)
    }

    @ViewBuilder private var content: some View {
        switch control {
        case .drive:
            Section("Still-photo drive") {
                Picker("Mode", selection: bind(\.drive)) { ForEach(FujiDrive.allCases) { Text($0.title).tag($0) } }
                Stepper("Continuous frames: \(controller.settings.burstCount)", value: bind(\.burstCount), in: 2...20)
                Text("Low targets at least 0.3 seconds between starts. High starts the next capture as soon as the camera and local storage are ready. Actual rate depends on the lens, RAW, light and device load. Flash is off for this shooting system.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .autoISO: autoISO
        case .dynamicRange:
            Section("Sensor highlight protection") {
                Picker("Capture DR", selection: bind(\.dynamicRange)) { ForEach(FujiDynamicRange.allCases) { Text($0.title).tag($0) } }
                Toggle("Keep RAW + developed JPEG", isOn: bind(\.captureRAW))
                Text("DR200 captures one stop below the metered exposure; DR400 captures two stops below it. A retained RAW is developed with middle-gray compensation and a highlight shoulder. This is separate from a recipe's tone setting. Unsupported exposure ranges are rejected, not simulated on a JPEG.")
                    .font(.footnote).foregroundStyle(.secondary)
                rawAvailability
            }
        case .teleconverter:
            Section("Prime / digital teleconverter") {
                Toggle("Lock the current physical lens", isOn: bind(\.lockPrimeLens))
                Picker("Digital crop", selection: bind(\.digitalCrop)) {
                    Text("Native · 1×").tag(1.0); Text("1.4×").tag(1.4); Text("2×").tag(2.0); Text("3×").tag(3.0)
                }.pickerStyle(.segmented)
                Text("The crop is applied to the saved pixels without upscaling. A 2× crop retains one quarter of the source pixels. A prime lock disables hardware zoom and lens changes until unlocked here. RAW originals stay uncropped.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .viewfinder:
            Section("Finder") {
                Picker("Viewfinder", selection: bind(\.viewfinder)) { ForEach(FujiViewfinder.allCases) { Text($0.title).tag($0) } }
                Text("EVF previews the developed crop. OVF-style shows an unfiltered electronic view outside the crop, with bright framing lines. Hybrid adds a processed crop inset. An iPhone does not contain an optical viewfinder.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .focusAssist:
            Section("Manual focus aids") {
                Picker("Aid", selection: bind(\.focusAssist)) { ForEach(FujiFocusAssist.allCases) { Text($0.title).tag($0) } }
                if camera.manualControls.manualFocusSupported {
                    Slider(value: Binding(get: { Double(camera.manualControls.lensPosition) },
                        set: { camera.setManualFocus(lensPosition: Float($0)) }), in: 0...1) { Text("Lens position") }
                        .accessibilityLabel("Manual focus position")
                    Button("Return to autofocus") { camera.setAutoFocus() }.frame(minHeight: 44)
                }
                Text("Split image and microprism breakup are driven by relative center-patch contrast. They are visual focusing aids, not phase-detection measurements or a focus guarantee. Reset the contrast reference after reframing; use peaking or magnification to confirm fine focus.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset contrast reference") { controller.invalidatePreview() }.frame(minHeight: 44)
            }
        case .naturalView:
            Section {
                Toggle("Natural Live View", isOn: bind(\.naturalLiveView))
                Text("Preview without the film recipe's color, grain or tone processing. The selected recipe is still applied to every saved JPEG. OVF-style and Hybrid always use a natural main view.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .nd:
            Section("Temporal ND") {
                Stepper("ND \(controller.settings.ndStops) · \(1 << controller.settings.ndStops) frames", value: bind(\.ndStops), in: 1...5)
                Toggle("Keep component originals", isOn: bind(\.keepCompositeSources))
                Button("Use Computational ND") { controller.change(\.drive, to: .computationalND) }.frame(minHeight: 44)
                Text("Average 2–32 equal-exposure stills in linear light for moving-water and motion-trail effects. Output is bounded to 6 MP. Use a tripod. This is sampled temporal integration, not a physical ND filter: it cannot prevent clipping within a source exposure and gaps may break motion trails.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .multipleExposure:
            Section("Layered capture") {
                Stepper("Layers: \(controller.settings.multipleExposureCount)", value: bind(\.multipleExposureCount), in: 2...9)
                Picker("Blend", selection: bind(\.blendMode)) { ForEach(FujiBlendMode.allCases) { Text($0.title).tag($0) } }
                Toggle("Keep component originals", isOn: bind(\.keepCompositeSources))
                Button("Use Multiple Exposure") { controller.change(\.drive, to: .multipleExposure) }.frame(minHeight: 44)
                Text("Press the shutter for each layer. A translucent previous-layer guide helps you compose. Recipe, crop and blend are fixed from the first layer. The final composite is saved automatically at the chosen count; output is bounded to 6 MP.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .preShot:
            Section("Before the shutter") {
                Picker("Buffer", selection: bind(\.preShotSeconds)) {
                    Text("Off").tag(0.0); Text("0.5 seconds").tag(0.5); Text("1 second").tag(1.0); Text("1.5 seconds").tag(1.5)
                }
                Text("Keeps up to 10 preview-resolution frames per second before the shutter, followed by the normal still. Buffered images are capped at 768 px and 32 MB total. Single-frame drive only, with RAW and DR protection off. Changing lens, framing or recipe clears the buffer. Backgrounding clears it too.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Ready: \(controller.bufferedCount) frames").font(.footnote.monospaced())
            }
        case .bracketing: bracketing
        case .focusStack:
            Section("Near-to-far sweep") {
                Stepper("Positions: \(controller.settings.focusCount)", value: bind(\.focusCount), in: 2...20)
                labeledSlider("Near position", value: bind(\.focusNear), range: 0...1)
                labeledSlider("Far position", value: bind(\.focusFar), range: 0...1)
                labeledSlider("Settle time (seconds)", value: bind(\.focusInterval), range: 0.05...3)
                Button("Set near to current focus") { controller.change(\.focusNear, to: Double(camera.manualControls.lensPosition)) }
                Button("Set far to current focus") { controller.change(\.focusFar, to: Double(camera.manualControls.lensPosition)) }
                Toggle("Keep component originals", isOn: bind(\.keepCompositeSources))
                Button("Use Focus Bracketing · separate files") { controller.change(\.drive, to: .focusBracket) }.frame(minHeight: 44)
                Button("Use Focus Stacking · fused image") { controller.change(\.drive, to: .focusStack) }.frame(minHeight: 44)
                Text("Requires manual lens-position control. Stacking aligns small translations and fuses locally sharp regions, with a 6 MP budget. Use a tripod and a still subject. Parallax and focus breathing are not corrected; large misalignment fails rather than silently exporting a bad stack.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .interval:
            Section("Foreground interval shooting") {
                Stepper("Frames: \(controller.settings.intervalCount)", value: bind(\.intervalCount), in: 2...120)
                Stepper("Interval: \(Int(controller.settings.intervalSeconds)) seconds", value: bind(\.intervalSeconds), in: 1...3600)
                Button("Use Interval Shooting") { controller.change(\.drive, to: .interval) }.frame(minHeight: 44)
                Text("Intervals are measured start-to-start. The next frame waits when the sensor is slower than the requested interval; missed deadlines never cause a catch-up burst. Keep the app in the foreground. Backgrounding cancels the sequence and retains acquired sources.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        default: EmptyView()
        }
    }

    private var autoISO: some View {
        Group {
            Section("Program") {
                Picker("Auto ISO", selection: bind(\.autoISOIndex)) {
                    Text("Off").tag(nil as Int?)
                    ForEach(0..<3, id: \.self) { Text("AUTO \($0 + 1)").tag(Optional($0)) }
                }
                Text("Raises ISO before slowing below the preferred shutter. At maximum ISO it permits slower shutter speeds. The app continuously meters on a supported physical lens. Exposure is held through a bracket or sweep.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Applied: ISO \(Int(camera.manualControls.iso)) · \(camera.manualControls.exposureDurationSeconds.formatted()) s")
                    .font(.caption.monospaced())
            }
            ForEach(0..<3, id: \.self) { index in
                Section("AUTO \(index + 1)") {
                    profileField("Minimum ISO", index: index, key: \.minimumISO, range: 25...6400, step: 25)
                    profileField("Maximum ISO", index: index, key: \.maximumISO, range: 100...12800, step: 100)
                    Picker("Preferred slowest shutter", selection: profileBinding(index, \.minimumShutterSeconds)) {
                        ForEach([15, 30, 60, 125, 250, 500, 1000, 2000], id: \.self) { Text("1/\($0) s").tag(1.0 / Double($0)) }
                    }
                    Toggle("Use focal-length rule", isOn: profileBinding(index, \.useFocalLengthRule))
                    profileField("Motion multiplier", index: index, key: \.motionMultiplier, range: 1...4, step: 0.5)
                }
            }
        }
    }

    private var bracketing: some View {
        Group {
            Section("AE BKT") {
                Picker("Frames", selection: bind(\.bracketCount)) { ForEach([3, 5, 7, 9], id: \.self) { Text("\($0)").tag($0) } }
                Picker("Step", selection: bind(\.bracketStep)) {
                    Text("⅓ EV").tag(1.0 / 3); Text("⅔ EV").tag(2.0 / 3); Text("1 EV").tag(1.0); Text("2 EV").tag(2.0)
                }
                Picker("Sequence", selection: bind(\.bracketOrder)) { ForEach(FujiBracketOrder.allCases) { Text($0.title).tag($0) } }
                Button("Use AE Bracketing") { controller.change(\.drive, to: .aeBracket) }.frame(minHeight: 44)
            }
            Section("Film Simulation BKT · one exposure") {
                ForEach(0..<3, id: \.self) { index in
                    Picker("Look \(index + 1)", selection: Binding(get: { controller.settings.filmRecipeIDs[index] }, set: { value in
                        var ids = controller.settings.filmRecipeIDs; ids[index] = value; controller.change(\.filmRecipeIDs, to: ids)
                    })) { ForEach(viewModel.recipes) { Text($0.name).tag($0.id) } }
                }
                Button("Use Film Simulation Bracketing") { controller.change(\.drive, to: .filmBracket) }.frame(minHeight: 44)
            }
            Section("Same-shot ISO / WB variants") {
                Picker("ISO BKT step", selection: bind(\.isoBracketStep)) {
                    Text("⅓ EV").tag(1.0 / 3); Text("⅔ EV").tag(2.0 / 3); Text("1 EV").tag(1.0)
                }
                Stepper("WB step: \(controller.settings.whiteBalanceStep)", value: bind(\.whiteBalanceStep), in: 1...3)
                Button("Use ISO Bracketing") { controller.change(\.drive, to: .isoBracket) }.frame(minHeight: 44)
                Button("Use White Balance Bracketing") { controller.change(\.drive, to: .whiteBalanceBracket) }.frame(minHeight: 44)
                Text("These create three developments of one exposure, not three different sensor ISO settings. WB shifts use Filmy's normalized temperature control.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Dynamic Range BKT · three exposures") {
                Button("Use DR100 / DR200 / DR400 Bracketing") { controller.change(\.drive, to: .dynamicRangeBracket) }.frame(minHeight: 44)
                rawAvailability
            }
        }
    }

    private var rawAvailability: some View {
        Text(camera.supportsFujiRAW ? "RAW is available on this camera configuration." : "RAW is unavailable on this configuration. Choose a supported physical rear lens in Sensor controls.")
            .font(.footnote).foregroundStyle(camera.supportsFujiRAW ? Color.secondary : Color.orange)
    }
    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).monospacedDigit() }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
    private func profileBinding<T>(_ index: Int, _ key: WritableKeyPath<FujiAutoISOProfile, T>) -> Binding<T> {
        Binding(get: { controller.settings.autoISOProfiles[index][keyPath: key] }, set: { value in
            var profiles = controller.settings.autoISOProfiles
            profiles[index][keyPath: key] = value
            controller.change(\.autoISOProfiles, to: profiles)
        })
    }
    private func profileField(_ title: String, index: Int, key: WritableKeyPath<FujiAutoISOProfile, Double>,
                              range: ClosedRange<Double>, step: Double) -> some View {
        Stepper("\(title): \(controller.settings.autoISOProfiles[index][keyPath: key].formatted())", value: profileBinding(index, key), in: range, step: step)
    }
}
