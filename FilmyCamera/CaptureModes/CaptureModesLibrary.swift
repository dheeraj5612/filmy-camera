import AVKit
import SwiftUI

struct CaptureModesLibrary: View {
    @ObservedObject var model: CaptureModesModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section("Action needed") { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                }
                if model.captures.isEmpty {
                    ContentUnavailableView("No captures yet", systemImage: "camera", description: Text("Completed originals are saved here before film processing starts."))
                }
                ForEach(model.captures) { capture in
                    NavigationLink {
                        CaptureModesDetail(model: model, initial: capture)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(capture.mode.title, systemImage: capture.mode.symbol).font(.headline)
                            Text(capture.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                            Text("\(capture.originals.count) originals · \(capture.outputs.count) developed · \(capture.recipeName)")
                                .font(.caption).foregroundStyle(.secondary)
                            if capture.status == .originalsOnly { Text("Originals retained. Processing can be retried.").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
            }
            .navigationTitle("Filmy Captures")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .overlay { if model.exporting { ProgressView("Exporting to Photos").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .task { model.refresh() }
        }.preferredColorScheme(.dark)
    }
}

private struct CaptureModesDetail: View {
    @ObservedObject var model: CaptureModesModel
    let initial: CaptureMedia
    @Environment(\.dismiss) private var dismiss
    @State private var originals: [URL] = []
    @State private var outputs: [URL] = []
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var confirmingDelete = false
    private var media: CaptureMedia { model.captures.first(where: { $0.id == initial.id }) ?? initial }

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
                if outputs.isEmpty { Text("No developed file yet. Your originals below are still available.").foregroundStyle(.secondary) }
                ForEach(outputs, id: \.self) { url in
                    ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "square.and.arrow.up") }
                }
                Button(media.isExported ? "Exported to Photos" : "Export developed files to Photos") { model.export(media) }
                    .disabled(media.outputs.isEmpty || media.isExported || model.exporting || model.state.phase.isBusy)
                if media.status == .originalsOnly {
                    Button("Retry processing from originals") { model.engine.retry(media) }
                        .disabled(model.exporting || model.state.phase.isBusy)
                }
            }
            Section("Untouched originals") {
                ForEach(originals, id: \.self) { url in
                    ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "doc") }
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
        .confirmationDialog("Delete originals and developed files from Filmy? Exports already in Photos stay unchanged.",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete local capture", role: .destructive) {
                Task {
                    do {
                        let id = media.id
                        try await Task.detached(priority: .utility) { try CaptureMediaStore.delete(id) }.value
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
        } catch { if !Task.isCancelled { model.errorMessage = error.localizedDescription } }
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
                            if let url = CaptureModesPolicy.safeWebURL(value) {
                                Button("Review web link") { pendingURL = url }
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
