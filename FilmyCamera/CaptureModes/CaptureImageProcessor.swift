@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision
import simd

/// Bounded, on-device processing. The film transform is the app's existing renderer,
/// not a second approximation. Fusion happens before grain and finishing effects.
enum CaptureImageProcessor {
    private static var linearContext: CIContext {
        CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, .cacheIntermediates: false])
    }

    static func thumbnail(_ url: URL, maximum: Int = 2_048, orient: Bool = true) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: orient,
                kCGImageSourceThumbnailMaxPixelSize: maximum,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CaptureModesError.invalidImage }
        return image
    }

    static func process(_ original: CaptureMedia, recipe: FilmRecipe) async throws -> CaptureMedia {
        var media = original
        guard media.status != .ready else { return media }
        try Task.checkCancellation()
        guard media.originals.count >= media.mode.minimumFrames else {
            throw CaptureModesError.insufficientFrames(media.originals.count)
        }
        guard media.originals.count <= media.mode.frameLimit else { throw CaptureModesError.invalidImage }
        let urls = try media.originals.map { try CaptureMediaStore.file($0, in: media.id) }
        if media.mode == .spatialVideo {
            // Do not flatten, re-encode, or strip the stereo calibration metadata.
            media.outputs = media.originals
            media.notes.append("Native spatial video; no film filter has been applied.")
        } else if media.mode == .filmVideo {
            let name = "filmy-video.mov"
            let destination = try CaptureMediaStore.file(name, in: media.id)
            try await gradeMovie(urls[0], to: destination, recipe: recipe)
            media.outputs = [name]
        } else if media.mode == .night || media.mode == .panorama {
            let result = try media.mode == .night ? fuseNight(urls) : stitchPanorama(urls)
            try Task.checkCancellation()
            let name = "filmy-\(media.mode.rawValue).heic"
            let rendered = FilmRenderer.render(result.image, recipe: recipe, quality: .photo)
            try encode(rendered, to: CaptureMediaStore.file(name, in: media.id))
            media.outputs = [name]
            media.width = Int(result.image.extent.width)
            media.height = Int(result.image.extent.height)
            media.acceptedFrames = result.accepted
            media.notes.append(media.mode == .night
                ? "Registered temporal denoising, up to 2560 pixels on the long edge. Moving regions favor the first frame."
                : "Experimental perspective-registered panorama. Parallax, moving subjects, and large sweeps can fail.")
        } else {
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                let name = String(format: "filmy-%03d.heic", index)
                if media.outputs.contains(name) { continue }
                try autoreleasepool {
                    guard var image = CIImage(contentsOf: url, options: [.applyOrientationProperty: false]) else {
                        throw CaptureModesError.invalidImage
                    }
                    if media.mode == .portrait { image = try portrait(image, source: url) }
                    let rendered = FilmRenderer.render(image, recipe: recipe, quality: .photo)
                    try encode(rendered, to: CaptureMediaStore.file(name, in: media.id), metadataSource: url,
                               retainDepth: media.mode == .portrait)
                    media.width = Int(image.extent.width)
                    media.height = Int(image.extent.height)
                }
                media.outputs.append(name)
                media.acceptedFrames += 1
                // Burst output is recoverable even if a later frame fails to render.
                try CaptureMediaStore.persist(media)
            }
        }
        media.status = .ready
        try CaptureMediaStore.persist(media)
        return media
    }

    static func encode(_ image: CIImage, to url: URL, metadataSource: URL? = nil, retainDepth: Bool = false) throws {
        guard let cg = FilmRenderer.sharedContext.createCGImage(image, from: image.extent.integral),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw CaptureModesError.invalidImage }
        let source = metadataSource.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.96,
                                          kCGImagePropertyOrientation: 1]
        if let source, let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if retainDepth {
                guard let width = original[kCGImagePropertyPixelWidth] as? Int,
                      let height = original[kCGImagePropertyPixelHeight] as? Int,
                      cg.width == width, cg.height == height else {
                    throw CaptureModesError.unavailable("Depth cannot be retained after resizing. The original HEIC is unchanged.")
                }
            }
            properties.merge(original) { _, original in original }
        }
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        if retainDepth, let source {
            // This path has not rotated/cropped/resized pixels, so the original
            // auxiliary map and orientation continue to describe the same image.
            for type in [kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
                         kCGImageAuxiliaryDataTypePortraitEffectsMatte] {
                if let auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) {
                    CGImageDestinationAddAuxiliaryDataInfo(destination, type, auxiliary)
                }
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw CaptureModesError.invalidImage }
    }

    private static func portrait(_ image: CIImage, source url: URL) throws -> CIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw CaptureModesError.invalidImage }
        let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)
            ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth)
        guard let dictionary = info as? [AnyHashable: Any] else {
            throw CaptureModesError.unavailable("This photo has no embedded depth. The original is retained; try a supported lens and a well-lit subject.")
        }
        let depth = try AVDepthData(fromDictionaryRepresentation: dictionary).converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let disparity = CIImage(cvPixelBuffer: depth.depthDataMap)
        let aligned = disparity.transformed(by: CGAffineTransform(scaleX: image.extent.width / disparity.extent.width,
                                                                 y: image.extent.height / disparity.extent.height))
        guard let filter = CIFilter(name: "CIDepthBlurEffect", parameters: [
            kCIInputImageKey: image, "inputDisparityImage": aligned, "inputAperture": 4.0,
            "inputFocusRect": CIVector(x: 0.45, y: 0.45, z: 0.1, w: 0.1)
        ]), let output = filter.outputImage else { throw CaptureModesError.invalidImage }
        return output.cropped(to: image.extent)
    }

    struct FusionResult { let image: CIImage; let accepted: Int }

    static func fuseNight(_ urls: [URL]) throws -> FusionResult {
        guard urls.count >= 3 else { throw CaptureModesError.insufficientFrames(urls.count) }
        let context = linearContext
        let reference = try thumbnail(urls[0], maximum: 2_560)
        let referenceImage = CIImage(cgImage: reference)
        var accumulator = referenceImage
        var crop = referenceImage.extent
        var accepted = 1
        for url in urls.dropFirst() {
            try Task.checkCancellation()
            try autoreleasepool {
                let cg = try thumbnail(url, maximum: 2_560)
                guard cg.width == reference.width, cg.height == reference.height else { return }
                let request = VNTranslationalImageRegistrationRequest(targetedCGImage: cg)
                try VNImageRequestHandler(cgImage: reference).perform([request])
                guard let transform = request.results?.first?.alignmentTransform,
                      CaptureModesPolicy.acceptableNightTranslation(x: transform.tx, y: transform.ty,
                          width: Double(cg.width), height: Double(cg.height)) else { return }
                let aligned = CIImage(cgImage: cg).transformed(by: transform)
                let intersection = crop.intersection(aligned.extent)
                let valid = CGRect(x: ceil(intersection.minX), y: ceil(intersection.minY),
                                   width: floor(intersection.maxX) - ceil(intersection.minX),
                                   height: floor(intersection.maxY) - ceil(intersection.minY))
                guard valid.width > 0, valid.height > 0 else { return }
                let average = accumulator.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: aligned, kCIInputTimeKey: 1.0 / Double(accepted + 1)])
                // Reject luminance differences above ~5%; keep the reference in
                // moving regions instead of producing a long-exposure ghost.
                let difference = aligned.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: referenceImage])
                let mask = difference.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: -4.252, y: -14.304, z: -1.444, w: 0),
                    "inputGVector": CIVector(x: -4.252, y: -14.304, z: -1.444, w: 0),
                    "inputBVector": CIVector(x: -4.252, y: -14.304, z: -1.444, w: 0),
                    "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
                ]).applyingFilter("CIColorClamp")
                let merged = average.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: accumulator, kCIInputMaskImageKey: mask]).cropped(to: valid)
                guard let materialized = context.createCGImage(merged, from: valid) else { throw CaptureModesError.invalidImage }
                accumulator = CIImage(cgImage: materialized).transformed(by: CGAffineTransform(translationX: valid.minX, y: valid.minY))
                crop = valid
                accepted += 1
            }
        }
        guard accepted >= 3 else { throw CaptureModesError.insufficientFrames(accepted) }
        let normalized = accumulator.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        return FusionResult(image: normalized, accepted: accepted)
    }

    static func stitchPanorama(_ urls: [URL]) throws -> FusionResult {
        guard urls.count >= 3 else { throw CaptureModesError.insufficientFrames(urls.count) }
        let context = linearContext
        var previous = try thumbnail(urls[0], maximum: Int(CaptureModesPolicy.registrationLongEdge))
        var canvas = CIImage(cgImage: previous)
        var previousToCanvas = matrix_identity_float3x3
        var accepted = 1
        var lastOrigin: CGFloat = 0
        var bottom: CGFloat = 0
        var top = canvas.extent.height
        for url in urls.dropFirst() {
            try Task.checkCancellation()
            try autoreleasepool {
                let next = try thumbnail(url, maximum: Int(CaptureModesPolicy.registrationLongEdge))
                guard next.width == previous.width, next.height == previous.height else { return }
                let request = VNHomographicImageRegistrationRequest(targetedCGImage: next)
                try VNImageRequestHandler(cgImage: previous).perform([request])
                guard let observation = request.results?.first else { return }
                let transform = previousToCanvas * observation.warpTransform
                let width = CGFloat(next.width), height = CGFloat(next.height)
                func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint? {
                    let point = transform * SIMD3<Float>(Float(x), Float(y), 1)
                    guard point.x.isFinite, point.y.isFinite, point.z.isFinite, point.z > 0.001 else { return nil }
                    return CGPoint(x: CGFloat(point.x / point.z), y: CGFloat(point.y / point.z))
                }
                guard let bl = project(0, 0), let br = project(width, 0),
                      let tl = project(0, height), let tr = project(width, height) else { return }
                // Only short, left-to-right sweeps with substantial overlap are accepted.
                let advance = min(bl.x, tl.x) - lastOrigin
                guard advance > width * 0.03, advance < width * 0.75,
                      abs(tl.y - bl.y - height) < height * 0.2,
                      abs(tr.y - br.y - height) < height * 0.2,
                      abs(br.x - bl.x - width) < width * 0.25 else { return }
                let warped = CIImage(cgImage: next).applyingFilter("CIPerspectiveTransform", parameters: [
                    "inputBottomLeft": CIVector(cgPoint: bl), "inputBottomRight": CIVector(cgPoint: br),
                    "inputTopLeft": CIVector(cgPoint: tl), "inputTopRight": CIVector(cgPoint: tr)])
                let bounds = canvas.extent.union(warped.extent).integral
                guard CaptureModesPolicy.acceptablePanoramaBounds(width: bounds.width, height: bounds.height) else { return }
                let newBottom = max(bottom, max(bl.y, br.y))
                let newTop = min(top, min(tl.y, tr.y))
                guard newTop - newBottom > height * 0.65 else { return }
                let left = min(bl.x, tl.x)
                guard let feather = CIFilter(name: "CILinearGradient", parameters: [
                    "inputPoint0": CIVector(x: left, y: 0), "inputPoint1": CIVector(x: left + width * 0.2, y: 0),
                    "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0), "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1)])?.outputImage else { throw CaptureModesError.invalidImage }
                let faded = warped.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: bounds), kCIInputMaskImageKey: feather])
                let merged = faded.composited(over: canvas).cropped(to: bounds)
                guard let image = context.createCGImage(merged, from: bounds) else { throw CaptureModesError.invalidImage }
                canvas = CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
                bottom = newBottom; top = newTop; lastOrigin = left
                previous = next; previousToCanvas = transform; accepted += 1
            }
        }
        guard accepted >= 3 else { throw CaptureModesError.insufficientFrames(accepted) }
        let crop = CGRect(x: 0, y: ceil(bottom), width: floor(canvas.extent.maxX), height: floor(top) - ceil(bottom))
        return FusionResult(image: canvas.cropped(to: crop).transformed(by: CGAffineTransform(translationX: 0, y: -crop.minY)), accepted: accepted)
    }

    private final class ExportBox: @unchecked Sendable {
        let session: AVAssetExportSession
        private let lock = NSLock()
        private var cancelled = false
        init(_ session: AVAssetExportSession) { self.session = session }
        func start(_ continuation: CheckedContinuation<Void, Error>) {
            lock.lock()
            guard !cancelled else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            session.exportAsynchronously { [self] in
                if session.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: session.error ?? CaptureModesError.cancelled) }
            }
            lock.unlock()
        }
        func cancel() {
            lock.lock()
            cancelled = true
            session.cancelExport()
            lock.unlock()
        }
    }

    private static func gradeMovie(_ source: URL, to destination: URL, recipe: FilmRecipe) async throws {
        try CaptureMediaStore.preflight()
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw CaptureModesError.unavailable("HEVC export is unavailable. The original movie is retained.")
        }
        exporter.videoComposition = AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let image = FilmRenderer.render(request.sourceImage, recipe: recipe, quality: .export)
            request.finish(with: image.cropped(to: request.sourceImage.extent), context: FilmRenderer.sharedContext)
        })
        exporter.outputURL = destination
        exporter.outputFileType = .mov
        let box = ExportBox(exporter)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                box.start(continuation)
            }
        } onCancel: { box.cancel() }
        try Task.checkCancellation()
    }
}
