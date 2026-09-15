import SwiftUI

struct FujiShootingPanel: View {
    @ObservedObject var shooting: FujiShootingController
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var editingQ = false
    @State private var bankNames: [Int: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Toggle("Shooting system", isOn: control(\.enabled))
                        .font(.headline).accessibilityIdentifier("fuji-enabled")
                    Text(shooting.settings.enabled ? shooting.settings.drive.title : "Off keeps the existing single-photo workflow unchanged.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(shooting.settings.qItems) { item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.title).font(.caption.weight(.semibold)).lineLimit(3)
                                    Spacer(minLength: 0)
                                    Text(value(for: item)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                .padding(9).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("fuji-q-\(item.rawValue)")
                        }
                    }
                    NavigationLink("All shooting controls") {
                        List(FujiQItem.allCases) { item in NavigationLink(item.title, value: item) }
                            .navigationTitle("All controls")
                    }
                    Button("Customize Q menu") { editingQ = true }.frame(minHeight: 44)
                    if let warning = shooting.autoISOWarning { Text(warning).font(.footnote).foregroundStyle(.orange) }
                    if !shooting.status.isEmpty { Text(shooting.status).font(.footnote).foregroundStyle(.secondary) }
                    Text("Independent Fuji-inspired controls. OVF-style and focusing aids are electronic approximations, not optical or phase-detect hardware.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Q · Shooting")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationDestination(for: FujiQItem.self) { item in
                if item == .raw { FujiDevelopmentBrowser(shooting: shooting, viewModel: viewModel, photoLibrary: photoLibrary) }
                else { controls(for: item).navigationTitle(item.title) }
            }
            .sheet(isPresented: $editingQ) { qEditor }
            .disabled(shooting.locksSettings)
            .task { await shooting.refreshCapabilities() }
        }
        .alert("Shooting system", isPresented: Binding(get: { shooting.errorMessage != nil },
                                                     set: { if !$0 { shooting.errorMessage = nil } })) {
            Button("OK") { shooting.errorMessage = nil }
        } message: { Text(shooting.errorMessage ?? "") }
        .presentationDragIndicator(.visible)
    }

    private func control<T>(_ keyPath: WritableKeyPath<FujiShootingSettings, T>) -> Binding<T> {
        Binding(get: { shooting.settings[keyPath: keyPath] }, set: { shooting.settings[keyPath: keyPath] = $0 })
    }

    private func value(for item: FujiQItem) -> String {
        let settings = shooting.settings
        switch item {
        case .banks: return shooting.selectedBank.map { "C\($0)\(shooting.bankIsModified(recipe: viewModel.selectedRecipe) ? " · modified" : "")" } ?? "7 custom banks"
        case .drive: return settings.drive.title
        case .autoISO: return settings.autoISOIndex.map { "Auto \($0 + 1)" } ?? "Off"
        case .dynamicRange: return settings.dynamicRange.title
        case .filmBracket: return "\(settings.filmRecipeIDs.count) looks"
        case .whiteBalanceBracket: return "±\(Int(settings.whiteBalanceStep)) K"
        case .prime: return settings.prime.title
        case .viewfinder: return settings.viewfinder.rawValue
        case .naturalView: return settings.naturalLiveView ? "On" : "Off"
        case .focusAssist: return settings.focusAssist.rawValue
        case .multipleExposure: return "\(settings.multipleExposureCount) · \(settings.multipleExposureBlend.title)"
        case .preShot: return "\(settings.preShotCount) frames"
        case .computationalND: return "\(settings.ndSeconds.formatted()) seconds"
        case .focusStack: return "\(settings.focusCount) planes"
        case .raw: return settings.retainRAW ? "RAW on · develop" : "Originals · develop"
        case .interval: return "\(settings.intervalSeconds.formatted()) seconds"
        }
    }

    @ViewBuilder private func controls(for item: FujiQItem) -> some View {
        Form {
            switch item {
            case .banks:
                banks
            case .drive:
                Picker("Drive", selection: control(\.drive)) {
                    ForEach(FujiDriveMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.inline)
                Section("Bracketing") {
                    Picker("Frames", selection: control(\.bracketCount)) { ForEach([3, 5, 7], id: \.self) { Text("\($0)").tag($0) } }
                    Slider(value: control(\.bracketStepEV), in: (1 / 3)...2, step: 1 / 3) { Text("EV step") }
                    Text("EV spacing: \(shooting.settings.bracketStepEV.formatted(.number.precision(.fractionLength(2))))")
                    Stepper("Burst / interval count: \(shooting.settings.burstCount)", value: control(\.burstCount), in: 2...24)
                    Text("CL adds a 0.25 s pause; CH captures as quickly as the hardware completes each still. No guaranteed frame rate. Flash is disabled for multi-frame modes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                capabilityNote
            case .autoISO:
                Picker("Profile", selection: Binding(get: { shooting.settings.autoISOIndex ?? -1 },
                    set: { shooting.settings.autoISOIndex = $0 < 0 ? nil : $0 })) {
                    Text("Off").tag(-1)
                    ForEach(0..<3) { Text("Auto ISO \($0 + 1)").tag($0) }
                }
                ForEach(0..<3) { index in
                    Section("Auto ISO \(index + 1)") {
                        profileField("Minimum ISO", index: index, path: \.minimumISO, range: 50...12800, step: 50)
                        profileField("Maximum ISO", index: index, path: \.maximumISO, range: 100...51200, step: 100)
                        Picker("Minimum shutter", selection: profile(index, path: \.minimumShutterSeconds)) {
                            ForEach([30.0, 60, 125, 250, 500, 1000, 2000], id: \.self) { speed in Text("1/\(Int(speed)) s").tag(1 / speed) }
                        }
                    }
                }
                Text("Uses the lowest ISO that meets your preferred shutter. At maximum ISO it allows a slower shutter. Device bounds always win. Opening Manual controls turns this loop off.")
                    .font(.footnote).foregroundStyle(.secondary)
                capabilityNote
            case .dynamicRange:
                Picker("Capture dynamic range", selection: control(\.dynamicRange)) {
                    ForEach(FujiDynamicRange.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("DR200 captures RAW one stop shorter; DR400 captures two stops shorter, at the metered ISO. The development pipeline restores shadow brightness with a linear-domain highlight shoulder. EXIF readback must confirm the requested exposure. This is not a Fuji sensor calibration.")
                Text("Requires RAW plus manual exposure. Already clipped highlights cannot be recovered. Higher DR can increase shadow noise.")
                    .font(.footnote).foregroundStyle(.secondary)
                capabilityNote
            case .filmBracket:
                Text("Select up to three looks. One captured original is developed separately through each recipe.")
                ForEach(viewModel.recipes) { recipe in
                    Toggle(recipe.name, isOn: Binding(get: { shooting.settings.filmRecipeIDs.contains(recipe.id) }, set: { selected in
                        if selected, shooting.settings.filmRecipeIDs.count < 3 { shooting.settings.filmRecipeIDs.append(recipe.id) }
                        if !selected { shooting.settings.filmRecipeIDs.removeAll { $0 == recipe.id } }
                    }))
                    .disabled(!shooting.settings.filmRecipeIDs.contains(recipe.id) && shooting.settings.filmRecipeIDs.count >= 3)
                }
            case .whiteBalanceBracket:
                Slider(value: control(\.whiteBalanceStep), in: 100...2000, step: 100) { Text("Temperature step") }
                Text("Three developments: as-shot temperature ±\(Int(shooting.settings.whiteBalanceStep)) K. Clamped to 2500–10000 K. RAW uses the decoder's neutral-balance controls; processed originals use a color transform.")
            case .prime:
                Picker("Fixed digital crop", selection: control(\.prime)) { ForEach(FujiPrimeMode.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.inline)
                Text("Crop is relative to the selected lens and hardware zoom. No upsampling. \(Int(shooting.settings.prime.retainedPixelFraction * 100))% of source pixels retained before aspect cropping. Pinch zoom is disabled while a digital prime is selected.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .viewfinder:
                Picker("Viewfinder", selection: control(\.viewfinder)) { ForEach(FujiViewfinderMode.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.inline)
                Text("OVF-style shows the camera's unfiltered electronic feed with frame lines. Hybrid adds a developed inset. There is no optical viewfinder, parallax measurement, or view beyond the active camera sensor.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .naturalView:
                Toggle("Natural live view", isOn: control(\.naturalLiveView))
                Text("Bypasses film simulation only in the viewfinder. Captures still receive the selected recipe. The camera's own image processing remains; this is not a linear RAW preview.")
            case .focusAssist:
                Picker("Focus aid", selection: control(\.focusAssist)) { ForEach(FujiFocusAssist.allCases) { Text($0.title).tag($0) } }
                Text("Split comparison shows a magnified live upper half and a frozen reference lower half. Microprism shows magnified local edge contrast. Neither measures defocus direction or simulates phase-detect data. Use manual focus and judge detail visually.")
                Button("Freeze current focus reference") { shooting.freezeFocusReference() }
                    .disabled(shooting.preview == nil)
            case .multipleExposure:
                Stepper("Exposures: \(shooting.settings.multipleExposureCount)", value: control(\.multipleExposureCount), in: 2...9)
                Picker("Blend", selection: control(\.multipleExposureBlend)) { ForEach(FujiMultipleExposureBlend.allCases) { Text($0.title).tag($0) } }
                Text("Press the shutter once per exposure. The previous developed frame appears as an onion-skin guide. The chosen count completes the blend automatically. Retake removes the last frame from the blend without deleting its original. Additive blending can clip highlights.")
            case .preShot:
                Slider(value: control(\.preShotSeconds), in: 0.25...2, step: 0.25) { Text("Look-back duration") }
                Text("Look back \(shooting.settings.preShotSeconds.formatted()) seconds")
                Stepper("Pre-shot frames: \(shooting.settings.preShotCount)", value: control(\.preShotCount), in: 1...12)
                Text("A bounded, 1280 px preview buffer sampled at up to 8 fps, plus one normal full-resolution still. This is not full-resolution RAW pre-capture. The buffer clears on backgrounding, lens changes, and memory warnings.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .computationalND:
                Slider(value: control(\.ndSeconds), in: 0.5...8, step: 0.5) { Text("Averaging duration") }
                Text("Average for \(shooting.settings.ndSeconds.formatted()) seconds")
                Text("Linear-light temporal averaging of up to 8 preview samples per second, bounded to 1280 px. Smooths motion and reduces noise; it is not optical attenuation, continuous long exposure, or highlight recovery. Sampling gaps may produce segmented motion. Use a tripod, DR100, and RAW off.")
            case .focusStack:
                Stepper("Focus planes: \(shooting.settings.focusCount)", value: control(\.focusCount), in: 2...12)
                Slider(value: control(\.focusNear), in: 0...1) { Text("Start lens position") }
                Text("Start: \(shooting.settings.focusNear.formatted(.number.precision(.fractionLength(2))))")
                Slider(value: control(\.focusFar), in: 0...1) { Text("End lens position") }
                Text("End: \(shooting.settings.focusFar.formatted(.number.precision(.fractionLength(2))))")
                Text("Lens positions are normalized actuator values, not distances. Focus BKT saves separate frames; Focus stack merges local detail into a composite capped at 4096 px. Use a tripod and a stationary subject. There is no geometric alignment or focus-breathing correction, so inspect seams before use.")
                    .font(.footnote).foregroundStyle(.secondary)
                capabilityNote
            case .interval:
                Stepper("Frames: \(shooting.settings.burstCount)", value: control(\.burstCount), in: 2...24)
                Stepper("Pause: \(shooting.settings.intervalSeconds.formatted()) s", value: control(\.intervalSeconds), in: 0.5...3600, step: 0.5)
                Text("Pause is measured after the preceding capture completes, not a guaranteed start-to-start cadence. Keep the app open. Backgrounding cancels remaining captures; originals already completed remain available.")
            case .raw:
                EmptyView()
            }
        }
    }

    private var capabilityNote: some View {
        Section("Current lens") {
            if let capabilities = shooting.capabilities {
                LabeledContent("Manual exposure", value: capabilities.supportsCustomExposure ? "Supported" : "Unavailable")
                LabeledContent("Manual focus", value: capabilities.supportsManualFocus ? "Supported" : "Unavailable")
                LabeledContent("RAW", value: capabilities.supportsRAW ? "Available" : "Unavailable")
                Text("\(Int(capabilities.isoBounds.lowerBound))–\(Int(capabilities.isoBounds.upperBound)) ISO")
            } else { Text("Start the camera to inspect capabilities.") }
            Text("Use the existing Manual controls to select a physical lens when a virtual camera cannot provide RAW or manual exposure.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var banks: some View {
        ForEach(shooting.banks) { bank in
            Section("C\(bank.id)") {
                TextField("Bank name", text: Binding(get: { bankNames[bank.id] ?? bank.name }, set: { bankNames[bank.id] = $0 }))
                if let recipe = bank.recipe { Text("\(recipe.name) · \(bank.settings?.drive.title ?? "Single frame")").font(.caption) }
                HStack {
                    Button("Recall") { shooting.recallBank(bank.id, camera: camera, viewModel: viewModel) }.disabled(bank.settings == nil)
                    Spacer()
                    Button("Save current") { shooting.saveBank(bank.id, name: bankNames[bank.id] ?? bank.name, camera: camera, viewModel: viewModel) }
                }
                Menu("Copy to another bank") {
                    ForEach((1...7).filter { $0 != bank.id }, id: \.self) { destination in
                        Button("C\(destination)") { shooting.copyBank(from: bank.id, to: destination) }
                    }
                }.disabled(bank.settings == nil)
            }
        }
    }

    private func profile(_ index: Int, path: WritableKeyPath<FujiAutoISOProfile, Double>) -> Binding<Double> {
        Binding(get: { shooting.settings.autoISOProfiles[index][keyPath: path] },
                set: { shooting.settings.autoISOProfiles[index][keyPath: path] = $0 })
    }
    private func profileField(_ name: String, index: Int, path: WritableKeyPath<FujiAutoISOProfile, Double>,
                              range: ClosedRange<Double>, step: Double) -> some View {
        Stepper("\(name): \(Int(shooting.settings.autoISOProfiles[index][keyPath: path]))", value: profile(index, path: path), in: range, step: step)
    }

    private var qEditor: some View {
        NavigationStack {
            List {
                Section("Drag to reorder; swipe to remove") {
                    ForEach(shooting.settings.qItems) { Text($0.title) }
                        .onMove { shooting.settings.qItems.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { shooting.settings.qItems.remove(atOffsets: $0) }
                }
                Section("Available controls") {
                    ForEach(FujiQItem.allCases.filter { !shooting.settings.qItems.contains($0) }) { item in
                        Button("Add \(item.title)") { shooting.settings.qItems.append(item) }
                    }
                }
                Button("Restore default Q menu") { shooting.settings.qItems = FujiQItem.allCases }
            }
            .navigationTitle("Customize Q")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { editingQ = false } } }
            .environment(\.editMode, .constant(.active))
        }
    }
}

struct FujiViewfinderOverlay: View {
    @ObservedObject var shooting: FujiShootingController
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = shooting.multiplePreview {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().opacity(0.3)
                }
                if shooting.settings.viewfinder != .electronic {
                    Rectangle().stroke(.white.opacity(0.7), lineWidth: 1).padding(16)
                    VStack { Text("ELECTRONIC · OVF-STYLE").font(.caption2.monospaced()).padding(22); Spacer() }
                }
                if let sample = shooting.preview {
                    if shooting.settings.viewfinder == .hybrid {
                        VStack { Spacer(); HStack { Spacer(); Image(uiImage: sample.developed).resizable().scaledToFit()
                            .frame(width: geometry.size.width * 0.32).overlay(Rectangle().stroke(.white, lineWidth: 1)).padding(22) } }
                    }
                    if shooting.settings.focusAssist == .microprism {
                        Image(uiImage: sample.contrast).resizable().scaledToFill().frame(width: 130, height: 130).clipShape(Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                    } else if shooting.settings.focusAssist == .splitImage {
                        let reference = shooting.focusReference ?? sample.live
                        ZStack {
                            Image(uiImage: sample.live).resizable().scaledToFill().frame(width: 150, height: 150).clipped()
                                .mask(VStack(spacing: 0) { Color.white; Color.clear })
                            Image(uiImage: reference).resizable().scaledToFill().frame(width: 150, height: 150).clipped()
                                .mask(VStack(spacing: 0) { Color.clear; Color.white })
                            Rectangle().frame(width: 150, height: 1).foregroundStyle(.white)
                        }.frame(width: 150, height: 150).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 1))
                    }
                }
            }.foregroundStyle(.white)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
