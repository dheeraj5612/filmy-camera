import CoreGraphics

/// Stores the card's position as a fraction of its available travel, so a
/// rotation or aspect change keeps the same corner without moving it offscreen.
struct HistogramPlacement {
    static let horizontalPreferenceKey = "histogramPositionX"
    static let verticalPreferenceKey = "histogramPositionY"
    static let preferredCardSize = CGSize(width: 118, height: 82)

    let cardSize: CGSize
    let centerBounds: CGRect

    init(viewport: CGSize, topClearance: CGFloat = 8, bottomClearance: CGFloat = 8) {
        let width = Self.dimension(viewport.width)
        let height = Self.dimension(viewport.height)
        let horizontalMargin = min(8, width / 2)
        let verticalMargin = min(8, height / 2)
        let topInset = max(verticalMargin, Self.dimension(topClearance))
        let bottomInset = max(verticalMargin, Self.dimension(bottomClearance))
        let chromeGap = height - topInset - bottomInset
        cardSize = CGSize(
            width: min(Self.preferredCardSize.width, max(0, width - 2 * horizontalMargin)),
            // A short landscape finder may leave less than 82pt between the
            // actual chrome rows. Compact the chart into that gap before
            // resorting to centering when there is no usable gap at all.
            height: min(Self.preferredCardSize.height, max(0, height - 2 * verticalMargin),
                        chromeGap > 0 ? chromeGap : Self.preferredCardSize.height)
        )
        let left = horizontalMargin + cardSize.width / 2
        let right = max(left, width - horizontalMargin - cardSize.width / 2)
        let hardTop = verticalMargin + cardSize.height / 2
        let hardBottom = max(hardTop, height - verticalMargin - cardSize.height / 2)
        let desiredTop = topInset + cardSize.height / 2
        let desiredBottom = height - bottomInset - cardSize.height / 2
        // If the chrome leaves no travel, keep the card centered within the
        // actual frame instead of letting an inset push it beyond an edge.
        let top = desiredTop <= desiredBottom ? max(hardTop, desiredTop) : (hardTop + hardBottom) / 2
        let bottom = desiredTop <= desiredBottom ? min(hardBottom, desiredBottom) : top
        centerBounds = CGRect(x: left, y: top, width: right - left, height: max(0, bottom - top))
    }

    func center(normalizedPosition: CGPoint, translation: CGSize = .zero) -> CGPoint {
        let position = Self.sanitized(normalizedPosition)
        return CGPoint(
            x: Self.clamp(centerBounds.minX + centerBounds.width * position.x + Self.finite(translation.width),
                          lower: centerBounds.minX, upper: centerBounds.maxX),
            y: Self.clamp(centerBounds.minY + centerBounds.height * position.y + Self.finite(translation.height),
                          lower: centerBounds.minY, upper: centerBounds.maxY)
        )
    }

    func normalizedPosition(for center: CGPoint, fallback: CGPoint = .zero) -> CGPoint {
        let fallback = Self.sanitized(fallback)
        return Self.sanitized(CGPoint(
            x: centerBounds.width > 0 ? (center.x - centerBounds.minX) / centerBounds.width : fallback.x,
            y: centerBounds.height > 0 ? (center.y - centerBounds.minY) / centerBounds.height : fallback.y
        ))
    }

    static func sanitized(_ position: CGPoint) -> CGPoint {
        CGPoint(x: clamp(finite(position.x), lower: 0, upper: 1),
                y: clamp(finite(position.y), lower: 0, upper: 1))
    }

    private static func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
    private static func dimension(_ value: CGFloat) -> CGFloat { max(0, finite(value)) }
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
