import SwiftUI
import UniformTypeIdentifiers

struct FujiRAWLibraryView: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var importing = false
    @State private var reading = false
    @State private var error: String?
    @State private var deletion: FujiOriginalRecord?

    var body: some View {
        List {
            Section {
                Toggle("Capture RAW + developed JPEG", isOn: Binding(get: { controller.settings.captureRAW },
                    set: { controller.change(\.captureRAW, to: $0) })).disabled(controller.settingsLocked)
                Button(reading ? "Reading RAW…" : "Import a RAW file") { importing = true }
                    .frame(minHeight: 44).disabled(reading || controller.isBusy)
                Text("Originals are retained on this device, outside Photos. Development never overwrites their bytes. Export an unchanged original for backup before deleting it or uninstalling Filmy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if controller.pendingExportCount > 0 {
                Section("Recoverable exports") {
                    Button("Retry \(controller.pendingExportCount) Photos saves") { controller.retryExports(photoLibrary: photoLibrary) }
                        .disabled(controller.isBusy).frame(minHeight: 44)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.orange).font(.footnote) } }
            if let message = controller.errorMessage { Section { Text(message).foregroundStyle(.orange).font(.footnote) } }
            Section("Originals and retained sequence sources") {
                if controller.originals.isEmpty {
                    ContentUnavailableView("No originals yet", systemImage: "camera.aperture",
                        description: Text("Enable RAW on a supported lens or import a supported RAW file. Failed or retained composite sources also appear here."))
                }
                ForEach(controller.originals) { record in
                    NavigationLink {
                        FujiRAWDevelopView(controller: controller, viewModel: viewModel, photoLibrary: photoLibrary, original: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.isRAW ? "RAW" : "SOURCE JPEG").font(.caption2.weight(.bold).monospaced())
                                Text(record.dynamicRange.title).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Spacer()
                                Text(record.capturedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(record.recipe.name).font(.headline)
                            Text(record.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 6)
                    }
                    .swipeActions {
                        Button("Delete original", role: .destructive) { deletion = record }.disabled(controller.isBusy)
                    }
                }
            }
        }
        .navigationTitle("RAW Develop").navigationBarTitleDisplayMode(.inline)
        .task { await controller.reloadLibrary() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.rawImage], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                reading = true; error = nil
                Task {
                    defer { reading = false }
                    do { try await controller.importRAW(url, recipe: viewModel.selectedRecipe) }
                    catch { self.error = error.localizedDescription }
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("Delete the original from this device?", isPresented: Binding(get: { deletion != nil },
            set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("Delete original permanently", role: .destructive) {
                guard let deletion else { return }
                Task {
                    do { try await controller.deleteOriginal(deletion) }
                    catch { self.error = error.localizedDescription }
                    self.deletion = nil
                }
            }
        } message: { Text("Developed copies in Photos are not deleted. This cannot be undone; export the original first to keep a backup.") }
    }
}

struct FujiRAWDevelopView: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    let original: FujiOriginalRecord
    @State private var draft: FujiOriginalRecord
    @State private var image: UIImage?
    @State private var isRendering = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var originalURL: URL?
    @State private var editingRecipe = false
    @State private var renderGeneration = UUID()
    @State private var savedMessage: String?

    init(controller: FujiShootingController, viewModel: CameraViewModel, photoLibrary: PhotoLibraryService, original: FujiOriginalRecord) {
        self.controller = controller; self.viewModel = viewModel; self.photoLibrary = photoLibrary; self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        Form {
            Section {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 340)
                            .accessibilityLabel("RAW development preview")
                    } else { Color.clear.frame(height: 240) }
                    if isRendering { ProgressView("Developing preview").padding().background(.regularMaterial, in: Capsule()) }
                }.frame(maxWidth: .infinity)
                Text("\(original.isRAW ? "RAW" : "Processed source") · \(original.dynamicRange.title) · Original unchanged")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                if let exposure = original.captureExposure {
                    Text("Captured ISO \(Int(exposure.iso)) · \(exposure.seconds.formatted()) s · protection \(exposure.protectedStops.formatted()) EV")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                if let savedMessage { Text(savedMessage).font(.footnote) }
            }
            Section("Development recipe") {
                Picker("Film recipe", selection: Binding(get: { draft.recipe.id }, set: { draft.recipe = viewModel.recipe(for: $0) })) {
                    ForEach(viewModel.recipes) { Text($0.name).tag($0.id) }
                }
                Button("Edit film, tone, grain and color") { editingRecipe = true }.frame(minHeight: 44)
            }
            if original.isRAW {
                Section("RAW exposure and white balance") {
                    control("Exposure (EV)", value: $draft.adjustment.exposure, range: -5...5)
                    Toggle("As-shot white balance", isOn: $draft.adjustment.useAsShotWhiteBalance)
                    if !draft.adjustment.useAsShotWhiteBalance {
                        control("Temperature (K)", value: $draft.adjustment.temperature, range: 2000...12000)
                        control("Tint", value: $draft.adjustment.tint, range: -150...150)
                    }
                    control("Highlight shoulder", value: $draft.adjustment.highlightRecovery, range: 0...1)
                    control("Shadow lift", value: $draft.adjustment.shadowLift, range: 0...1)
                    Text("Highlight development can use information present in the original. It cannot recover sensor-clipped detail. Capture DR protection is fixed by the original exposure, not applied retroactively.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(isSaving ? "Saving development…" : "Save development to Photos") {
                    isSaving = true; error = nil; savedMessage = nil
                    let snapshot = draft
                    Task {
                        defer { isSaving = false }
                        do {
                            try await controller.saveDevelopment(snapshot, photoLibrary: photoLibrary)
                            savedMessage = "Saved a developed copy. Original unchanged."
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(isSaving || controller.isBusy).frame(minHeight: 44)
                Button("Revert to saved development") { draft = original }.disabled(isSaving).frame(minHeight: 44)
                if let originalURL {
                    ShareLink(item: originalURL) { Label("Export unchanged original", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                }
                Text("Development settings are stored as a sidecar when you save. Your shooting recipe and C banks are not changed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Develop Original").navigationBarTitleDisplayMode(.inline)
        .task {
            do { originalURL = try await controller.originalURL(original) }
            catch { self.error = error.localizedDescription }
        }
        .task(id: draft) {
            let generation = UUID(); renderGeneration = generation
            isRendering = true
            do {
                try await Task.sleep(for: .milliseconds(220))
                let data = try await controller.developPreview(draft)
                try Task.checkCancellation()
                guard generation == renderGeneration else { return }
                image = UIImage(data: data); isRendering = false
            } catch is CancellationError {
                if generation == renderGeneration { isRendering = false }
            } catch {
                if generation == renderGeneration { self.error = error.localizedDescription; isRendering = false }
            }
        }
        .sheet(isPresented: $editingRecipe) {
            RecipeDetailView(recipe: draft.recipe, originalRecipe: viewModel.originalRecipe(for: draft.recipe.id),
                isSelected: true, onSelect: { editingRecipe = false }, onCancel: { editingRecipe = false },
                onUpdate: { draft.recipe = $0; editingRecipe = false }, onReset: { draft.recipe = original.recipe })
        }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).monospacedDigit() }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
