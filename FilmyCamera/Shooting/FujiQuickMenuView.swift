import SwiftUI
import UIKit

struct FujiQuickMenuView: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tileMinimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 220 : 110
        let lineCap: Int? = dynamicTypeSize.isAccessibilitySize ? nil : 2
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum), spacing: 8)], spacing: 8) {
                        ForEach(controller.preferences.quickControls) { control in
                            NavigationLink {
                                destination(control)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(control.title).font(.caption.weight(.semibold)).lineLimit(lineCap)
                                    Spacer(minLength: 0)
                                    Text(value(control)).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(lineCap)
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
                    FujiHint(short: "Some effects are approximations; support depends on the lens.",
                             long: "OVF-style, focus aids and temporal ND are digital interpretations. RAW, custom exposure and manual focus depend on the selected lens.",
                             topic: "the Q menu", identifier: "fuji-hint-q")
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
        case .rawDevelopment: return FujiOriginalFilter.tileValue(captureRAW: settings.captureRAW, records: controller.originals)
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

/// One plain line always visible; the full explanation one tap away. Expansion is not stored.
struct FujiHint: View {
    let short: String
    let long: String
    let topic: String
    let identifier: String
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(short).font(.footnote).foregroundStyle(.secondary)
            if isEnabled { toggle }
            if expanded || !isEnabled {
                Text(long).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + "-text")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("More about this")
                Image(systemName: expanded ? "chevron.up" : "chevron.down").accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More about \(topic)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier(identifier)
    }
}

/// Where the banks list scrolls on appearance: only at accessibility text sizes, only to a saved bank after C1.
enum FujiBankScroll {
    static func target(selectedBank: Int?, savedIDs: Set<Int>, accessibilitySize: Bool) -> String? {
        guard accessibilitySize, let n = selectedBank, n > 1, savedIDs.contains(n) else { return nil }
        return "bank-\(n)"
    }
}

private struct FujiBanksView: View {
    @ObservedObject var controller: FujiShootingController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var names: [Int: String] = [:]
    @State private var pendingOverwrite: Int?
    @State private var savedIndex: Int?
    @State private var scrolledToActive = false

    var body: some View {
        ScrollViewReader { proxy in
            banksForm
                .onAppear { scrollToActiveBank(proxy) }
        }
    }

    private func scrollToActiveBank(_ proxy: ScrollViewProxy) {
        if !scrolledToActive {
            let saved: Set<Int> = Set(controller.preferences.banks.map { $0.id })
            let target: String? = FujiBankScroll.target(selectedBank: controller.preferences.selectedBank, savedIDs: saved,
                                                        accessibilitySize: dynamicTypeSize.isAccessibilitySize)
            if let target { proxy.scrollTo(target, anchor: .top) }
        }
        scrolledToActive = true
    }

    private var banksForm: some View {
        Form {
            if let message = controller.errorMessage {
                Section { Text(message).font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                FujiHint(short: "Save a setup, then recall it in one tap.",
                         long: "Each bank saves the complete recipe, shooting setup, device, manual controls, crop, framing, timer and finish. Recall does not automatically overwrite a bank.",
                         topic: "banks", identifier: "fuji-hint-banks")
            }
            ForEach(1...7, id: \.self) { index in bankSection(index) }
        }
        .navigationTitle("C1–C7 Shooting Banks")
        .disabled(controller.settingsLocked)
        .confirmationDialog("Replace the saved bank?", isPresented: Binding(get: { pendingOverwrite != nil },
            set: { if !$0 { pendingOverwrite = nil } }), titleVisibility: .visible) {
            Button("Replace bank", role: .destructive) { if let index = pendingOverwrite { save(index) }; pendingOverwrite = nil }
            Button("Cancel", role: .cancel) { pendingOverwrite = nil }
        }
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func nameBinding(_ index: Int, _ bank: FujiShootingBank?) -> Binding<String> {
        Binding<String>(get: { names[index] ?? bank?.name ?? "" },
                        set: { names[index] = String($0.prefix(32)) })
    }

    @ViewBuilder private func bankSection(_ index: Int) -> some View {
        let bank: FujiShootingBank? = controller.preferences.banks.first { $0.id == index }
        if let bank {
            savedSection(index, bank)
        } else {
            emptySection(index)
        }
    }

    private func emptySection(_ index: Int) -> some View {
        Section {
            rowLayout {
                Text("C\(index)").font(.headline.monospaced()).accessibilityAddTraits(.isHeader)
                TextField("Name", text: nameBinding(index, nil), prompt: Text("Custom \(index)"))
                    .accessibilityLabel("C\(index) name")
                Button(action: { save(index) }, label: {
                    Text("Save")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                })
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Save current setup to C\(index)")
                    .accessibilityInputLabels(["Save", "Save C\(index)"])
                    .accessibilityIdentifier("fuji-bank-save-\(index)")
            }
        }
    }

    private func savedSection(_ index: Int, _ bank: FujiShootingBank) -> some View {
        Section {
            if savedIndex == index {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                    Text("Saved to C\(index)").accessibilityIdentifier("fuji-bank-saved-\(index)")
                }.font(.footnote)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("C\(index)").font(.headline).accessibilityAddTraits(.isHeader)
                Text(bank.recipe.name).font(.footnote).foregroundStyle(.secondary)
            }
                .id("bank-\(index)")
            recallRow(index, bank)
            TextField("Name", text: nameBinding(index, bank), prompt: Text("Custom \(index)"))
                .accessibilityLabel("C\(index) name")
            Button("Replace with current setup") { pendingOverwrite = index }
                .frame(minHeight: 44)
                .accessibilityLabel("Replace C\(index) with current setup")
                .accessibilityIdentifier("fuji-bank-save-\(index)")
        }
    }

    private func recallRow(_ index: Int, _ bank: FujiShootingBank) -> some View {
        rowLayout {
            Button("Recall C\(index)") { savedIndex = nil; controller.recallBank(bank) }
                .buttonStyle(.filmySecondary)
                .accessibilityIdentifier("fuji-bank-recall-\(index)")
            if controller.preferences.selectedBank == index {
                let dirty: Bool = controller.bankIsDirty(bank)
                HStack(spacing: 4) {
                    Image(systemName: dirty ? "pencil.circle" : "checkmark.circle.fill").accessibilityHidden(true)
                    Text(dirty ? "Edited" : "Active")
                }.font(.caption.weight(.semibold))
            }
        }
    }

    private func save(_ index: Int) {
        let before: Date? = controller.preferences.banks.first(where: { $0.id == index })?.savedAt
        controller.saveBank(index, name: names[index] ?? controller.preferences.banks.first(where: { $0.id == index })?.name ?? "Custom \(index)")
        let after: Date? = controller.preferences.banks.first(where: { $0.id == index })?.savedAt
        if after != nil && after != before {
            savedIndex = index
            UIAccessibility.post(notification: .announcement, argument: "Saved to C\(index)")
        }
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

    private func useDriveButton(_ title: String, _ drive: FujiDrive) -> some View {
        let inUse = controller.settings.drive == drive
        return Button {
            let wasInUse = controller.settings.drive == drive
            controller.change(\.drive, to: drive)
            if !wasInUse && controller.settings.drive == drive { HapticFeedback.play(.selection) }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 0)
                if inUse { Image(systemName: "checkmark").font(.body.weight(.semibold)).accessibilityHidden(true) }
            }
        }
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityValue(inUse ? "In use" : "")
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
                FujiHint(short: "Low and High set how quickly continuous frames follow.",
                         long: "Low targets at least 0.3 seconds between starts. High starts the next capture as soon as the camera and local storage are ready. Actual rate depends on the lens, RAW, light and device load. Flash is off for this shooting system.",
                         topic: "Drive", identifier: "fuji-hint-drive")
            }
        case .autoISO: autoISO
        case .dynamicRange:
            Section("Sensor highlight protection") {
                Picker("Capture DR", selection: bind(\.dynamicRange)) { ForEach(FujiDynamicRange.allCases) { Text($0.title).tag($0) } }
                Toggle("Keep RAW + developed JPEG", isOn: bind(\.captureRAW))
                FujiHint(short: "DR200 and DR400 expose 1 or 2 stops darker to protect highlights.",
                         long: "DR200 captures one stop below the metered exposure; DR400 captures two stops below it. A retained RAW is developed with middle-gray compensation and a highlight shoulder. This is separate from a recipe's tone setting. Unsupported exposure ranges are rejected, not simulated on a JPEG.",
                         topic: "Capture DR", identifier: "fuji-hint-dynamicRange")
                rawAvailability
            }
        case .teleconverter:
            Section("Prime / digital teleconverter") {
                Toggle("Lock the current physical lens", isOn: bind(\.lockPrimeLens))
                Picker("Digital crop", selection: bind(\.digitalCrop)) {
                    Text("Native · 1×").tag(1.0); Text("1.4×").tag(1.4); Text("2×").tag(2.0); Text("3×").tag(3.0)
                }.pickerStyle(.segmented)
                FujiHint(short: "Crops the saved photo; a lens lock turns off zoom.",
                         long: "The crop is applied to the saved pixels without upscaling. A 2× crop retains one quarter of the source pixels. A prime lock disables hardware zoom and lens changes until unlocked here. RAW originals stay uncropped.",
                         topic: "Digital crop", identifier: "fuji-hint-teleconverter")
            }
        case .viewfinder:
            Section("Finder") {
                Picker("Viewfinder", selection: bind(\.viewfinder)) { ForEach(FujiViewfinder.allCases) { Text($0.title).tag($0) } }
                FujiHint(short: "EVF shows the developed crop; OVF-style and Hybrid show more of the scene.",
                         long: "EVF previews the developed crop. OVF-style shows an unfiltered electronic view outside the crop, with bright framing lines. Hybrid adds a processed crop inset. An iPhone does not contain an optical viewfinder.",
                         topic: "Viewfinder", identifier: "fuji-hint-viewfinder")
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
                FujiHint(short: "Visual aids only. Reset the reference after reframing.",
                         long: "Split image and microprism breakup are driven by relative center-patch contrast. They are visual focusing aids, not phase-detection measurements or a focus guarantee. Reset the contrast reference after reframing; use peaking or magnification to confirm fine focus.",
                         topic: "Focus aids", identifier: "fuji-hint-focusAssist")
                Button("Reset contrast reference") { controller.invalidatePreview() }.frame(minHeight: 44)
            }
        case .naturalView:
            Section {
                Toggle("Natural Live View", isOn: bind(\.naturalLiveView))
                FujiHint(short: "Shows the scene without the recipe; saved photos still use it.",
                         long: "Preview without the film recipe's color, grain or tone processing. The selected recipe is still applied to every saved JPEG. OVF-style and Hybrid always use a natural main view.",
                         topic: "Natural Live View", identifier: "fuji-hint-naturalView")
            }
        case .nd:
            Section("Temporal ND · long exposure") {
                Stepper("ND \(controller.settings.ndStops) · \(1 << controller.settings.ndStops) frames", value: bind(\.ndStops), in: 1...5)
                Toggle("Keep component originals", isOn: bind(\.keepCompositeSources))
                useDriveButton("Use Computational ND", .computationalND)
                FujiHint(short: "Blends 2–32 frames into one long-exposure look; use a tripod.",
                         long: "Average 2–32 equal-exposure stills in linear light for moving-water and motion-trail effects. Output is bounded to 6 MP. Use a tripod. This is sampled temporal integration, not a physical ND filter: it cannot prevent clipping within a source exposure and gaps may break motion trails.",
                         topic: "Computational ND", identifier: "fuji-hint-nd")
            }
        case .multipleExposure:
            Section("Layered capture") {
                Stepper("Layers: \(controller.settings.multipleExposureCount)", value: bind(\.multipleExposureCount), in: 2...9)
                Picker("Blend", selection: bind(\.blendMode)) { ForEach(FujiBlendMode.allCases) { Text($0.title).tag($0) } }
                Toggle("Keep component originals", isOn: bind(\.keepCompositeSources))
                useDriveButton("Use Multiple Exposure", .multipleExposure)
                FujiHint(short: "Press once per layer; the photo saves after the last one.",
                         long: "Press the shutter for each layer. A translucent previous-layer guide helps you compose. Recipe, crop and blend are fixed from the first layer. The final composite is saved automatically at the chosen count; output is bounded to 6 MP.",
                         topic: "Multiple exposure", identifier: "fuji-hint-multipleExposure")
            }
        case .preShot:
            Section("Before the shutter") {
                Picker("Buffer", selection: bind(\.preShotSeconds)) {
                    Text("Off").tag(0.0); Text("0.5 seconds").tag(0.5); Text("1 second").tag(1.0); Text("1.5 seconds").tag(1.5)
                }
                FujiHint(short: "Keeps frames from just before you press.",
                         long: "Keeps up to 10 preview-resolution frames per second before the shutter, followed by the normal still. Buffered images are capped at 768 px and 32 MB total. Single-frame drive only, with RAW and DR protection off. Changing lens, framing or recipe clears the buffer. Backgrounding clears it too.",
                         topic: "Pre-shot", identifier: "fuji-hint-preShot")
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
                useDriveButton("Use Focus Bracketing · separate files", .focusBracket)
                useDriveButton("Use Focus Stacking · fused image", .focusStack)
                FujiHint(short: "Needs manual focus control, a tripod and a still subject.",
                         long: "Requires manual lens-position control. Stacking aligns small translations and fuses locally sharp regions, with a 6 MP budget. Use a tripod and a still subject. Parallax and focus breathing are not corrected; large misalignment fails rather than silently exporting a bad stack.",
                         topic: "Focus stacking", identifier: "fuji-hint-focusStack")
            }
        case .interval:
            Section("Foreground interval shooting") {
                Stepper("Frames: \(controller.settings.intervalCount)", value: bind(\.intervalCount), in: 2...120)
                Stepper("Interval: \(Int(controller.settings.intervalSeconds)) seconds", value: bind(\.intervalSeconds), in: 1...3600)
                useDriveButton("Use Interval Shooting", .interval)
                FujiHint(short: "Keep Filmy open; leaving the app stops the sequence.",
                         long: "Intervals are measured start-to-start. The next frame waits when the sensor is slower than the requested interval; missed deadlines never cause a catch-up burst. Keep the app in the foreground. Backgrounding cancels the sequence and retains acquired sources.",
                         topic: "Interval shooting", identifier: "fuji-hint-interval")
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
                FujiHint(short: "Raises ISO first, then slows the shutter at the ISO limit.",
                         long: "Raises ISO before slowing below the preferred shutter. At maximum ISO it permits slower shutter speeds. The app continuously meters on a supported physical lens. Exposure is held through a bracket or sweep.",
                         topic: "Auto ISO", identifier: "fuji-hint-autoISO")
                let appliedLine = "Applied: ISO \(Int(camera.manualControls.iso)) · \(FujiMath.shutterText(camera.manualControls.exposureDurationSeconds))"
                Text(appliedLine)
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
            Section("AE BKT · exposure") {
                Picker("Frames", selection: bind(\.bracketCount)) { ForEach([3, 5, 7, 9], id: \.self) { Text("\($0)").tag($0) } }
                Picker("Step", selection: bind(\.bracketStep)) {
                    Text("⅓ EV").tag(1.0 / 3); Text("⅔ EV").tag(2.0 / 3); Text("1 EV").tag(1.0); Text("2 EV").tag(2.0)
                }
                Picker("Sequence", selection: bind(\.bracketOrder)) { ForEach(FujiBracketOrder.allCases) { Text($0.title).tag($0) } }
                useDriveButton("Use AE Bracketing", .aeBracket)
            }
            Section("Film Simulation BKT · one exposure") {
                ForEach(0..<3, id: \.self) { index in
                    Picker("Look \(index + 1)", selection: Binding(get: { controller.settings.filmRecipeIDs[index] }, set: { value in
                        var ids = controller.settings.filmRecipeIDs; ids[index] = value; controller.change(\.filmRecipeIDs, to: ids)
                    })) { ForEach(viewModel.recipes) { Text($0.name).tag($0.id) } }
                }
                useDriveButton("Use Film Simulation Bracketing", .filmBracket)
            }
            Section("Same-shot ISO / WB variants") {
                Picker("ISO BKT step", selection: bind(\.isoBracketStep)) {
                    Text("⅓ EV").tag(1.0 / 3); Text("⅔ EV").tag(2.0 / 3); Text("1 EV").tag(1.0)
                }
                Stepper("WB step: \(controller.settings.whiteBalanceStep)", value: bind(\.whiteBalanceStep), in: 1...3)
                useDriveButton("Use ISO Bracketing", .isoBracket)
                useDriveButton("Use White Balance Bracketing", .whiteBalanceBracket)
                FujiHint(short: "Three developments of one exposure, not three sensor ISOs.",
                         long: "These create three developments of one exposure, not three different sensor ISO settings. WB shifts use Filmy's normalized temperature control.",
                         topic: "ISO and WB bracketing", identifier: "fuji-hint-bracketing")
            }
            Section("Dynamic Range BKT · three exposures") {
                useDriveButton("Use DR100 / DR200 / DR400 Bracketing", .dynamicRangeBracket)
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
