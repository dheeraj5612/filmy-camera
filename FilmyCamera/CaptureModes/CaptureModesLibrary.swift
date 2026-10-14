import AVKit
import SwiftUI

struct CaptureModesLibrary: View {
    @ObservedObject var model: CaptureModesModel
    var readOnly = false
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID]
    /// Merge-only snapshot so a capture deleted from its detail keeps that detail on screen while it slides out.
    @State private var lastKnown: [UUID: CaptureMedia] = [:]

    @MainActor
    init(model: CaptureModesModel, readOnly: Bool = false, initialCaptureID: UUID? = nil) {
        _model = ObservedObject(wrappedValue: model)
        self.readOnly = readOnly
        _path = State(initialValue: initialCaptureID.map { [$0] } ?? [])
        // Seed the snapshot so a deep-linked detail deleted before the root's onChange fires still has its record.
        var seeded: [UUID: CaptureMedia] = [:]
        for capture in model.captures { seeded[capture.id] = capture }
        _lastKnown = State(initialValue: seeded)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if readOnly {
                    Text("Photos, videos and panoramas saved from Capture modes.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage {
                    Section("Action needed") { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                }
                if model.captures.isEmpty {
                    ContentUnavailableView("No captures yet", systemImage: "camera", description: Text("Completed originals are saved here before film processing starts."))
                }
                ForEach(model.captures) { capture in
                    NavigationLink(value: capture.id) {
                        CaptureLibraryRow(capture: capture, readOnly: readOnly)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { (id: UUID) in destination(id) }
            .onChange(of: model.captures.map(\.id), initial: true) { _, _ in
                for capture in model.captures { lastKnown[capture.id] = capture }
            }
            .navigationTitle("Filmy Captures")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .overlay { if model.exporting { ProgressView("Exporting to Photos").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .task { model.refresh() }
        }.preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func destination(_ id: UUID) -> some View {
        let capture = model.captures.first(where: { $0.id == id }) ?? lastKnown[id]
        if let capture {
            CaptureModesDetail(model: model, initial: capture, readOnly: readOnly)
        } else {
            ContentUnavailableView("Capture not found", systemImage: "photo", description: Text("It is no longer in Filmy Captures."))
        }
    }
}

private struct CaptureModesDetail: View {
    @ObservedObject var model: CaptureModesModel
    let initial: CaptureMedia
    var readOnly = false
    @Environment(\.dismiss) private var dismiss
    @State private var originals: [URL] = []
    @State private var outputs: [URL] = []
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var confirmingDelete = false
    @State private var deleted = false
    private var media: CaptureMedia { model.captures.first(where: { $0.id == initial.id }) ?? initial }
    private var deleteTitle: String {
        if media.isExported { return "Delete originals and developed files from Filmy? Exports already in Photos stay unchanged." }
        return "This capture is not fully exported to Photos, so Filmy holds the only copy. Delete originals and developed files from Filmy? This cannot be undone."
    }

    var body: some View {
        List {
            if let image { Image(uiImage: image).resizable().scaledToFit().listRowInsets(EdgeInsets()) }
            if let player { VideoPlayer(player: player).frame(minHeight: 240).listRowInsets(EdgeInsets()) }
            Section("Capture") {
                Text("\(media.mode.title) · \(media.recipeName)")
                Text(media.createdAt, format: .dateTime)
                if media.width > 0 { Text("\(media.width) × \(media.height) pixels · \(media.acceptedFrames) accepted frames") }
                ForEach(media.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("Developed files") {
                if model.exporting || model.state.phase == .processing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(model.exporting ? "Exporting to Photos" : model.state.message)
                    }.accessibilityElement(children: .combine)
                }
                if outputs.isEmpty { Text("No developed file yet. Your originals below are still available.").foregroundStyle(.secondary) }
                ForEach(Array(outputs.enumerated()), id: \.element) { index, url in
                    ShareLink(item: url) {
                        Label(CaptureModesPolicy.shareLabel(original: false, isVideo: media.mode.isVideo, index: index), systemImage: "square.and.arrow.up")
                    }
                }
                Button(media.isExported ? "Exported to Photos" : "Export developed files to Photos") { model.export(media) }
                    .disabled(media.outputs.isEmpty || media.isExported || model.exporting || model.state.phase.isBusy)
                if media.status == .originalsOnly {
                    if readOnly {
                        Text("To retry processing, open Capture modes, then Captures.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Retry processing from originals") { model.errorMessage = nil; model.engine.retry(media) }
                            .disabled(model.exporting || model.state.phase.isBusy)
                    }
                }
            }
            Section("Untouched originals") {
                ForEach(Array(originals.enumerated()), id: \.element) { index, url in
                    ShareLink(item: url) {
                        Label(CaptureModesPolicy.shareLabel(original: true, isVideo: media.mode.isVideo, index: index), systemImage: "doc")
                    }
                }
                Text("Sharing the original HEIC or spatial movie preserves its encoded depth or stereo metadata. Third-party apps may not retain it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Delete local capture", role: .destructive) { confirmingDelete = true }
                    .disabled(model.exporting || model.state.phase.isBusy)
            }
        }
        .navigationTitle(media.mode.title)
        .confirmationDialog(deleteTitle,
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete local capture", role: .destructive) {
                Task {
                    do {
                        let id = media.id
                        try await Task.detached(priority: .utility) { try CaptureMediaStore.delete(id) }.value
                        CaptureThumbnailCache.evict(media)
                        deleted = true
                        model.refresh()
                        dismiss()
                    } catch { model.errorMessage = error.localizedDescription }
                }
            }
        }
        .task(id: media.outputs) { await loadFiles() }
        .onDisappear { player?.pause() }
    }

    @MainActor private func loadFiles() async {
        guard !deleted else { return }
        let record = media
        do {
            let paths = try await Task.detached(priority: .utility) {
                let originals = try CaptureMediaStore.recoverableOriginals(record)
                let outputs = try record.outputs.map { try CaptureMediaStore.file($0, in: record.id) }
                return (originals, outputs)
            }.value
            guard !Task.isCancelled else { return }
            originals = paths.0
            outputs = paths.1
            guard let first = outputs.first ?? originals.first else { return }
            if record.mode.isVideo { player = AVPlayer(url: first) }
            else {
                let preview = try await Task.detached(priority: .utility) {
                    let cg = try CaptureImageProcessor.thumbnail(first, maximum: 1_280)
                    return CaptureReferencePreview(image: cg, jpeg: Data())
                }.value
                guard !Task.isCancelled else { return }
                image = UIImage(cgImage: preview.image)
            }
        } catch { if !Task.isCancelled, !deleted { model.errorMessage = error.localizedDescription } }
    }
}

/// Bounded in-memory thumbnails for the Captures list. 160 px maximum, 64 entries: a few MB at most.
@MainActor enum CaptureThumbnailCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        return cache
    }()

    static func key(_ id: UUID, _ name: String) -> String { "\(id.uuidString)/\(name)" }

    /// Drops the entries a deleted capture could have produced (developed file first, else original).
    static func evict(_ media: CaptureMedia) {
        for name in [media.outputs.first, media.originals.first].compactMap({ $0 }) {
            images.removeObject(forKey: key(media.id, name) as NSString)
        }
    }

    /// Reads an existing file only: never creates a capture folder, so a deleted capture stays deleted.
    nonisolated static func decode(id: UUID, name: String, isVideo: Bool) async throws -> CaptureReferencePreview {
        let url = try CaptureMediaStore.root()
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CaptureModesError.invalidImage }
        let cg: CGImage
        if isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 160)
            cg = try await generator.image(at: .zero).image
        } else {
            cg = try CaptureImageProcessor.thumbnail(url, maximum: 160)
        }
        // A delete may have removed the folder while decoding: do not hand back a result for it.
        guard FileManager.default.fileExists(atPath: url.path) else { throw CaptureModesError.invalidImage }
        return CaptureReferencePreview(image: cg, jpeg: Data())
    }
}

/// Square thumbnail of a capture: the developed file when there is one, else the first original, else the mode symbol.
struct CaptureThumbnail: View {
    let capture: CaptureMedia
    let side: CGFloat
    @State private var image: UIImage?

    private var fileName: String? {
        CaptureModesPolicy.thumbnailFile(outputs: capture.outputs, originals: capture.originals)
    }
    private var cacheKey: String { CaptureThumbnailCache.key(capture.id, fileName ?? "") }

    var body: some View {
        ZStack {
            Rectangle().fill(FilmyTheme.panel)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: capture.mode.symbol).font(.title3).foregroundStyle(FilmyTheme.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: FilmyTheme.controlRadius))
        .accessibilityHidden(true)
        .task(id: cacheKey) { await load() }
    }

    @MainActor private func load() async {
        let key = cacheKey
        if let cached = CaptureThumbnailCache.images.object(forKey: key as NSString) {
            image = cached
            return
        }
        image = nil
        guard let name = fileName, !Task.isCancelled else { return }
        let id = capture.id
        let isVideo = capture.mode.isVideo
        let preview: CaptureReferencePreview? = try? await Task.detached(priority: .utility) {
            try await CaptureThumbnailCache.decode(id: id, name: name, isVideo: isVideo)
        }.value
        guard let preview else { return }
        let decoded = UIImage(cgImage: preview.image)
        CaptureThumbnailCache.images.setObject(decoded, forKey: key as NSString)
        guard !Task.isCancelled else { return }
        image = decoded
    }
}

private struct CaptureLibraryRow: View {
    let capture: CaptureMedia
    let readOnly: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize { return AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) }
        return AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    var body: some View {
        layout {
            CaptureThumbnail(capture: capture, side: 64)
            textColumn
        }
    }

    private var textColumn: some View {
        let status = CaptureModesPolicy.photosStatus(capture)
        return VStack(alignment: .leading, spacing: 5) {
            Label(capture.mode.title, systemImage: capture.mode.symbol).font(.headline)
            Text(capture.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption)
            Text("\(capture.originals.count) originals · \(capture.outputs.count) developed · \(capture.recipeName)")
                .font(.caption).foregroundStyle(.secondary)
            Label(status.text, systemImage: status.symbol).font(.caption)
            if capture.status == .originalsOnly { originalsNote }
        }
    }

    private var originalsNote: some View {
        Text(readOnly ? "Originals retained." : "Originals retained. Processing can be retried.")
            .font(.caption).foregroundStyle(.orange)
    }
}

struct CaptureSceneResults: View {
    let analysis: CaptureSceneAnalysis
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var pendingURL: URL?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Processed on device. Labels are uncertain suggestions, not authoritative identification or Apple's Visual Intelligence.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Recognized text") {
                    Text(analysis.text.isEmpty ? "No readable text found." : analysis.text).textSelection(.enabled)
                    if !analysis.text.isEmpty { ShareLink(item: analysis.text) { Label("Share text", systemImage: "square.and.arrow.up") } }
                }
                Section("QR and barcodes") {
                    if analysis.codes.isEmpty { Text("No code found.").foregroundStyle(.secondary) }
                    ForEach(analysis.codes, id: \.self) { value in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(value).textSelection(.enabled)
                            ShareLink(item: value) { Label("Share code", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.borderless)
                            if let url = CaptureModesPolicy.safeWebURL(value) {
                                Button("Review web link") { pendingURL = url }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Possible scene labels") {
                    if analysis.labels.isEmpty { Text("No confident label found.").foregroundStyle(.secondary) }
                    ForEach(analysis.labels, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("Read scene")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Open this website?", isPresented: Binding(get: { pendingURL != nil }, set: { if !$0 { pendingURL = nil } })) {
                Button("Cancel", role: .cancel) { pendingURL = nil }
                Button("Open website") { if let url = pendingURL { openURL(url) }; pendingURL = nil }
            } message: {
                Text("A scanned code can lead to an unsafe site. Check the address before opening:\n\(pendingURL?.absoluteString ?? "")")
            }
        }.preferredColorScheme(.dark)
    }
}
