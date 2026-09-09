import CoreGraphics
import CoreImage

/// Adds an optional print border after recipe rendering without resampling the
/// finished photo. Core Image keeps this composition lazy until export.
enum PhotoPrintCompositor {
    static let maximumSourcePixelCount: CGFloat = 64_000_000
    static let maximumOutputPixelCount: CGFloat = 80_000_000

    static let sideAndTopFraction: CGFloat = 0.035
    static let bottomFraction: CGFloat = 0.12

    static let paperRed: CGFloat = 0.97
    static let paperGreen: CGFloat = 0.96
    static let paperBlue: CGFloat = 0.93

    struct Layout: Equatable {
        let sourcePixelExtent: CGRect
        let canvasExtent: CGRect
        let imageFrame: CGRect
        let sideMargin: CGFloat
        let topMargin: CGFloat
        let bottomMargin: CGFloat
    }

    /// Returns deterministic, pixel-aligned geometry for preview and export.
    /// Instant Print uses the short edge so the proportions remain consistent
    /// across portrait and landscape photos. The larger bottom sits at Core
    /// Image's y=0 edge.
    static func layout(for sourceExtent: CGRect, finish: PhotoFinish) -> Layout? {
        guard let sourcePixelExtent = pixelAlignedExtent(enclosing: sourceExtent) else {
            return nil
        }

        if finish == .photo {
            return Layout(
                sourcePixelExtent: sourcePixelExtent,
                canvasExtent: sourceExtent,
                imageFrame: sourceExtent,
                sideMargin: 0,
                topMargin: 0,
                bottomMargin: 0
            )
        }

        guard isWithinPixelBudget(sourcePixelExtent, maximum: maximumSourcePixelCount) else {
            return nil
        }

        let shortEdge = min(sourcePixelExtent.width, sourcePixelExtent.height)
        let sideAndTop = max(1, ceil(shortEdge * sideAndTopFraction))
        let bottom = max(sideAndTop + 1, ceil(shortEdge * bottomFraction))
        let outputWidth = sourcePixelExtent.width + (sideAndTop * 2)
        let outputHeight = sourcePixelExtent.height + sideAndTop + bottom
        let canvasExtent = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

        guard isWithinPixelBudget(canvasExtent, maximum: maximumOutputPixelCount) else {
            return nil
        }

        return Layout(
            sourcePixelExtent: sourcePixelExtent,
            canvasExtent: canvasExtent,
            imageFrame: CGRect(
                x: sideAndTop,
                y: bottom,
                width: sourcePixelExtent.width,
                height: sourcePixelExtent.height
            ),
            sideMargin: sideAndTop,
            topMargin: sideAndTop,
            bottomMargin: bottom
        )
    }

    /// Returns the original image for `.photo`. Instant Print normalizes the
    /// output to a zero origin, surrounds the source at one-to-one pixel scale,
    /// and produces an opaque result even when the source contains alpha.
    static func composedImage(_ image: CIImage, finish: PhotoFinish) -> CIImage? {
        guard finish == .instantPrint else { return image }
        guard let layout = layout(for: image.extent, finish: finish) else { return nil }

        let source = image
            .transformed(by: CGAffineTransform(
                translationX: -layout.sourcePixelExtent.minX,
                y: -layout.sourcePixelExtent.minY
            ))
            .cropped(to: CGRect(
                x: 0,
                y: 0,
                width: layout.sourcePixelExtent.width,
                height: layout.sourcePixelExtent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: layout.imageFrame.minX,
                y: layout.imageFrame.minY
            ))

        let paper = CIImage(color: CIColor(
            red: paperRed,
            green: paperGreen,
            blue: paperBlue,
            alpha: 1
        )).cropped(to: layout.canvasExtent)
        return source.composited(over: paper).cropped(to: layout.canvasExtent)
    }

    private static func pixelAlignedExtent(enclosing extent: CGRect) -> CGRect? {
        guard !extent.isNull,
              !extent.isInfinite,
              !extent.isEmpty,
              extent.minX.isFinite,
              extent.minY.isFinite,
              extent.maxX.isFinite,
              extent.maxY.isFinite else {
            return nil
        }

        let minX = floor(extent.minX)
        let minY = floor(extent.minY)
        let maxX = ceil(extent.maxX)
        let maxY = ceil(extent.maxY)
        let pixelExtent = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        guard pixelExtent.width > 0,
              pixelExtent.height > 0,
              pixelExtent.width.isFinite,
              pixelExtent.height.isFinite else {
            return nil
        }
        return pixelExtent
    }

    private static func isWithinPixelBudget(_ extent: CGRect, maximum: CGFloat) -> Bool {
        let pixelCount = extent.width * extent.height
        return pixelCount.isFinite && pixelCount > 0 && pixelCount <= maximum
    }
}
