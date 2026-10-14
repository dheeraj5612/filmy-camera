import CoreImage
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private struct FilmyDecodedThumbnail: @unchecked Sendable { let image: UIImage }

/// This library does not depend on Photos authorization or cache retention.
@MainActor
struct FilmyOriginalsView: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var documents: [FilmyPhotoDocument] = []
    @State private var issue: String?
    @State private var hasLoaded = false
    @State private var owedIDs: Set<UUID> = []

    var body: some View {
        List {
            Section {
                Text("Originals and editable versions stay in Filmy even after the Roll cache is cleared. Deleting the app deletes this private library; share originals or keep Photos exports as backups.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).foregroundStyle(.orange) }
            if !hasLoaded && documents.isEmpty {
                ProgressView("Loading originals").frame(maxWidth: .infinity)
            } else if documents.isEmpty && issue == nil {
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
                            if document.photosAssetIdentifier == nil && owedIDs.contains(document.id) {
                                Text("Not in Photos yet")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("filmy-document-photos-pending")
                            }
                        }
                    }
                }
                .accessibilityIdentifier("filmy-document-\(document.id.uuidString)")
            }
        }
        .navigationTitle("Filmy originals")
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("filmy-originals-library")
        .onAppear { Task { await refresh() } }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        defer { hasLoaded = true }
        do {
            let inventory = try await FilmyPhotoStore.shared.inventory()
            documents = inventory.documents
            owedIDs = await FilmyPhotoStore.shared.photosExportOwedIDs()
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
            image = nil
            guard let data = try? await FilmyPhotoStore.shared.thumbnailData(id) else { return }
            let decoded = await ImageDecodeQueue.shared.value { () -> FilmyDecodedThumbnail? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 128,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                return FilmyDecodedThumbnail(image: UIImage(cgImage: thumbnail))
            }
            guard !Task.isCancelled else { return }
            image = decoded?.image
        }
    }
}

@MainActor
struct FilmyPhotoEditorView: View {
    let documentID: UUID
    @ObservedObject var photoLibrary: PhotoLibraryService
    /// Edit look from the Roll viewer: one Save as new frame action, no
    /// delete, no overwrite of the linked Photos asset.
    var savesAsNewFrame = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var document: FilmyPhotoDocument?
    @State private var recipe: FilmRecipe?
    @State private var finish: PhotoFinish = .photo
    @State private var preview: UIImage?
    @State private var loadingRendition = false
    @State private var originalPreview: UIImage?
    @State private var originalURL: URL?
    @State private var rawURL: URL?
    @State private var liveURL: URL?
    @State private var showingOriginal = false
    /// True while a look or finish pick renders its preview.
    @State private var developingPreview = false
    @State private var showingLookLibrary = false
    @State private var showingLive = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var selectedRevisionID: UUID?
    /// Version saved by Save as new frame whose Photos export has not succeeded yet.
    @State private var newFrameAwaitingExport: UUID?
    /// The Photos link the document had before the first export of that version.
    @State private var linkBeforeNewFrameExport: String?

    init(documentID: UUID, photoLibrary: PhotoLibraryService, savesAsNewFrame: Bool = false) {
        self.documentID = documentID
        self.photoLibrary = photoLibrary
        self.savesAsNewFrame = savesAsNewFrame
    }

    var body: some View {
        GeometryReader { geometry in
            editorLayout(size: geometry.size)
        }
        .background(FilmyTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .navigationTitle(savesAsNewFrame ? "Edit look" : "Develop again")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { editLookToolbar }
        .interactiveDismissDisabled(savesAsNewFrame && busy)
        .disabled(busy)
        .sheet(isPresented: $showingLookLibrary) { lookLibrarySheet() }
        .task { await load() }
        .onChange(of: message) { _, newValue in
            if let newValue { UIAccessibility.post(notification: .announcement, argument: newValue) }
        }
        .confirmationDialog("Delete this Filmy original?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete original and all versions", role: .destructive) {
                Task {
                    do { try await FilmyPhotoStore.shared.delete(documentID); dismiss() }
                    catch { message = error.localizedDescription }
                }
            }
        } message: { Text("This cannot be undone. Existing exports in Apple Photos will not be deleted.") }
    }

    private func editorLayout(size: CGSize) -> some View {
        let width = min(size.width, 760)
        let maxBox = photoMaxBox(width: width, available: size.height)
        return VStack(spacing: 0) {
            photoArea(maxBox: maxBox)
            ScrollView {
                secondaryControls
                    .padding(.horizontal, FilmyTheme.pageMargin)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: width)
        .frame(maxWidth: .infinity)
    }

    /// Largest box the photo may fill. Non-accessibility sizes keep 124 pt for
    /// the controls below the photo; accessibility sizes give it 55%.
    private func photoMaxBox(width: CGFloat, available: CGFloat) -> CGSize {
        let boxWidth = max(width - FilmyTheme.pageMargin, 1)
        let boxHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
            ? max(available * 0.55, 160)
            : max(available - 124, 160)
        return CGSize(width: boxWidth, height: boxHeight)
    }

    private func photoArea(maxBox: CGSize) -> some View {
        imagePreview(maxBox: maxBox)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var secondaryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if busy { ProgressView("Processing photo").frame(maxWidth: .infinity) }
            if let document, let editing = document.revisionForEditing(selectedRevisionID) {
                editingControls(document, editing)
            }
            if !savesAsNewFrame {
                Button("Delete Filmy original and versions", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("filmy-delete-original")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editingControls(_ document: FilmyPhotoDocument, _ editing: FilmyPhotoRevision) -> some View {
        if let recipe { lookRow(recipe) }
        Toggle("Compare original", isOn: $showingOriginal).accessibilityIdentifier("filmy-compare-original")
        finishRow(document)
        revisionPicker(document)
        detailsGroup(document, editing)
        exportControls(document)
    }

    private func lookRow(_ recipe: FilmRecipe) -> some View {
        let nameLines: Int = dynamicTypeSize.isAccessibilitySize ? 3 : 1
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            showingLookLibrary = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.filters").foregroundStyle(FilmyTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Film look")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FilmyTheme.secondary)
                    Text(recipe.name)
                        .font(.headline)
                        .foregroundStyle(FilmyTheme.primary)
                        .lineLimit(nameLines)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(FilmyTheme.panel, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Film look")
        .accessibilityValue(recipe.name)
        .accessibilityHint("Opens the look library. Your original is unchanged.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("filmy-edit-recipe")
    }

    /// Looks offered by the library: allowed built-ins with the user's saved
    /// look edits resolved behind full access, read only. The frame's own look
    /// maps to the recipe saved in its version so re-picking restores it.
    private var editorRecipes: [FilmRecipe] {
        let stock: [FilmRecipe] = FilmRecipe.builtIns.filter { AppConfiguration.isRecipeAllowed($0.id) }
        var overrides: [String: FilmRecipe] = [:]
        if MembershipStore.shared.hasFullAccess {
            let stored: Data? = UserDefaults.standard.data(forKey: CameraViewModel.recipeOverridesKey)
            overrides = CameraViewModel.decodeRecipeOverrides(from: stored).recipes
        }
        let savedRecipe: FilmRecipe? = document?.revisionForEditing(selectedRevisionID)?.recipe
        return stock.map { base -> FilmRecipe in
            if let savedRecipe, savedRecipe.id == base.id { return savedRecipe }
            guard let saved = overrides[base.id] else { return base }
            var resolved: FilmRecipe = base
            resolved.applyControlValues(from: saved)
            resolved.markUserModified(parentRecipeID: base.id)
            return resolved
        }
    }

    private func lookLibrarySheet() -> some View {
        LookLibraryView(
            recipes: editorRecipes,
            selectedRecipeID: recipe?.id ?? "",
            selectionIdentifierPrefix: "filmy-look",
            subtitle: "Choose a look for this photo. Your original is unchanged.",
            onSelect: { (candidate: FilmRecipe) in selectLook(candidate) },
            onClose: { showingLookLibrary = false }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(FilmyTheme.background)
        .presentationCornerRadius(28)
    }

    private func selectLook(_ candidate: FilmRecipe) {
        guard !busy else { return }
        showingLookLibrary = false
        guard candidate.id != recipe?.id else { return }
        recipe = candidate
        startPreview()
    }

    private func detailsGroup(_ document: FilmyPhotoDocument, _ editing: FilmyPhotoRevision) -> some View {
        DisclosureGroup("Details") {
            VStack(alignment: .leading, spacing: 8) {
                Text(document.capturedAt, format: .dateTime.month().day().year().hour().minute()).foregroundStyle(.secondary)
                Text("\(editing.output.format.title) · \(editing.output.resolution.title) requested · \(editing.output.dynamicRange == .hdr ? "HDR PQ" : "SDR")")
                    .font(.caption).monospacedDigit()
                Text("Editing previews are SDR and limited to 1800 pixels. HDR is preserved in the saved HEIF when selected. \(saveActionName) renders from the retained original at the selected output resolution. Every save creates a new version.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .accessibilityIdentifier("filmy-edit-details")
    }

    private func finishRow(_ document: FilmyPhotoDocument) -> some View {
        let isAX = dynamicTypeSize.isAccessibilitySize
        let layout: AnyLayout = isAX
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text("Finish")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.secondary)
                .accessibilityHidden(true)
            finishTrack(document)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmy-edit-finish")
    }

    private func finishTrack(_ document: FilmyPhotoDocument) -> some View {
        HStack(spacing: 0) {
            finishSegment(.photo, title: "Photo", identifier: "filmy-edit-finish-photo", isDisabled: false)
            finishSegment(.instantPrint, title: "Instant Print", identifier: "filmy-edit-finish-instant",
                          isDisabled: document.hasLivePhoto)
        }
        .frame(maxWidth: .infinity)
        .background(FilmyTheme.panel, in: Capsule())
        .overlay(Capsule().stroke(FilmyTheme.line, lineWidth: 1))
    }

    private func finishSegment(_ target: PhotoFinish, title: String, identifier: String, isDisabled: Bool) -> some View {
        let isSelected = finish == target
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        return Button {
            selectFinish(target)
        } label: {
            trackSegmentLabel(title, isSelected: isSelected).frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel("Finish, \(title)")
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier(identifier)
    }

    private func trackSegmentLabel(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .font(.caption.weight(.bold))
            .foregroundStyle(isSelected ? FilmyTheme.background : FilmyTheme.primary)
            .padding(.horizontal, 12)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: 48)
            .background {
                if isSelected {
                    Capsule().fill(FilmyTheme.accent).padding(3)
                }
            }
            .contentShape(Rectangle())
    }

    private func selectFinish(_ new: PhotoFinish) {
        guard new != finish else { return }
        finish = new
        startPreview()
    }

    /// A look or finish pick previews through the same render call as Save.
    private func startPreview() {
        Task {
            developingPreview = true
            await develop(save: false)
            developingPreview = false
        }
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            messageLine
            saveButton
        }
        .padding(.horizontal, FilmyTheme.pageMargin)
        .padding(.vertical, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(FilmyTheme.background)
        .overlay(alignment: .top) { Divider() }
    }

    /// Reserves one footnote row so short messages never resize the photo;
    /// long errors wrap in full, next to Save.
    private var messageLine: some View {
        ZStack(alignment: .leading) {
            Text(" ").font(.footnote).hidden()
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(FilmyTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("filmy-document-message")
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if savesAsNewFrame {
            Button("Save as new frame") { Task { await saveAsNewFrame() } }
                .buttonStyle(.filmyPrimary)
                .disabled(document == nil)
                .accessibilityHint("Saves this look as a new version and adds it to your Roll as a new frame. This frame is kept.")
                .accessibilityIdentifier("filmy-save-new-frame")
        } else {
            Button("Save version") { Task { await develop(save: true) } }
                .buttonStyle(.filmyPrimary)
                .disabled(document == nil)
                .accessibilityIdentifier("filmy-save-version")
        }
    }

    /// An unsaved look or finish: the selection differs from the version shown.
    private var hasUnsavedChanges: Bool {
        guard let recipe, let editing = document?.revisionForEditing(selectedRevisionID) else { return false }
        return recipe.id != editing.recipe.id || finish != editing.finish
    }

    /// Only an unsaved pick reads Cancel; a saved version whose export failed
    /// is kept in Originals, so closing then reads Done.
    private var showsCancel: Bool { hasUnsavedChanges }

    private var doneTitle: String { showsCancel ? "Cancel" : "Done" }

    private var doneHint: String {
        if hasUnsavedChanges { return "Closes without saving this look." }
        if newFrameAwaitingExport != nil { return "Your saved version stays in Originals." }
        return ""
    }

    @ToolbarContentBuilder
    private var editLookToolbar: some ToolbarContent {
        if savesAsNewFrame {
            ToolbarItem(placement: .cancellationAction) {
                Button(doneTitle) { dismiss() }
                    .disabled(busy)
                    .accessibilityHint(doneHint)
                    .accessibilityIdentifier("gallery-edit-look-done")
            }
        }
    }

    private var displayedImage: UIImage? { showingOriginal ? originalPreview : preview }

    @ViewBuilder
    private func imagePreview(maxBox: CGSize) -> some View {
        if showingLive, let originalURL, let liveURL {
            OriginalLivePhotoView(photoURL: originalURL, movieURL: liveURL)
                .frame(width: maxBox.width, height: maxBox.height)
                .accessibilityLabel("Original Live Photo. Touch and hold to play.")
        } else if let image = displayedImage {
            let fitted = CaptureReviewView.fittedSize(for: image.size, within: maxBox)
            Image(uiImage: image).resizable().scaledToFit().allowedDynamicRange(.high)
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: FilmyTheme.viewfinderCornerRadius))
        } else if loadingRendition {
            ProgressView("Loading version").frame(width: maxBox.width, height: min(maxBox.height, 240))
        } else {
            ContentUnavailableView("Develop the original", systemImage: "camera.filters")
                .frame(width: maxBox.width, height: min(maxBox.height, 240))
        }
    }

    private func revisionPicker(_ document: FilmyPhotoDocument) -> some View {
        Picker("Load a version", selection: Binding(get: { selectedRevisionID ?? document.revisions[0].id }, set: { id in
            selectedRevisionID = id
            message = nil
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
            // Edit look saves and exports in one step (Save as new frame), so it shows no export buttons.
            if savesAsNewFrame {
                Text("Original files").font(.headline)
            } else {
                Text("Export saved version").font(.headline)
                Button(document.photosAssetIdentifier == nil ? "Save to Photos" : "Update linked Photos asset") {
                    Task { await export(asNewCopy: false) }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("filmy-export-photos")
                if document.photosAssetIdentifier != nil {
                    Button("Export a new Photos copy") { Task { await export(asNewCopy: true) } }.buttonStyle(.bordered)
                }
                Text("Exports use the most recently saved version. Existing Photos edits from another app are not overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let originalURL { ShareLink("Share processed original", item: originalURL) }
            if let rawURL { ShareLink("Share original DNG", item: rawURL) }
            if let liveURL { ShareLink("Share original Live movie", item: liveURL) }
            if liveURL != nil { Toggle("Play original Live Photo", isOn: $showingLive) }
            Text("Original files retain their original metadata. Filmy renders looks from the processed companion, not a new RAW demosaic.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        loadingRendition = true
        do {
            let value = try await FilmyPhotoStore.shared.loadDocument(documentID)
            document = value
            recipe = value.currentRevision?.recipe
            finish = value.currentRevision?.finish ?? .photo
            selectedRevisionID = value.currentRevision?.id
            originalURL = try await FilmyPhotoStore.shared.originalURL(documentID)
            rawURL = value.hasRAW ? try await FilmyPhotoStore.shared.originalURL(documentID, raw: true) : nil
            liveURL = try await FilmyPhotoStore.shared.liveMovieURL(documentID)
            let source = try await FilmyPhotoStore.shared.originalData(documentID)
            originalPreview = await Task.detached(priority: .userInitiated) { Self.thumbnail(source) }.value
            await showRendition(revisionID: selectedRevisionID)
        } catch {
            loadingRendition = false
            message = error.localizedDescription
        }
    }

    private func showRendition(revisionID: UUID?) async {
        guard let revisionID else {
            loadingRendition = false
            return
        }
        preview = nil
        loadingRendition = true
        let image: UIImage?
        if let url = try? await FilmyPhotoStore.shared.renditionURL(documentID, revisionID: revisionID) {
            image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return Self.thumbnail(data)
            }.value
        } else { image = originalPreview }
        guard !Task.isCancelled, selectedRevisionID == revisionID else { return }
        preview = image
        loadingRendition = false
    }

    private var saveActionName: String { savesAsNewFrame ? "Save as new frame" : "Save version" }

    /// Edit look: keep the look as a new version, then add it to Photos as a
    /// new asset. The original and the linked Photos asset are never touched.
    private func saveAsNewFrame() async {
        // Retry after a failed export: the version from the last tap is still
        // current and unchanged, so export it instead of saving a duplicate.
        if let pending = newFrameAwaitingExport, let current = document?.currentRevision,
           current.id == pending, selectedRevisionID == pending,
           recipe?.id == current.recipe.id, finish == current.finish {
            let updatesLinkedCopy = await failedExportLinkedNewAsset()
            if await export(asNewCopy: !updatesLinkedCopy, newCopyIfAssetMissing: updatesLinkedCopy) {
                newFrameAwaitingExport = nil
            }
            return
        }
        let before = document?.currentRevision?.id
        await develop(save: true)
        guard let after = document?.currentRevision?.id, after != before else { return }
        newFrameAwaitingExport = after
        linkBeforeNewFrameExport = document?.photosAssetIdentifier
        if await export(asNewCopy: true) { newFrameAwaitingExport = nil }
    }

    /// True when the failed first export had already created and linked a new
    /// Photos asset: the retry then updates that asset instead of making a
    /// second one. Updating needs read-write access; under add-only a
    /// duplicate is possible, a lost version is not, so the retry makes a copy.
    private func failedExportLinkedNewAsset() async -> Bool {
        guard let latest = try? await FilmyPhotoStore.shared.loadDocument(documentID) else { return false }
        guard let linked = latest.photosAssetIdentifier, !linked.isEmpty,
              linked != linkBeforeNewFrameExport else { return false }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private func develop(save: Bool) async {
        guard !busy, let document, let current = document.currentRevision,
              let editing = document.revisionForEditing(selectedRevisionID), let recipe else { return }
        message = nil
        busy = true
        defer { busy = false }
        do {
            let data = try await FilmyPhotoStore.shared.originalData(documentID)
            let selectedFinish = finish
            let rendered = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    let source: Data
                    var output = editing.output
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
                        grainSeed: document.geometry.grainSeed, finish: selectedFinish, outputSettings: output,
                        dateStampEnabled: document.geometry.dateStampText != nil,
                        dateStampText: document.geometry.dateStampText
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
                    settings: editing.output, renderedData: rendered.data
                )
                self.document = updated
                selectedRevisionID = updated.currentRevision?.id
                message = "New version saved. Your original is unchanged."
            } else { message = savesAsNewFrame ? "Preview only. Tap Save as new frame to keep it." : "Preview only. Save version before exporting." }
        } catch { message = error.localizedDescription }
    }

    @discardableResult
    private func export(asNewCopy: Bool, newCopyIfAssetMissing: Bool = false) async -> Bool {
        guard !busy else { return false }
        message = nil
        busy = true
        defer { busy = false }
        do {
            let identifier = try await FilmyPhotosExporter.save(documentID, asNewCopy: asNewCopy)
            let latest = try await FilmyPhotoStore.shared.loadDocument(documentID)
            let thumbnailData = try await FilmyPhotoStore.shared.thumbnailData(documentID)
            let thumbnail = thumbnailData.flatMap { UIImage(data: $0) }
            if let revision = latest.currentRevision {
                await photoLibrary.registerDocumentExport(identifier, recipe: revision.recipe,
                                                          capturedAt: latest.capturedAt,
                                                          thumbnailData: thumbnailData, thumbnail: thumbnail)
            }
            await load()
            message = "Saved to Photos with original resources and reversible Filmy edits."
            return true
        } catch {
            if newCopyIfAssetMissing, !asNewCopy, case FilmyPhotosExporter.ExportError.missingAsset = error {
                // Filmy can no longer see the linked copy (deleted in Photos,
                // or outside a limited selection): make a fresh asset instead of
                // failing forever. A duplicate is possible, a lost version is not.
                busy = false
                return await export(asNewCopy: true)
            }
            message = error.localizedDescription
            return false
        }
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
