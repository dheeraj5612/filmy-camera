import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Geometry shared by the live viewfinder and the saved still path.
///
/// The camera surface is aspect-fill, so the visible frame is a centered crop
/// of the sensor image. Keeping this calculation in one place prevents a
/// subject composed at the edge of the preview from moving in the saved photo.
enum CameraFrameLayout {
    static func aspectFillCrop(
        sourceExtent: CGRect,
        targetSize: CGSize
    ) -> CGRect {
        guard sourceExtent.width > 0,
              sourceExtent.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return sourceExtent
        }

        let sourceAspect = sourceExtent.width / sourceExtent.height
        let targetAspect = targetSize.width / targetSize.height

        if sourceAspect > targetAspect {
            let cropWidth = sourceExtent.height * targetAspect
            return CGRect(
                x: sourceExtent.midX - cropWidth / 2,
                y: sourceExtent.minY,
                width: cropWidth,
                height: sourceExtent.height
            )
        }

        let cropHeight = sourceExtent.width / targetAspect
        return CGRect(
            x: sourceExtent.minX,
            y: sourceExtent.midY - cropHeight / 2,
            width: sourceExtent.width,
            height: cropHeight
        )
    }

    /// Pixel size of a still after its EXIF orientation is applied. Reads the
    /// header only; nil when the data is not a readable image.
    static func orientedPixelSize(of data: Data) -> CGSize? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = orientation >= 5 && orientation <= 8
        return swapsAxes ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// `viewport` is in preview-frame axes. Returns it in the delivered still's
    /// axes. Any unknown, non-finite, square or off-axis input returns it as is.
    static func stillViewport(
        _ viewport: CGSize,
        stillPixelSize: CGSize?,
        previewRotationAngle: CGFloat?
    ) -> CGSize {
        guard let still = stillPixelSize, let angle = previewRotationAngle, angle.isFinite,
              viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
              still.width.isFinite, still.height.isFinite, still.width > 0, still.height > 0,
              still.width != still.height else { return viewport }
        let remainder = abs(angle.truncatingRemainder(dividingBy: 180))
        let previewIsPortrait = abs(remainder - 90) <= 1
        let previewIsLandscape = remainder <= 1 || remainder >= 179
        guard previewIsPortrait || previewIsLandscape else { return viewport }
        let stillIsPortrait = still.height > still.width
        if previewIsPortrait == stillIsPortrait { return viewport }
        return CGSize(width: viewport.height, height: viewport.width)
    }

    static func aspectFill(
        _ image: CIImage,
        in target: CGRect
    ) -> CIImage {
        let sourceExtent = image.extent
        guard sourceExtent.width > 0,
              sourceExtent.height > 0,
              target.width > 0,
              target.height > 0 else {
            return image
        }

        let crop = aspectFillCrop(
            sourceExtent: sourceExtent,
            targetSize: target.size
        )
        let cropped = image.cropped(to: crop)
        let scale = min(target.width / crop.width, target.height / crop.height)
        let normalized = cropped.transformed(
            by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
        )
        let scaled = normalized.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let scaledExtent = scaled.extent
        return scaled
            .transformed(
                by: CGAffineTransform(
                    translationX: target.midX - scaledExtent.midX,
                    y: target.midY - scaledExtent.midY
                )
            )
            .cropped(to: target)
    }
}
