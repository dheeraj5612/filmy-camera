import CoreImage
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// This library does not depend on Photos authorization or cache retention.
@MainActor
struct FilmyOriginalsView: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var documents: [FilmyPhotoDocument] = []
    @State private var issue: String?

    var body: some View {
        List {
            Section {
                Text("Originals and editable versions stay in Filmy even after the Roll cache is cleared. Deleting the app deletes this private library; share originals or keep Photos exports as backups.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).foregroundStyle(.orange) }
            if documents.isEmpty {
                ContentUnavailableView("Your next frame starts here", systemImage: "photo.stack",
                                       description: Text("New camera captures retain their originals automatically. Older Roll exports are not retroactively recoverable."))
            }
            ForEach(documents) { document in
                NavigationLink {
                    FilmyPhotoEditorView(documentID: document.id, photoLibrary: photoLibrary)
                } label: {
                    HStack(spacing: 12) {
                        FilmyDocumentThumbnail(id: document.id, revisionID: document.currentRevision?.id)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.currentRevision?.recipe.name ?? "Undeveloped original").font(.headline)
                            Text(document.capturedAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                            Text(document.hasRAW ? "DNG retained" : document.hasLivePhoto ? "Live Photo retained" : "Original retained")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("filmy-document-\(document.id.uuidString)")
            }
        }
        .navigationTitle("Filmy originals")
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("filmy-originals-library")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do {
            let inventory = try await FilmyPhotoStore.shared.inventory()
            documents = inventory.documents
            issue = inventory.unreadableCount > 0 ? "\(inventory.unreadableCount) document(s) could not be read. Their files have not been deleted." : nil
        } catch { issue = error.localizedDescription }
    }
}

@MainActor
private struct FilmyDocumentThumbnail: View {
    let id: UUID
    let revisionID: UUID?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
        }
        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: revisionID) {
            if let data = try? await FilmyPhotoStore.shared.thumbnailData(id) { image = UIImage(data: data) }
        }
    }
}

@MainActor
struct FilmyPhotoEditorView: View {
    let documentID: UUID
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var document: FilmyPhotoDocument?
    @State private var recipe: FilmRecipe?
    @State private var finish: PhotoFinish = .photo
    @State private var preview: UIImage?
    @State private var originalPreview: UIImage?
    @State private var originalURL: URL?
    @State private var rawURL: URL?
    @State private var liveURL: URL?
    @State private var showingOriginal = false
    @State private var showingLive = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var selectedRevisionID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                imagePreview
                if let document, let current = document.currentRevision {
                    Text(document.capturedAt, format: .dateTime.month().day().year().hour().minute()).foregroundStyle(.secondary)
                    Text("\(current.output.format.title) · \(current.output.resolution.title) requested · \(current.output.dynamicRange == .hdr ? "HDR PQ" : "SDR")")
                        .font(.caption).monospacedDigit()
                    Toggle("Compare original", isOn: $showingOriginal).accessibilityIdentifier("filmy-compare-original")
                    if let recipe {
                        Picker("Film look", selection: Binding(get: { recipe.id }, set: { id in
                            self.recipe = FilmRecipe.builtIns.first(where: { $0.id == id })
                        })) {
                            if !FilmRecipe.builtIns.contains(where: { $0.id == recipe.id }) { Text(recipe.name).tag(recipe.id) }
                            ForEach(FilmRecipe.builtIns) { Text($0.name).tag($0.id) }
                        }
                        .accessibilityIdentifier("filmy-edit-recipe")
                    }
                    Picker("Finish", selection: $finish) {
                        Text("Photo").tag(PhotoFinish.photo)
                        Text("Instant Print").tag(PhotoFinish.instantPrint).disabled(document.hasLivePhoto)
                    }.pickerStyle(.segmented)
                    HStack {
                        Button("Preview look") { Task { await develop(save: false) } }.buttonStyle(.bordered)
                        Button("Save version") { Task { await develop(save: true) } }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("filmy-save-version")
                    }
                    Text("Editing previews are SDR and limited to 1800 pixels. HDR is preserved in the saved HEIF when selected. Save version renders from the retained original at the selected output resolution. Every save creates a new version.")
                        .font(.caption).foregroundStyle(.secondary)
                    revisionPicker(document)
                    exportControls(document)
                }
                if busy { ProgressView("Processing photo").frame(maxWidth: .infinity) }
                if let message { Text(message).font(.callout).accessibilityIdentifier("filmy-document-message") }
                Button("Delete Filmy original and versions", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("filmy-delete-original")
            }
            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle("Develop again")
        .toolbar(.visible, for: .navigationBar)
        .disabled(busy)
        .task { await load() }
        .confirmationDialog("Delete this Filmy original?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete original and all versions", role: .destructive) {
                Task {
                    do { try await FilmyPhotoStore.shared.delete(documentID); dismiss() }
                    catch { message = error.localizedDescription }
                }
            }
        } message: { Text("This cannot be undone. Existing exports in Apple Photos will not be deleted.") }
    }

    private var imagePreview: some View {
        Group {
            if showingLive, let originalURL, let liveURL {
                OriginalLivePhotoView(photoURL: originalURL, movieURL: liveURL)
                    .frame(height: 400).accessibilityLabel("Original Live Photo. Touch and hold to play.")
            } else if let image = showingOriginal ? originalPreview : preview {
                Image(uiImage: image).resizable().scaledToFit().allowedDynamicRange(.high)
                    .frame(maxHeight: 520).clipShape(RoundedRectangle(cornerRadius: 14))
            } else { ContentUnavailableView("Develop the original", systemImage: "camera.filters") }
        }
    }

    private func revisionPicker(_ document: FilmyPhotoDocument) -> some View {
        Picker("Load a version", selection: Binding(get: { selectedRevisionID ?? document.revisions[0].id }, set: { id in
            selectedRevisionID = id
            guard let revision = document.revisions.first(where: { $0.id == id }) else { return }
            recipe = revision.recipe
            finish = revision.finish
            Task { await showRendition(revisionID: id) }
        })) {
            ForEach(Array(document.revisions.enumerated()), id: \.element.id) { index, revision in
                Text("\(index == 0 ? "Capture settings" : "Version \(index)") · \(revision.recipe.name)").tag(revision.id)
            }
        }
        .accessibilityIdentifier("filmy-edit-history")
    }

    private func exportControls(_ document: FilmyPhotoDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Export saved version").font(.headline)
            Button(document.photosAssetIdentifier == nil ? "Save to Photos" : "Update linked Photos asset") {
                Task { await export(asNewCopy: false) }
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("filmy-export-photos")
            if document.photosAssetIdentifier != nil {
                Button("Export a new Photos copy") { Task { await export(asNewCopy: true) } }.buttonStyle(.bordered)
            }
            Text("Exports use the most recently saved version. Existing Photos edits from another app are not overwritten.")
                .font(.caption).foregroundStyle(.secondary)
            if let originalURL { ShareLink("Share processed original", item: originalURL) }
            if let rawURL { ShareLink("Share original DNG", item: rawURL) }
            if let liveURL { ShareLink("Share original Live movie", item: liveURL) }
            if liveURL != nil { Toggle("Play original Live Photo", isOn: $showingLive) }
            Text("Original files retain their original metadata. Filmy renders looks from the processed companion, not a new RAW demosaic.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            let value = try await FilmyPhotoStore.shared.load(documentID)
            document = value
            recipe = value.currentRevision?.recipe
            finish = value.currentRevision?.finish ?? .photo
            selectedRevisionID = value.currentRevision?.id
            originalURL = try await FilmyPhotoStore.shared.originalURL(documentID)
            rawURL = value.hasRAW ? try await FilmyPhotoStore.shared.originalURL(documentID, raw: true) : nil
            liveURL = try await FilmyPhotoStore.shared.liveMovieURL(documentID)
            let source = try await FilmyPhotoStore.shared.originalData(documentID)
            originalPreview = await Task.detached(priority: .userInitiated) { Self.thumbnail(source) }.value
            await showRendition(revisionID: value.currentRevision?.id)
        } catch { message = error.localizedDescription }
    }

    private func showRendition(revisionID: UUID?) async {
        guard let revisionID else { return }
        if let url = try? await FilmyPhotoStore.shared.renditionURL(documentID, revisionID: revisionID) {
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return Self.thumbnail(data)
            }.value
            guard selectedRevisionID == revisionID else { return }
            preview = image
        } else { preview = originalPreview }
    }

    private func develop(save: Bool) async {
        guard !busy, let document, let current = document.currentRevision, let recipe else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await FilmyPhotoStore.shared.originalData(documentID)
            let selectedFinish = finish
            let rendered = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    let source: Data
                    var output = current.output
                    if save { source = data }
                    else {
                        guard let thumbnail = Self.thumbnail(data), let previewData = thumbnail.jpegData(compressionQuality: 0.98) else {
                            return CameraViewModel.RenderedPhoto?.none
                        }
                        source = previewData
                        output.dynamicRange = .sdr
                        output.format = .jpeg
                        output.livePhoto = false
                    }
                    return CameraViewModel.render(
                        sourceData: source, recipe: recipe,
                        viewportSize: CGSize(width: document.geometry.viewportWidth, height: document.geometry.viewportHeight),
                        previewDrawableSize: CGSize(width: document.geometry.previewWidth, height: document.geometry.previewHeight),
                        capturedAt: document.capturedAt, flashFired: document.geometry.flashFired,
                        grainSeed: document.geometry.grainSeed, finish: selectedFinish, outputSettings: output
                    )
                }
            }.value
            guard let rendered else { throw FilmyPhotoStore.StoreError.missingRendition }
            preview = rendered.image
            showingOriginal = false
            showingLive = false
            if save {
                let updated = try await FilmyPhotoStore.shared.addRevision(
                    documentID, expectedRevisionID: current.id, recipe: recipe, finish: selectedFinish,
                    settings: current.output, renderedData: rendered.data
                )
                self.document = updated
                selectedRevisionID = updated.currentRevision?.id
                message = "New version saved. Your original is unchanged."
            } else { message = "Preview only. Save version before exporting." }
        } catch { message = error.localizedDescription }
    }

    private func export(asNewCopy: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let identifier = try await FilmyPhotosExporter.save(documentID, asNewCopy: asNewCopy)
            if let document, let revision = document.currentRevision {
                await photoLibrary.registerDocumentExport(identifier, recipe: revision.recipe,
                                                          capturedAt: document.capturedAt, thumbnail: preview)
            }
            await load()
            message = "Saved to Photos with original resources and reversible Filmy edits."
        } catch { message = error.localizedDescription }
    }

    nonisolated private static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1800, kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct OriginalLivePhotoView: UIViewRepresentable {
    let photoURL: URL
    let movieURL: URL
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.isMuted = true
        PHLivePhoto.request(withResourceFileURLs: [photoURL, movieURL], placeholderImage: nil,
                            targetSize: CGSize(width: 1000, height: 1000), contentMode: .aspectFit) { [weak view] photo, _ in
            DispatchQueue.main.async { view?.livePhoto = photo }
        }
        return view
    }
    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {}
    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: ()) { uiView.stopPlayback(); uiView.livePhoto = nil }
}
