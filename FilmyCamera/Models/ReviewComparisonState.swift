import Foundation

/// Presentation only. A comparison never changes the recipe, source, finish,
/// or bytes selected for export. Pending intent owns the async original load:
/// a late result must not reopen a comparison after the user changes looks.
struct ReviewComparisonState: Equatable {
    enum Mode: String, Equatable, Sendable {
        case look, original, split
    }

    private(set) var mode: Mode = .look
    private(set) var pendingMode: Mode?
    private(set) var originalFraction: Double = 0.5

    /// Returns true only when the caller needs to prepare the source preview.
    @discardableResult
    mutating func select(_ requested: Mode, originalAvailable: Bool, splitSupported: Bool) -> Bool {
        guard requested != .split || splitSupported else { return false }
        pendingMode = nil
        if requested == .look || originalAvailable {
            mode = requested
            return false
        }
        pendingMode = requested
        return true
    }

    mutating func originalDidLoad(splitSupported: Bool) {
        guard let requested = pendingMode else { return }
        pendingMode = nil
        mode = requested == .split && !splitSupported ? .original : requested
    }

    mutating func preparationFailed() { pendingMode = nil }

    mutating func reset() {
        mode = .look
        pendingMode = nil
        originalFraction = 0.5
    }

    mutating func moveDivider(to fraction: Double) {
        guard fraction.isFinite else { return }
        originalFraction = min(max(fraction, 0), 1)
    }

    mutating func stepDivider(increasing: Bool) {
        moveDivider(to: originalFraction + (increasing ? 0.1 : -0.1))
    }
}

/// A split is honest only when both photographs have the same framing.
/// Instant Print adds pixels around the image, so it uses full-frame A/B,
/// never a misleading wipe between different compositions.
enum ReviewComparisonGeometry {
    static func supportsSplit(original: CGSize, edited: CGSize, finish: PhotoFinish) -> Bool {
        guard finish == .photo,
              original.width.isFinite, original.height.isFinite,
              edited.width.isFinite, edited.height.isFinite,
              original.width > 0, original.height > 0,
              edited.width > 0, edited.height > 0 else { return false }
        let originalAspect = original.width / original.height
        let editedAspect = edited.width / edited.height
        // The bounded preview rounds each output dimension to whole pixels.
        return abs(originalAspect / editedAspect - 1) <= 0.003
    }
}
