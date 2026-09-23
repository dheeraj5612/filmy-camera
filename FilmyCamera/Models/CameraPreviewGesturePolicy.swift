import CoreGraphics

enum CameraLookDirection: Equatable {
    case previous
    case next
}

enum CameraPreviewDragAxis {
    case look
    case exposure
}

enum CameraPreviewGesturePolicy {
    /// Lock the first deliberate axis for the entire drag, including curved drags.
    static func dragAxis(translation: CGSize) -> CameraPreviewDragAxis? {
        guard translation.width.isFinite, translation.height.isFinite else { return nil }
        let x = abs(translation.width), y = abs(translation.height)
        if x >= 12, x > y * 1.5 { return .look }
        if y >= 12, y > x * 1.5 { return .exposure }
        return nil
    }

    /// Do not claim a vertical drag until tap-to-focus has made exposure
    /// adjustment available. Returning nil keeps the axis undecided so a
    /// focus state update that lands during the first drag events can still
    /// start the exposure gesture.
    static func eligibleDragAxis(translation: CGSize, hasFocusPoint: Bool,
                                 canAdjustExposure: Bool) -> CameraPreviewDragAxis? {
        guard let axis = dragAxis(translation: translation) else { return nil }
        guard axis != .exposure || (hasFocusPoint && canAdjustExposure) else { return nil }
        return axis
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
}
