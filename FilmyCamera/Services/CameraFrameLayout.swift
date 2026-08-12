import CoreGraphics
import CoreImage

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
