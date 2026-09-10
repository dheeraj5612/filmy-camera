import CoreGraphics
import Foundation

enum GalleryPagingDirection {
    case previous
    case next
}

/// Paging uses the Roll's current order, including locally cached frames.
/// Only the selected frame is decoded; the Roll can contain thousands of
/// frames without keeping thousands of full-size images in the detail view.
enum GalleryPagingPolicy {
    static func neighbor(of index: Int, offset: Int, count: Int) -> Int? {
        guard count > 0, (0..<count).contains(index), offset == -1 || offset == 1 else { return nil }
        if offset == -1 { return index > 0 ? index - 1 : nil }
        return index < count - 1 ? index + 1 : nil
    }

    static func retainedIndices(around index: Int, count: Int) -> Range<Int> {
        guard count > 0, (0..<count).contains(index) else { return 0..<0 }
        let end = index < count - 1 ? index + 2 : count
        return max(0, index - 1)..<end
    }

    static func targetIdentifier(
        in identifiers: [String],
        selectedIdentifier: String,
        direction: GalleryPagingDirection
    ) -> String? {
        guard let current = identifiers.firstIndex(of: selectedIdentifier) else { return nil }
        let target = current + (direction == .next ? 1 : -1)
        guard identifiers.indices.contains(target) else { return nil }
        return identifiers[target]
    }

    static func swipeDirection(
        translation: CGSize,
        viewportWidth: CGFloat,
        zoomScale: CGFloat
    ) -> GalleryPagingDirection? {
        guard translation.width.isFinite, translation.height.isFinite,
              viewportWidth.isFinite, viewportWidth > 0,
              zoomScale.isFinite, zoomScale == 1 else { return nil }
        let threshold = min(max(viewportWidth * 0.16, 44), 90)
        guard abs(translation.width) >= threshold,
              abs(translation.width) > abs(translation.height) * 1.25 else { return nil }
        return translation.width < 0 ? .next : .previous
    }
}
