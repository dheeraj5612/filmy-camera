import CoreGraphics
import Foundation

enum CameraLookDirection: Equatable {
    case previous
    case next
}

enum CameraPreviewDragAxis {
    case look
    case exposure
}

enum CameraExposureDetent: Equatable {
    case step
    case zero
}

/// Which single view owns the viewfinder's middle slot. Newest claim wins.
enum CameraMidSlot: Equatable {
    case none
    case original
    case exposure
    case lookName
}

enum CameraPreviewGesturePolicy {
    /// Spoken to VoiceOver on the live preview. Camera flip is not offered here:
    /// it lives on the flip button and the "Switch camera" accessibility action.
    static let previewAccessibilityHint = "Tap to focus. Slide up to brighten or down to darken. Press and hold to compare the original. Swipe left or right to change looks, or pinch to zoom. These controls are also available as accessibility actions."

    /// Travel before a vertical drag provisionally claims exposure.
    static let exposureClaimDistance: CGFloat = 24

    /// How long the exposure readout stays after the finger lifts.
    static let exposureReadoutLinger: Duration = .milliseconds(1500)

    /// One meaning per gesture. A lift before 12 pt is a tap and focuses at once.
    /// Horizontal (x >= 12 and x > 1.5y) claims a look swipe. Vertical (y >= 24 and
    /// y > 1.5x) claims exposure provisionally: nothing is sent and no readout
    /// shows until the target is a full 1/3 stop from the baseline, and a later
    /// horizontal-dominant sample still reclaims the drag as a look swipe. Once
    /// committed, the drag stays exposure for its whole length. Diagonals stay
    /// undecided until one rule fires.
    static func dragAxis(translation: CGSize) -> CameraPreviewDragAxis? {
        guard translation.width.isFinite, translation.height.isFinite else { return nil }
        let x = abs(translation.width), y = abs(translation.height)
        if x >= 12, x > y * 1.5 { return .look }
        if y >= exposureClaimDistance, y > x * 1.5 { return .exposure }
        return nil
    }

    /// Keeps the axis decided so far, except that a provisional exposure claim
    /// becomes a look swipe when the drag turns horizontal before it commits.
    static func resolvedDragAxis(current: CameraPreviewDragAxis?, translation: CGSize,
                                 exposureCommitted: Bool) -> CameraPreviewDragAxis? {
        if current == .look { return .look }
        if current == .exposure, exposureCommitted { return .exposure }
        let fresh = dragAxis(translation: translation)
        if current == .exposure { return fresh == .look ? .look : .exposure }
        return fresh
    }

    /// A provisional exposure drag commits once its target is a full 1/3 stop from the baseline.
    static func exposureDragReachesCommit(start: Float, target: Float) -> Bool {
        start.isFinite && target.isFinite && abs(target - start) >= 1.0 / 3 - 0.0001
    }

    /// Whole thirds of a stop, rounded like CameraService.quantizedExposureBias.
    static func exposureThird(_ bias: Float) -> Int? {
        guard bias.isFinite, abs(bias) <= 64 else { return nil }
        return Int((bias * 3).rounded())
    }

    static func exposureDetent(from old: Float, to new: Float) -> CameraExposureDetent? {
        guard let oldThird = exposureThird(old), let newThird = exposureThird(new),
              oldThird != newThird else { return nil }
        return newThird == 0 ? .zero : .step
    }

    /// Ticks only when the published value is within a third of what the drag sent,
    /// so a Scene Auto saved-bias restore does not tick but a clamp one third short does.
    static func exposureDragHaptic(from old: Float, to new: Float, sent: Float?) -> CameraExposureDetent? {
        guard let sent, let sentThird = exposureThird(sent), let newThird = exposureThird(new),
              abs(newThird - sentThird) <= 1 else { return nil }
        return exposureDetent(from: old, to: new)
    }

    static func exposureReadout(bias: Float, isManualExposure: Bool) -> String {
        if isManualExposure { return "Manual exposure on" }
        let rounded: Float = bias.isFinite ? (bias * 10).rounded() / 10 : 0
        return String(format: "%@%.1f EV", rounded >= 0 ? "+" : "\u{2212}", Double(abs(rounded)))
    }

    /// One stop per quarter-viewfinder, with a minimum travel for small previews.
    /// CameraService remains responsible for the active sensor's supported range.
    static func exposureBias(start: Float, translation: CGSize, viewportHeight: CGFloat) -> Float? {
        guard start.isFinite, translation.height.isFinite,
              viewportHeight.isFinite, viewportHeight > 0 else { return nil }
        let bias = start - Float(translation.height / max(100, viewportHeight / 4))
        return bias.isFinite ? bias : nil
    }

    static func targetRecipe(in recipes: [FilmRecipe], selectedIdentifier: String,
                             direction: CameraLookDirection) -> FilmRecipe? {
        let ordered = LookLibraryIndex.results(in: recipes, query: "", filter: .all, favorites: [])
        guard let identifier = targetIdentifier(in: ordered.map(\.id), selectedIdentifier: selectedIdentifier,
                                                direction: direction) else { return nil }
        return ordered.first { $0.id == identifier }
    }

    static func lookDirection(translation: CGSize, viewportWidth: CGFloat,
                              interactionEnabled: Bool, includesPinch: Bool) -> CameraLookDirection? {
        guard interactionEnabled, !includesPinch,
              translation.width.isFinite, translation.height.isFinite,
              viewportWidth.isFinite, viewportWidth > 0 else { return nil }
        let threshold = min(max(viewportWidth * 0.16, 44), 90)
        guard abs(translation.width) >= threshold,
              abs(translation.width) > abs(translation.height) * 1.5 else { return nil }
        return translation.width < 0 ? .next : .previous
    }

    /// Match the look library's order and stop at its first and last entries.
    static func targetIdentifier(in identifiers: [String], selectedIdentifier: String,
                                 direction: CameraLookDirection) -> String? {
        guard let index = identifiers.firstIndex(of: selectedIdentifier) else { return nil }
        let target = index + (direction == .next ? 1 : -1)
        guard identifiers.indices.contains(target) else { return nil }
        return identifiers[target]
    }

    /// How long the look-name flash stays over the viewfinder.
    static let lookFlashDuration: Duration = .milliseconds(900)

    /// Hold-to-compare beats the exposure readout, which beats the look flash.
    static func midSlot(isHoldingOriginal: Bool, isShowingExposure: Bool, hasLookFlash: Bool) -> CameraMidSlot {
        if isHoldingOriginal { return .original }
        if isShowingExposure { return .exposure }
        return hasLookFlash ? .lookName : .none
    }

    /// "12 of 40", counted from one; nil when the look is not in the list.
    static func lookPositionText(in recipes: [FilmRecipe], selectedIdentifier: String) -> String? {
        guard let index = recipes.firstIndex(where: { $0.id == selectedIdentifier }) else { return nil }
        return "\(index + 1) of \(recipes.count)"
    }

    /// Top of the Fuji viewfinder state chip: 106 pt under the measured top chrome
    /// (54 pt when nothing is measured, which gives 160 pt), clamped above the tool rail.
    static func fujiChipTop(topChromeHeight: CGFloat?, viewfinderHeight: CGFloat) -> CGFloat {
        min((topChromeHeight ?? 54) + 106, max(70, viewfinderHeight - 170))
    }

    /// A short-lived Undo toast never replaces an error toast.
    static func actionToastMayShow(isErrorToastShowing: Bool) -> Bool {
        !isErrorToastShowing
    }

    /// The exact override a Live Adjust Reset removed, so Undo restores it unchanged.
    struct LookResetUndo: Equatable, Sendable {
        let recipeID: String
        let snapshot: FilmRecipe

        static func make(recipeID: String, overrides: [String: FilmRecipe]) -> LookResetUndo? {
            guard let snapshot = overrides[recipeID] else { return nil }
            return LookResetUndo(recipeID: recipeID, snapshot: snapshot)
        }

        func restored(into overrides: [String: FilmRecipe]) -> [String: FilmRecipe] {
            var result = overrides
            result[recipeID] = snapshot
            return result
        }

        func isInvalidated(byEditOf id: String) -> Bool { id == recipeID }
    }
}
