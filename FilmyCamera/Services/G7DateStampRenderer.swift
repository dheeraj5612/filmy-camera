import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Namespaced preference used by the optional G7 X camera experience.
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

/// Applies a compact-camera date mark to finished output pixels.
enum G7DateStampRenderer {
    static let dateFormat = "yy.MM.dd"
    static let orange = CGColor(red: 1.0, green: 0.28, blue: 0.035, alpha: 0.88)
    static let glow = CGColor(red: 1.0, green: 0.20, blue: 0.01, alpha: 0.28)

    static func dateText(
        for date: Date,
        timeZone: TimeZone = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
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

    /// Composites a small overlay after framing and grading, so the mark stays
    /// in the true output corner and is never duplicated during re-rendering.
    static func applyingStamp(to image: CIImage, text: String?, enabled: Bool) -> CIImage {
        guard enabled, let text, !text.isEmpty else { return image }
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 1, extent.height > 1 else { return image }

        let minimumDimension = min(extent.width, extent.height)
        let inset = max(8, minimumDimension * 0.035)
        let fontSize = max(12, minimumDimension * 0.045)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): orange
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        guard textWidth > 0, textWidth + inset * 2 < extent.width else { return image }

        let padding = max(2, fontSize * 0.18)
        let overlayWidth = Int(ceil(textWidth + padding * 2))
        let overlayHeight = Int(ceil(fontSize * 1.55 + padding * 2))
        guard overlayWidth > 0, overlayHeight > 0,
              let context = CGContext(
                data: nil, width: overlayWidth, height: overlayHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }

        context.clear(CGRect(x: 0, y: 0, width: CGFloat(overlayWidth), height: CGFloat(overlayHeight)))
        context.saveGState()
        context.setShadow(offset: .zero, blur: max(1.5, fontSize * 0.12), color: glow)
        context.textPosition = CGPoint(x: padding, y: padding + fontSize * 0.16)
        CTLineDraw(line, context)
        context.restoreGState()
        guard let overlay = context.makeImage() else { return image }

        let overlayImage = CIImage(cgImage: overlay)
        let positioned = overlayImage.transformed(by: CGAffineTransform(
            translationX: extent.maxX - inset - overlayImage.extent.width - overlayImage.extent.minX,
            y: extent.minY + inset - overlayImage.extent.minY
        ))
        return positioned.composited(over: image)
    }
}
