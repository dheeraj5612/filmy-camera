@preconcurrency import Photos
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PhotoKit owns the rendered Live Photo pairing metadata. Never combine a
/// re-encoded still with an unedited movie and hope the pairing survives.
@MainActor
enum FilmyPhotosExporter {
    nonisolated static let adjustmentIdentifier = "com.filmycamera.photo-edit"
    private static var exporting: Set<UUID> = []

    enum ExportError: LocalizedError {
        case accessDenied, busy, missingAsset, unsupportedOutput, writeFailed, externalEdit
        var errorDescription: String? {
            switch self {
            case .accessDenied: "Photos access is needed for this export. Your Filmy original is safe."
            case .busy: "This photo is already being exported."
            case .missingAsset: "The linked Photos asset is unavailable. Restore Photos access or export a new copy."
            case .unsupportedOutput: "Photos cannot preserve this format in an edited asset on this device. The Filmy version is safe."
            case .writeFailed: "Photos could not finish this edit. Its original and your Filmy version are safe; retry to update the same asset."
            case .externalEdit: "Another app edited this Photos asset. Export a new copy to keep those edits."
            }
        }
    }

    /// Used by PhotoKit's non-main callbacks. Framework objects are never
    /// mutated concurrently: every producer finishes before the reader runs.
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ value: Value) { lock.lock(); defer { lock.unlock() }; self.value = value }
    }

    static func save(_ id: UUID, asNewCopy: Bool = false, store: FilmyPhotoStore = .shared) async throws -> String {
        guard exporting.insert(id).inserted else { throw ExportError.busy }
        defer { exporting.remove(id) }
        let document = try await store.load(id)
        guard let revision = document.currentRevision else { throw ExportError.writeFailed }
        guard !(document.hasLivePhoto && (revision.output.dynamicRange == .hdr || revision.finish != .photo)) else {
            throw ExportError.unsupportedOutput
        }
        let rendition = try await store.renditionURL(id)
        let original = try await store.originalURL(id)
        let raw = document.hasRAW ? try await store.originalURL(id, raw: true) : nil
        let movie = try await store.liveMovieURL(id)
        let existingID = asNewCopy ? nil : document.photosAssetIdentifier
        let access: PHAccessLevel = document.hasLivePhoto || existingID != nil ? .readWrite : .addOnly
        var status = PHPhotoLibrary.authorizationStatus(for: access)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: access) }
        guard status == .authorized || status == .limited else { throw ExportError.accessDenied }
        // Include the complete edit, geometry and renderer version in Photos,
        // not just the name of a catalog entry that could change tomorrow.
        let adjustmentBytes = try JSONEncoder().encode(document)
        let adjustment = PHAdjustmentData(formatIdentifier: adjustmentIdentifier, formatVersion: "1", data: adjustmentBytes)

        if let existingID {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [existingID], options: nil)
            guard let asset = assets.firstObject else { throw ExportError.missingAsset }
            try await update(asset, document: document, rendition: rendition, adjustment: adjustment)
            return existingID
        }

        let identifier = Box<String?>(nil)
        let editError = Box<Bool>(false)
        let outputURL = Box<URL?>(nil)
        let requestedType: UTType = rendition.pathExtension == "heic" ? .heic : .jpeg
        let adjustmentBox = Box(adjustment)
        // For stills, original + RAW companion + rendered edit are committed
        // in one PhotoKit transaction and require only add-only permission.
        let createChanges: @Sendable () -> Void = {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = document.capturedAt
            request.addResource(with: .photo, fileURL: original, options: nil)
            if let raw { request.addResource(with: .alternatePhoto, fileURL: raw, options: nil) }
            if let movie { request.addResource(with: .pairedVideo, fileURL: movie, options: nil) }
            guard let placeholder = request.placeholderForCreatedAsset else { editError.set(true); return }
            identifier.set(placeholder.localIdentifier)
            guard movie == nil else { return }
            let output = PHContentEditingOutput(placeholderForCreatedAsset: placeholder)
            do {
                guard output.supportedRenderedContentTypes.contains(requestedType) else { throw ExportError.unsupportedOutput }
                let url = try output.renderedContentURL(for: requestedType)
                outputURL.set(url)
                try Data(contentsOf: rendition, options: .mappedIfSafe).write(to: url, options: .atomic)
                output.adjustmentData = adjustmentBox.get()
                request.contentEditingOutput = output
            } catch { editError.set(true) }
        }
        try await PHPhotoLibrary.shared().performChanges(createChanges)
        defer { if let url = outputURL.get() { try? FileManager.default.removeItem(at: url) } }
        guard let assetID = identifier.get() else { throw ExportError.writeFailed }
        // Link immediately after creation, including a failed edit. Retrying
        // then updates the existing original instead of duplicating it.
        try await store.linkPhotosAsset(assetID, to: id)
        guard !editError.get() else { throw ExportError.writeFailed }
        if movie != nil {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = assets.firstObject else { throw ExportError.missingAsset }
            try await update(asset, document: document, rendition: rendition, adjustment: adjustment)
        }
        return assetID
    }

    private static func update(
        _ asset: PHAsset, document: FilmyPhotoDocument, rendition: URL, adjustment: PHAdjustmentData
    ) async throws {
        let externalAdjustment = Box(false)
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        // Returning true for Filmy adjustments asks Photos for the original,
        // not the previous baked-in look. A version is never graded twice.
        let canHandle: @Sendable (PHAdjustmentData) -> Bool = { data in
            let recognized = data.formatIdentifier == adjustmentIdentifier && data.formatVersion == "1"
            if !recognized { externalAdjustment.set(true) }
            return recognized
        }
        options.canHandleAdjustmentData = canHandle
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            let completion: @Sendable (PHContentEditingInput?, [AnyHashable: Any]) -> Void = { input, _ in
                if let input { continuation.resume(returning: input) }
                else { continuation.resume(throwing: ExportError.writeFailed) }
            }
            asset.requestContentEditingInput(with: options, completionHandler: completion)
        }
        if externalAdjustment.get() { throw ExportError.externalEdit }
        if let data = input.adjustmentData, data.formatIdentifier != adjustmentIdentifier {
            throw ExportError.externalEdit
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = adjustment
        if document.hasLivePhoto {
            guard let context = PHLivePhotoEditingContext(livePhotoEditingInput: input),
                  let revision = document.currentRevision else { throw ExportError.writeFailed }
            let geometry = document.geometry
            let orientation = context.orientation
            context.audioVolume = revision.output.livePhotoAudio ? 1 : 0
            let processor: @Sendable (PHLivePhotoFrame, NSErrorPointer) -> CIImage? = { frame, error in
                autoreleasepool {
                    let viewport = CGSize(width: geometry.viewportWidth, height: geometry.viewportHeight)
                    let sideways = [CGImagePropertyOrientation.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
                    let target = sideways ? CGSize(width: viewport.height, height: viewport.width) : viewport
                    let source = ProPhotoOutput.framedSource(frame.image, viewportSize: target, resolution: .mp12)
                    let regions = revision.recipe.filmBase == .compactDigital ? FilmRenderer.portraitSubjectRegions(in: source) : []
                    let filtered = FilmRenderer.render(
                        source, recipe: revision.recipe, quality: .photo,
                        captureContext: .init(flashFired: geometry.flashFired, subjectRegions: regions),
                        grainSeed: geometry.grainSeed,
                        grainPhase: CameraViewModel.scaledGrainPhase(
                            geometry.grainSeed, grainSize: revision.recipe.grainSize,
                            previewSize: CGSize(width: geometry.previewWidth, height: geometry.previewHeight),
                            stillSize: source.extent.size
                        )
                    )
                    // Materialize in Filmy's working color space rather than
                    // relying on Photos' unspecified CIContext color policy.
                    guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3),
                          let rendered = ProPhotoOutput.context.createCGImage(
                            filtered, from: filtered.extent, format: .RGBA8, colorSpace: colorSpace
                          ) else {
                        error?.pointee = ExportError.writeFailed as NSError
                        return nil
                    }
                    return CIImage(cgImage: rendered)
                }
            }
            context.frameProcessor = processor
            try await context.saveLivePhoto(to: output, options: nil)
        } else {
            let type: UTType = rendition.pathExtension == "heic" ? .heic : .jpeg
            guard output.supportedRenderedContentTypes.contains(type) else { throw ExportError.unsupportedOutput }
            let url = try output.renderedContentURL(for: type)
            try Data(contentsOf: rendition, options: .mappedIfSafe).write(to: url, options: .atomic)
        }
        let outputBox = Box(output)
        let assetBox = Box(asset)
        let updateChanges: @Sendable () -> Void = {
            PHAssetChangeRequest(for: assetBox.get()).contentEditingOutput = outputBox.get()
        }
        try await PHPhotoLibrary.shared().performChanges(updateChanges)
        // Photos has consumed its copy. Only remove the URL it explicitly
        // gave us; do not enumerate or purge the shared temporary directory.
        try? FileManager.default.removeItem(at: output.renderedContentURL)
    }
}
