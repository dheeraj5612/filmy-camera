import CoreImage
import PhotosUI
import SwiftUI

struct FilmyOriginalsView: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [FilmyPhotoProject] = []
    @State private var message: String?
    @State private var unreadableCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Originals stay untouched. Change a look, save an edit, or return to the captured recipe at any time.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let message { Text(message).foregroundStyle(FilmyTheme.danger) }
                    if unreadableCount > 0 {
                        Text("\(unreadableCount) project files could not be opened. Their originals have not been removed.")
                            .font(.caption).foregroundStyle(FilmyTheme.danger)
                    }
                    if projects.isEmpty {
                        ContentUnavailableView("No Filmy originals yet", systemImage: "photo.stack",
                            description: Text("New camera captures keep their originals here. Older Roll photos are not retroactively recoverable."))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16) {
                            ForEach(projects) { project in
                                NavigationLink {
                                    FilmyProjectEditor(project: project, photoLibrary: photoLibrary)
                                } label: { FilmyProjectTile(project: project) }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(20)
            }
            .background(FilmyTheme.background)
            .navigationTitle("Filmy originals")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
        }
        .accessibilityIdentifier("filmy-originals-library")
    }
    private func reload() async {
        do {
            let listing = try await FilmyPhotoStore.shared.list()
            projects = listing.photos
            unreadableCount = listing.unreadableCount
            message = nil
        } catch { message = error.localizedDescription }
    }
}

private struct FilmyProjectTile: View {
    let project: FilmyPhotoProject
    @State private var preview: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(FilmyTheme.panel)
                if let preview { Image(uiImage: preview).resizable().scaledToFill() }
                else { Image(systemName: "photo").font(.largeTitle) }
            }
            .frame(height: 156).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(project.edit.recipe.name).font(.caption.weight(.semibold)).lineLimit(1)
            Text(project.capturedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
            Text(project.rawFilename != nil ? "RAW retained" : project.movieFilename != nil ? "Live original" : "Original retained")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: project.revision) {
            if let image = try? await FilmyPhotoStore.shared.preview(project.id, original: false, maximum: 512, hdr: false) {
                preview = UIImage(cgImage: image.image)
            }
        }
    }
}

private struct FilmyProjectEditor: View {
    @State var project: FilmyPhotoProject
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var edit: FilmyPhotoEdit
    @State private var image: UIImage?
    @State private var showingOriginal = false
    @State private var choosingLook = false
    @State private var showingLive = false
    @State private var liveURLs: [URL] = []
    @State private var rawURL: URL?
    @State private var busy = false
    @State private var message: String?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(project: FilmyPhotoProject, photoLibrary: PhotoLibraryService) {
        _project = State(initialValue: project)
        _edit = State(initialValue: project.edit)
        self.photoLibrary = photoLibrary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FilmyHDRImage(image: image)
                    .frame(height: 350).background(.black, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(showingOriginal ? "Unmodified processed original" : "Saved Filmy edit")
                Toggle("Show original", isOn: $showingOriginal)
                    .accessibilityIdentifier("filmy-project-original")
                if let dimensions = project.outputDimensions, !showingOriginal {
                    Text("\(dimensions.width) × \(dimensions.height) · \(project.outputHasHDRGainMap ? "HDR gain map" : "SDR") · revision \(project.revision)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                LabeledContent("Saved recipe", value: project.edit.recipe.name)
                Button("Choose look: \(edit.recipe.name)") { choosingLook = true }
                    .buttonStyle(.bordered).accessibilityIdentifier("filmy-project-choose-look")
                Text("Choosing a recipe stages an edit. The preview remains the saved version until you tap Save edit.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Finish", selection: $edit.finish) {
                    Text("Photo").tag(PhotoFinish.photo)
                    Text("Instant print").tag(PhotoFinish.instantPrint)
                }
                Picker("Export format", selection: $edit.options.codec) {
                    Text("JPEG · sRGB").tag(ProCaptureOptions.Codec.jpeg)
                    Text("HEIF · P3").tag(ProCaptureOptions.Codec.heif)
                }
                if #available(iOS 18.0, *), edit.options.codec == .heif {
                    Toggle("Preserve source HDR highlights", isOn: $edit.options.hdr)
                }
                Button(busy ? "Working…" : "Save edit") { save(edit) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("filmy-project-save")
                Button("Revert to captured recipe") { save(project.initialEdit) }
                    .buttonStyle(.bordered).accessibilityIdentifier("filmy-project-revert")
                Divider()
                Button("Export saved edit to Photos") { exportEdit() }
                    .buttonStyle(.bordered).disabled(project.renditionFilename == nil)
                Button(project.originalPhotosIdentifier == nil ? "Export original to Photos" : "Export another original copy") {
                    exportOriginal()
                }.buttonStyle(.bordered)
                if let rawURL { ShareLink("Share original DNG", item: rawURL).buttonStyle(.bordered) }
                if !liveURLs.isEmpty {
                    Button("Play Live original") { showingLive = true }.buttonStyle(.bordered)
                    Text("The Live original is silent. Its movie is unfiltered; the saved Filmy edit is a separate still.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Original exports preserve original camera metadata. Edits use a metadata allowlist without location data. Deleting the app removes local originals; export important captures first.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Delete local project", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.bordered)
            }
            .disabled(busy)
            .padding(20)
        }
        .background(FilmyTheme.background)
        .navigationTitle("Develop photo")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(project.revision)-\(showingOriginal)") { await loadPreview() }
        .task {
            if let name = project.rawFilename { rawURL = try? await FilmyPhotoStore.shared.resourceURL(project.id, filename: name) }
            if let name = project.movieFilename,
               let still = try? await FilmyPhotoStore.shared.resourceURL(project.id, filename: project.originalFilename),
               let movie = try? await FilmyPhotoStore.shared.resourceURL(project.id, filename: name) { liveURLs = [still, movie] }
        }
        .sheet(isPresented: $choosingLook) {
            FilmyProjectLookPicker { recipe in edit.recipe = recipe; choosingLook = false }
        }
        .sheet(isPresented: $showingLive) {
            NavigationStack {
                FilmyLivePhotoView(urls: liveURLs).background(.black)
                    .navigationTitle("Live original")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingLive = false } } }
            }
        }
        .confirmationDialog("Delete this local project and all of its originals?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete local project", role: .destructive) {
                busy = true
                Task {
                    do { try await FilmyPhotoStore.shared.delete(project.id); dismiss() }
                    catch { message = error.localizedDescription; busy = false }
                }
            }
        } message: { Text("This cannot be undone. Copies already exported to Photos are not deleted.") }
        .accessibilityIdentifier("filmy-project-editor")
    }

    private func loadPreview() async {
        do {
            let payload = try await FilmyPhotoStore.shared.preview(project.id, original: showingOriginal, maximum: 1536, hdr: true)
            guard !Task.isCancelled else { return }
            image = UIImage(cgImage: payload.image)
        } catch { message = error.localizedDescription }
    }
    private func save(_ requestedEdit: FilmyPhotoEdit) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                project = try await FilmyPhotoStore.shared.render(project.id, edit: requestedEdit, expectedRevision: project.revision)
                edit = project.edit
                showingOriginal = false
                message = "Edit saved. Original unchanged."
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func exportOriginal() {
        busy = true
        Task {
            do {
                try await FilmyPhotoStore.shared.exportOriginal(project.id, forceCopy: project.originalPhotosIdentifier != nil)
                project = try await FilmyPhotoStore.shared.load(project.id)
                message = "Original saved to Photos."
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func exportEdit() {
        guard let filename = project.renditionFilename else { return }
        busy = true
        Task {
            do {
                let data = try await FilmyPhotoStore.shared.data(project.id, filename: filename)
                photoLibrary.save(image: image ?? UIImage(), imageData: data, recipe: project.edit.recipe, capturedAt: project.capturedAt) { result in
                    switch result {
                    case .success: message = "Saved edit exported to Photos."
                    case .failure(let error): message = error.localizedDescription
                    }
                    busy = false
                }
            } catch { message = error.localizedDescription; busy = false }
        }
    }
}

private struct FilmyProjectLookPicker: View {
    let select: (FilmRecipe) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var recipes: [FilmRecipe] {
        FilmRecipe.builtIns.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List(recipes) { recipe in Button(recipe.name) { select(recipe) } }
                .searchable(text: $query, prompt: "Find a look")
                .navigationTitle("Choose look")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct FilmyHDRImage: UIViewRepresentable {
    let image: UIImage?
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.preferredImageDynamicRange = .high
        return view
    }
    func updateUIView(_ uiView: UIImageView, context: Context) { uiView.image = image }
}

private struct FilmyLivePhotoView: UIViewRepresentable {
    let urls: [URL]
    final class Coordinator: @unchecked Sendable {
        var request: PHLivePhotoRequestID?
        var urls: [URL] = []
        var token = UUID()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }
    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        let coordinator = context.coordinator
        guard urls != coordinator.urls else { return }
        if let request = coordinator.request { PHLivePhoto.cancelRequest(withRequestID: request) }
        coordinator.urls = urls
        let token = UUID()
        coordinator.token = token
        coordinator.request = PHLivePhoto.request(withResourceFileURLs: urls, placeholderImage: nil,
            targetSize: CGSize(width: 1440, height: 1440), contentMode: .aspectFit) { [weak uiView] photo, info in
                DispatchQueue.main.async {
                    guard coordinator.token == token, (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true else { return }
                    uiView?.livePhoto = photo
                    uiView?.startPlayback(with: .full)
                }
            }
    }
    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.token = UUID()
        if let request = coordinator.request { PHLivePhoto.cancelRequest(withRequestID: request) }
        uiView.stopPlayback()
    }
}
