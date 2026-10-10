import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// The G7 X date-stamp preference is shared by the Q menu and the still
/// renderer. The setting is intentionally namespaced so it cannot collide
/// with a future setting in the original Filmy Camera target.
enum G7DateStampPreferences {
    static let enabledKey = "g7x.dateStamp.enabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
#if G7_APP
        defaults.bool(forKey: enabledKey)
#else
        false
#endif
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
#if G7_APP
        defaults.set(enabled, forKey: enabledKey)
#else
        _ = enabled
        _ = defaults
#endif
    }
}

/// Draws the optional compact-camera date mark into the already cropped and
/// finished pixels. Applying it at this last stage puts it in the true output
/// bottom-right corner for both `.photo` and Instant Print compositions.
enum G7DateStampRenderer {
    static let dateFormat = "yy.MM.dd"
    static let orange = CGColor(red: 1.0, green: 0.28, blue: 0.035, alpha: 0.88)
    static let glow = CGColor(red: 1.0, green: 0.20, blue: 0.01, alpha: 0.28)

    /// Returns the date text used by the stamp. This is exposed separately so
    /// tests and the review path can verify the capture date without decoding
    /// rendered pixels.
    static func dateText(
        for date: Date,
        timeZone: TimeZone = .current,
        calendar: Calendar = .gregorian
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }

    /// Adds the mark once to `image`. Callers pass the original render source
    /// on every re-edit, so a re-export never composites a second mark over an
    /// already stamped JPEG. `text` is captured at shutter time, including its
    /// timezone, so later re-renders are stable while traveling.
    static func applyingStamp(
        to image: CIImage,
        text: String?,
        enabled: Bool
    ) -> CIImage {
#if G7_APP
        guard enabled, let text, !text.isEmpty else { return image }
        let sourceExtent = image.extent
        guard sourceExtent.width.isFinite,
              sourceExtent.height.isFinite,
              sourceExtent.width > 1,
              sourceExtent.height > 1 else {
            return image
        }

        let minimumDimension = min(sourceExtent.width, sourceExtent.height)
        // Keep the mark legible on small crops while preserving a proportional
        // safe inset on phone, print, and landscape output sizes.
        let inset = max(8, minimumDimension * 0.035)
        let fontSize = max(12, minimumDimension * 0.045)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): orange
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard textWidth > 0, textWidth + (inset * 2) < sourceExtent.width else {
            return image
        }

        // The stamp is tiny relative to a photo. Allocate only its glyph-sized
        // overlay instead of a second full-resolution transparent bitmap.
        let padding = max(2, fontSize * 0.18)
        let overlayWidth = Int(ceil(textWidth + padding * 2))
        let overlayHeight = Int(ceil(fontSize * 1.55 + padding * 2))
        guard overlayWidth > 0, overlayHeight > 0 else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: overlayWidth,
            height: overlayHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(overlayWidth), height: CGFloat(overlayHeight)))
        // Core Graphics uses a lower-left origin, so the baseline is inset
        // above the output's bottom edge.
        let baseline = padding + fontSize * 0.16
        context.saveGState()
        context.setShadow(offset: .zero, blur: max(1.5, fontSize * 0.12), color: glow)
        context.textPosition = CGPoint(x: padding, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
        guard let overlay = context.makeImage() else { return image }

        let overlayImage = CIImage(cgImage: overlay)
        let positionedOverlay = overlayImage.transformed(by: CGAffineTransform(
            translationX: sourceExtent.maxX - inset - overlayImage.extent.width - overlayImage.extent.minX,
            y: sourceExtent.minY + inset - overlayImage.extent.minY
        ))
        return positionedOverlay.composited(over: image)
#else
        _ = enabled
        _ = text
        return image
#endif
    }
}

private extension Calendar {
    static var gregorian: Calendar { Calendar(identifier: .gregorian) }
}
