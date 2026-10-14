@preconcurrency import Photos
import CoreImage
import CoreLocation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File-backed receipt that makes a Photos creation idempotent. The placeholder
/// identifier is written inside the change block, before the commit completes,
/// so a throw or process death before the capture is linked cannot cause a
/// duplicate: the next attempt adopts the asset if it resolves, else clears it.
/// Add-only access cannot fetch, so an unresolved receipt there falls back to a
/// fresh creation (the previous behavior).
enum PhotosExportReceipt {
    /// Receipt location for the save in progress; read by PhotoLibraryService.save.
    @TaskLocal static var sidecar: URL?

    enum Decision: Equatable {
        case create
        case adopt(String)
        case clearAndCreate
    }

    /// Pure decision: adopt a pending identifier only if it resolves to an asset.
    static func decision(pending: String?, resolves: (String) -> Bool) -> Decision {
        guard let pending, !pending.isEmpty else { return .create }
        return resolves(pending) ? .adopt(pending) : .clearAndCreate
    }

    static func pending(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func record(_ identifier: String, at url: URL) {
        try? Data(identifier.utf8).write(to: url, options: .atomic)
    }

    static func clear(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func resolves(_ identifier: String) -> Bool {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: options).firstObject != nil
    }

    /// Identifier of an already-created asset for this receipt, or nil. A stale
    /// receipt that no longer resolves is cleared.
    static func adoptable(at url: URL?, resolver: (String) -> Bool = { PhotosExportReceipt.resolves($0) }) -> String? {
        guard let url else { return nil }
        switch decision(pending: pending(at: url), resolves: resolver) {
        case .adopt(let identifier): return identifier
        case .clearAndCreate: clear(at: url); return nil
        case .create: return nil
        }
    }
}

/// PhotoKit owns the rendered Live Photo pairing metadata. Never combine a
/// re-encoded still with an unedited movie and hope the pairing survives.
@MainActor
enum FilmyPhotosExporter {
    nonisolated static let adjustmentIdentifier = "com.filmycamera.photo-edit"
    private static var exporting: Set<UUID> = []

    enum ExportError: LocalizedError {
        case accessDenied, busy, missingAsset, unsupportedOutput, writeFailed, externalEdit, iCloudDownloadRequired
        var errorDescription: String? {
            switch self {
            case .accessDenied: "Photos access is needed for this export. Your Filmy original is safe."
            case .busy: "This photo is already being exported."
            case .missingAsset: "The linked Photos asset is unavailable. Restore Photos access or export a new copy."
            case .unsupportedOutput: "Photos cannot preserve this format in an edited asset on this device. The Filmy version is safe."
            case .writeFailed: "Photos could not finish this edit. Its original and your Filmy version are safe; retry to update the same asset."
            case .externalEdit: "Another app edited this Photos asset. Export a new copy to keep those edits."
            case .iCloudDownloadRequired: "The original is in iCloud and could not be downloaded. Connect to the internet, then retry. Your Filmy version is safe."
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
        let document = try await store.loadDocument(id)
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
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [existingID], options: hiddenInclusiveFetchOptions())
            if let asset = assets.firstObject {
                try await update(asset, document: document, rendition: rendition, adjustment: adjustment)
                // A receipt left by an interrupted "new copy" must not be adopted later in place of this link.
                let staleReceiptURL = await store.photosReceiptURL(for: id)
                PhotosExportReceipt.clear(at: staleReceiptURL)
                return existingID
            }
            // Only full access proves the asset was deleted; under limited
            // access an empty fetch can mean it was merely deselected.
            guard status == .authorized else { throw ExportError.missingAsset }
        }

        let receiptURL = await store.photosReceiptURL(for: id)
        if let adopted = PhotosExportReceipt.adoptable(at: receiptURL) {
            // A prior attempt created this asset but never linked it.
            try await store.linkPhotosAsset(adopted, to: id)
            PhotosExportReceipt.clear(at: receiptURL)
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [adopted], options: hiddenInclusiveFetchOptions())
            guard let asset = assets.firstObject else { throw ExportError.missingAsset }
            try await update(asset, document: document, rendition: rendition, adjustment: adjustment)
            return adopted
        }
        let identifier = Box<String?>(nil)
        let editError = Box<Bool>(false)
        let outputURL = Box<URL?>(nil)
        let requestedType: UTType = rendition.pathExtension == "heic" ? .heic : .jpeg
        let adjustmentBox = Box(adjustment)
        // For stills, original + RAW companion + rendered edit are committed
        // in one PhotoKit transaction and require only add-only permission.
        let taggingEnabled: Bool = UserDefaults.standard.object(forKey: "locationTaggingEnabled.v1") as? Bool ?? true
        // Current rendition first; older revisions only supply GPS a re-developed rendition lacks.
        var locationRenditions: [URL] = [rendition]
        if taggingEnabled {
            for older in document.revisions.dropLast().reversed() {
                if let url = try? await store.renditionURL(id, revisionID: older.id) { locationRenditions.append(url) }
            }
        }
        let candidates = locationRenditions
        let createChanges: @Sendable () -> Void = {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = document.capturedAt
            request.location = Self.exportLocation(original: original, renditions: candidates, taggingEnabled: taggingEnabled)
            request.addResource(with: .photo, fileURL: original, options: nil)
            if let raw { request.addResource(with: .alternatePhoto, fileURL: raw, options: nil) }
            if let movie { request.addResource(with: .pairedVideo, fileURL: movie, options: nil) }
            guard let placeholder = request.placeholderForCreatedAsset else { editError.set(true); return }
            identifier.set(placeholder.localIdentifier)
            PhotosExportReceipt.record(placeholder.localIdentifier, at: receiptURL)
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
        defer { if let url = outputURL.get() { try? FileManager.default.removeItem(at: url) } }
        try await PHPhotoLibrary.shared().performChanges(createChanges)
        guard let assetID = identifier.get() else { throw ExportError.writeFailed }
        // Link immediately after creation, including a failed edit. Retrying
        // then updates the existing original instead of duplicating it.
        try await store.linkPhotosAsset(assetID, to: id)
        PhotosExportReceipt.clear(at: receiptURL)
        guard !editError.get() else { throw ExportError.writeFailed }
        if movie != nil {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: hiddenInclusiveFetchOptions())
            guard let asset = assets.firstObject else { throw ExportError.missingAsset }
            try await update(asset, document: document, rendition: rendition, adjustment: adjustment)
        }
        return assetID
    }

    /// The sensor original carries no GPS; the rendition does when location tagging allowed it.
    /// The original's own location is kept regardless; the rendition's is used only while tagging is on.
    nonisolated static func exportLocation(original: URL, rendition: URL, taggingEnabled: Bool) -> CLLocation? {
        PhotoLibraryService.location(fromURL: original) ?? (taggingEnabled ? PhotoLibraryService.location(fromURL: rendition) : nil)
    }

    /// Same as above, trying each rendition in order (current revision first).
    nonisolated static func exportLocation(original: URL, renditions: [URL], taggingEnabled: Bool) -> CLLocation? {
        if let own = PhotoLibraryService.location(fromURL: original) { return own }
        guard taggingEnabled else { return nil }
        for url in renditions {
            if let found = PhotoLibraryService.location(fromURL: url) { return found }
        }
        return nil
    }

    /// Maps a failed content-editing-input request to the error the user sees.
    nonisolated static func inputFailure(info: [AnyHashable: Any]) -> ExportError {
        if let error = info[PHContentEditingInputErrorKey] as? NSError, error.domain == PHPhotosErrorDomain {
            let networkCodes = [PHPhotosError.Code.networkAccessRequired.rawValue, PHPhotosError.Code.networkError.rawValue]
            if networkCodes.contains(error.code) { return .iCloudDownloadRequired }
        }
        if (info[PHContentEditingInputResultIsInCloudKey] as? NSNumber)?.boolValue == true {
            return .iCloudDownloadRequired
        }
        return .writeFailed
    }

    private static func hiddenInclusiveFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        return options
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
            let completion: @Sendable (PHContentEditingInput?, [AnyHashable: Any]) -> Void = { input, info in
                if let input { continuation.resume(returning: input) }
                else { continuation.resume(throwing: inputFailure(info: info)) }
            }
            asset.requestContentEditingInput(with: options, completionHandler: completion)
        }
        if externalAdjustment.get() { throw ExportError.externalEdit }
        if let data = input.adjustmentData, data.formatIdentifier != adjustmentIdentifier {
            throw ExportError.externalEdit
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = adjustment
        var renderedURL = output.renderedContentURL
        defer { try? FileManager.default.removeItem(at: renderedURL) }
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
                    let regions: [CGRect] = []
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
                    let finished = G7DateStampRenderer.applyingStamp(
                        to: filtered, text: geometry.dateStampText,
                        enabled: geometry.dateStampText != nil, orientation: orientation
                    )
                    // Materialize in Filmy's working color space rather than
                    // relying on Photos' unspecified CIContext color policy.
                    let colorSpaceName = revision.output.colorGamut == .displayP3
                        ? CGColorSpace.displayP3 : CGColorSpace.sRGB
                    guard let colorSpace = CGColorSpace(name: colorSpaceName),
                          let rendered = ProPhotoOutput.context.createCGImage(
                            finished, from: finished.extent, format: .RGBA8, colorSpace: colorSpace
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
            renderedURL = url
        }
        let outputBox = Box(output)
        let assetBox = Box(asset)
        let updateChanges: @Sendable () -> Void = {
            PHAssetChangeRequest(for: assetBox.get()).contentEditingOutput = outputBox.get()
        }
        try await PHPhotoLibrary.shared().performChanges(updateChanges)
        // The deferred removal drops only the URL Photos explicitly gave us;
        // do not enumerate or purge the shared temporary directory.
    }
}
