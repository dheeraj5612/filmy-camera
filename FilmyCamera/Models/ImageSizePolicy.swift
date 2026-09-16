import Foundation

/// Shared numeric admission rules for untrusted dimensions and render targets.
/// Do not convert CGFloat to Int or allocate pixels before this validation.
enum ImageSizePolicy {
    static func boundedSize(
        _ size: CGSize,
        maximumPixels: CGFloat,
        maximumDimension: CGFloat,
        maximumScale: CGFloat = 1
    ) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              maximumPixels.isFinite, maximumPixels >= 1,
              maximumDimension.isFinite, maximumDimension >= 1,
              maximumScale.isFinite, maximumScale > 0 else { return nil }

        // Divide before multiplying: even finite inputs can overflow their area.
        let edgeScale = min(maximumDimension / size.width, maximumDimension / size.height)
        let pixelScale = (maximumPixels / size.width).squareRoot() / size.height.squareRoot()
        let scale = min(maximumScale, edgeScale, pixelScale)
        guard scale.isFinite, scale > 0 else { return nil }
        let width = max(1, (size.width * scale).rounded(.down))
        let height = max(1, (size.height * scale).rounded(.down))
        guard width <= maximumDimension, height <= maximumDimension,
              width <= maximumPixels / height else { return nil }
        return CGSize(width: width, height: height)
    }

    static func isFinitePositive(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

/// A failed read while protected data is locked is not evidence of deletion.
enum CacheMaintenancePolicy {
    static func confirmsMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError))
            || (error.domain == NSPOSIXErrorDomain && error.code == 2) // ENOENT
    }

    static func canRemove(currentFilename: String?, inspectedFilename: String?) -> Bool {
        guard let currentFilename, let inspectedFilename else { return false }
        return currentFilename == inspectedFilename
    }
}
