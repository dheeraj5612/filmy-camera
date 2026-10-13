import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CaptureReferenceFile: Transferable, Sendable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { file in
            let url = file.file
            let task = Task.detached(priority: .userInitiated) {
                do { return try PhotoImportPolicy.read(from: url, byteLimit: 20_000_000) }
                catch PhotoImportFailure.tooLarge {
                    throw CaptureModesError.unavailable("Choose a reference image smaller than 20 MB.")
                }
            }
            return try await withTaskCancellationHandler {
                CaptureReferenceFile(data: try await task.value)
            } onCancel: { task.cancel() }
        }
    }
}

struct CaptureReferencePreview: @unchecked Sendable {
    let image: CGImage
    let jpeg: Data
}

enum CaptureReference {
    static func url() throws -> URL { try CaptureMediaStore.root().appendingPathComponent("reference.jpg") }

    static func prepare(_ data: Data) throws -> CaptureReferencePreview {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CaptureModesError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CaptureModesError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9,
                                                        kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureModesError.invalidImage }
        try Task.checkCancellation()
        return CaptureReferencePreview(image: image, jpeg: output as Data)
    }

    static func load() throws -> CaptureReferencePreview? {
        let source = try url()
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        return try prepare(Data(contentsOf: source))
    }
}
