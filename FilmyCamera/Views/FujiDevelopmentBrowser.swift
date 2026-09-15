import SwiftUI

struct FujiDevelopmentBrowser: View {
    @ObservedObject var shooting: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var deleteCandidate: FujiStoredPhoto?

    var body: some View {
        List {
            Section {
                Toggle("Retain RAW for new captures", isOn: $shooting.settings.retainRAW)
                Text("RAW-capable lenses capture a real DNG. Unsupported lenses report an error, never a renamed JPEG. All shooting-system originals remain in this on-device library until you delete them. Photos exports are developed JPEG copies.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Development library · 2 GB limit") {
                if shooting.storedPhotos.isEmpty { Text("No retained captures yet.").foregroundStyle(.secondary) }
                ForEach(shooting.storedPhotos) { record in
                    NavigationLink {
                        FujiDevelopmentEditor(record: record, shooting: shooting, viewModel: viewModel, photoLibrary: photoLibrary)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.recipe.name).font(.headline)
                            Text(record.metadata.sourceKind.title).font(.caption)
                            Text(record.metadata.capturedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            Text(record.exportedToPhotos ? "Exported to Photos" : "Original retained · not exported")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete original", role: .destructive) { deleteCandidate = record }
                    }
                }
            }
        }
        .navigationTitle("RAW development")
        .task { await shooting.refreshLibrary() }
        .refreshable { await shooting.refreshLibrary() }
        .confirmationDialog("Delete this retained original and its edit settings? Photos copies are not deleted.",
                            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("Delete original", role: .destructive) {
                guard let record = deleteCandidate else { return }
                deleteCandidate = nil
                Task {
                    do { try await FujiDevelopmentLibrary.shared.delete(record); await shooting.refreshLibrary() }
                    catch { shooting.errorMessage = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        }
    }
}

struct FujiDevelopmentEditor: View {
    @State var record: FujiStoredPhoto
    @ObservedObject var shooting: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var preview: UIImage?
    @State private var originalURL: URL?
    @State private var isWorking = false
    @State private var rendering = false
    @State private var message: String?
    @State private var renderRevision = 0

    var body: some View {
        Form {
            Section {
                if let preview { Image(uiImage: preview).resizable().scaledToFit().listRowInsets(EdgeInsets()) }
                if rendering { ProgressView("Developing preview") }
                Text(record.metadata.sourceKind.title).font(.caption)
                LabeledContent("Capture DR", value: record.metadata.dynamicRange.title)
                if let iso = record.metadata.iso { LabeledContent("Recorded ISO", value: iso.formatted(.number.precision(.fractionLength(0)))) }
                if let duration = record.metadata.durationSeconds {
                    LabeledContent("Recorded exposure", value: "\(duration.formatted(.number.precision(.fractionLength(6)))) s")
                }
                if let count = record.metadata.temporalFrameCount { LabeledContent("Source frames", value: "\(count)") }
                if let duration = record.metadata.temporalElapsedSeconds {
                    LabeledContent("Sample span", value: "\(duration.formatted(.number.precision(.fractionLength(2)))) s")
                }
            }
            Section("Development · original unchanged") {
                Picker("Film recipe", selection: Binding(get: { record.recipe.id }, set: { record.recipe = viewModel.recipe(for: $0) })) {
                    ForEach(viewModel.recipes) { Text($0.name).tag($0.id) }
                }
                Slider(value: adjustment(\.exposureEV), in: -3...3, step: 1 / 3) { Text("Push / pull") }
                Text("Push / pull: \(record.adjustments.exposureEV.formatted(.number.precision(.fractionLength(2)))) EV")
                Toggle("As-shot white balance", isOn: Binding(get: { record.adjustments.temperature == nil }, set: {
                    record.adjustments.temperature = $0 ? nil : 5600
                }))
                if record.adjustments.temperature != nil {
                    Slider(value: Binding(get: { record.adjustments.temperature ?? 5600 }, set: { record.adjustments.temperature = $0 }),
                           in: 2500...10000, step: 100) { Text("Temperature") }
                    Text("\(Int(record.adjustments.temperature ?? 5600)) K")
                }
                Slider(value: adjustment(\.tint), in: -150...150) { Text("Tint") }
                Slider(value: adjustment(\.highlights), in: -1...1) { Text("Highlight tone") }
                Slider(value: adjustment(\.shadows), in: -1...1) { Text("Shadow tone") }
                if record.metadata.sourceKind.isRAW {
                    Slider(value: adjustment(\.sharpness), in: 0...1) { Text("RAW sharpness") }
                    Slider(value: adjustment(\.noiseReduction), in: 0...1) { Text("RAW noise reduction") }
                }
                Button("Reset development") { record.adjustments = .init() }
                Text("DR is capture metadata and cannot be changed after capture. Film colors are independent approximations, not Fujifilm's proprietary RAW converter. Grain and other recipe controls come from the chosen, customizable film recipe.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Save development settings") {
                    Task {
                        do { try await FujiDevelopmentLibrary.shared.update(record); message = "Edit settings saved. Original unchanged." }
                        catch { message = error.localizedDescription }
                    }
                }
                Button(record.exportedToPhotos ? "Export another JPEG copy" : "Export JPEG to Photos") {
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        do {
                            try await shooting.export(record, photoLibrary: photoLibrary)
                            record.exportedToPhotos = true
                            message = "Developed copy saved to Photos."
                            await shooting.refreshLibrary()
                        } catch { message = error.localizedDescription }
                    }
                }
                if let originalURL { ShareLink("Share unchanged original", item: originalURL) }
                if isWorking { ProgressView("Exporting") }
                if let message { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Develop original")
        .disabled(isWorking)
        .interactiveDismissDisabled(isWorking)
        .navigationBarBackButtonHidden(isWorking)
        .onChange(of: record.recipe) { _, _ in renderRevision += 1 }
        .onChange(of: record.adjustments) { _, _ in renderRevision += 1 }
        .task(id: renderRevision) { await renderPreview() }
        .task { originalURL = await FujiDevelopmentLibrary.shared.sourceURL(for: record) }
    }

    private func adjustment(_ path: WritableKeyPath<FujiDevelopmentAdjustments, Double>) -> Binding<Double> {
        Binding(get: { record.adjustments[keyPath: path] }, set: { record.adjustments[keyPath: path] = $0 })
    }

    private func renderPreview() async {
        do {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            rendering = true
            let edit = record
            let frame = try await FujiDevelopmentLibrary.shared.frame(for: edit)
            let result = try await FujiWork.run {
                try FujiDevelopmentPipeline.develop(frame, recipe: edit.recipe, adjustments: edit.adjustments,
                                                   cropFactor: edit.cropFactor, aspectRatio: edit.aspectRatio, longEdge: 1000, finish: edit.finish)
            }
            try Task.checkCancellation()
            preview = result.image
            rendering = false
        } catch {
            guard !Task.isCancelled else { return }
            rendering = false
            message = error.localizedDescription
        }
    }
}
