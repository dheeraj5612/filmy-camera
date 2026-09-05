import Combine
import CoreImage
import CoreMedia
import ImageIO
import SwiftUI
import UIKit

extension FilmRecipe {
    /// UI-only metadata keeps the rail expressive without changing the core
    /// recipe model owned by the renderer.
    var descriptor: String { subtitle }

    var base: String {
        filmBase.displayName
    }

    var detail: String {
        switch id {
        case "provia-standard": return "Natural color, open whites, and a clean daylight finish for scenes that should feel close to the way you remember them."
        case "classic-chrome": return "Muted color, hard light, and restrained saturation for a frame that feels considered without feeling polished."
        case "velvia-vivid": return "Dense color and rich contrast for foliage, travel, and the scenes that deserve a little more pulse."
        case "astia-soft": return "Gentle portrait color with an easy highlight rolloff and a soft, natural finish."
        case "pro-neg-high": return "Neutral color and defined edges for everyday light, people, and moments that should stay believable."
        case "pro-neg-standard": return "A calm, versatile negative look with soft contrast and honest skin tones for everyday light."
        case "eterna-cinema": return "Low saturation, soft shadows, and a forgiving cinema-inspired curve for moving light."
        case "eterna-bleach-bypass": return "Desaturated color, lifted blacks, and crisp highlights for a graphic, silver-rich cinema mood."
        case "acros-monochrome": return "Fine grain and tonal depth for graphic scenes where light, shape, and texture do the talking."
        case "sepia-archive": return "Warm monochrome, paper-like highlights, and a quiet archival finish for images that should feel found."
        case "classic-negative": return "Warm highlights, restrained greens, and a textured negative feel for street scenes and quiet rooms."
        case "nostalgic-negative": return "Amber light, softened blues, and gentle contrast for a memory-like everyday palette."
        case "reala-ace": return "Natural color, open shadows, and a clean negative finish that lets the scene stay itself."
        case "g7x-compact": return "The default social compact-camera profile: bright warm portraits, peach/pink skin, crisp reds and blues, a protected highlight shoulder, and gentle subject-aware smoothing. Real flash captures deepen the ambient background while device optics and depth of field remain unchanged."
        default: return subtitle
        }
    }

    var symbol: String {
        switch filmBase {
        case .classicChrome, .proNegative, .proNegStandard, .classicNegative, .nostalgicNegative, .realaAce:
            return "building.2.crop.circle"
        case .velvia: return "sparkles"
        case .astia: return "person.crop.square.filled.and.at.rectangle"
        case .eterna, .eternaBleachBypass: return "film.stack"
        case .acros, .acrosYellow, .acrosRed, .acrosGreen, .monochrome: return "circle.lefthalf.filled"
        case .sepia: return "clock.arrow.circlepath"
        case .compactDigital: return "camera.fill"
        case .standard, .provia: return "camera.aperture"
        }
    }

    var previewColors: [Color] {
        switch id {
        case "provia-standard":
            return [Color(red: 0.15, green: 0.24, blue: 0.28), Color(red: 0.58, green: 0.50, blue: 0.39), Color(red: 0.91, green: 0.78, blue: 0.59)]
        case "classic-chrome":
            return [Color(red: 0.20, green: 0.27, blue: 0.30), Color(red: 0.76, green: 0.49, blue: 0.33), Color(red: 0.90, green: 0.76, blue: 0.55)]
        case "velvia-vivid":
            return [Color(red: 0.04, green: 0.25, blue: 0.28), Color(red: 0.05, green: 0.53, blue: 0.27), Color(red: 0.87, green: 0.20, blue: 0.16)]
        case "astia-soft":
            return [Color(red: 0.23, green: 0.29, blue: 0.32), Color(red: 0.78, green: 0.60, blue: 0.52), Color(red: 0.94, green: 0.79, blue: 0.72)]
        case "pro-neg-high":
            return [Color(red: 0.17, green: 0.22, blue: 0.25), Color(red: 0.52, green: 0.47, blue: 0.39), Color(red: 0.85, green: 0.76, blue: 0.60)]
        case "pro-neg-standard":
            return [Color(red: 0.18, green: 0.23, blue: 0.25), Color(red: 0.61, green: 0.51, blue: 0.43), Color(red: 0.88, green: 0.77, blue: 0.63)]
        case "eterna-cinema":
            return [Color(red: 0.12, green: 0.22, blue: 0.27), Color(red: 0.39, green: 0.53, blue: 0.52), Color(red: 0.74, green: 0.71, blue: 0.58)]
        case "eterna-bleach-bypass":
            return [Color(red: 0.10, green: 0.14, blue: 0.16), Color(red: 0.38, green: 0.43, blue: 0.41), Color(red: 0.82, green: 0.78, blue: 0.67)]
        case "acros-monochrome":
            return [Color(white: 0.08), Color(white: 0.38), Color(white: 0.84)]
        case "sepia-archive":
            return [Color(red: 0.16, green: 0.10, blue: 0.06), Color(red: 0.56, green: 0.38, blue: 0.24), Color(red: 0.88, green: 0.72, blue: 0.52)]
        case "classic-negative":
            return [Color(red: 0.13, green: 0.21, blue: 0.22), Color(red: 0.69, green: 0.44, blue: 0.30), Color(red: 0.92, green: 0.73, blue: 0.51)]
        case "nostalgic-negative":
            return [Color(red: 0.18, green: 0.23, blue: 0.26), Color(red: 0.72, green: 0.48, blue: 0.34), Color(red: 0.89, green: 0.71, blue: 0.50)]
        case "reala-ace":
            return [Color(red: 0.16, green: 0.25, blue: 0.27), Color(red: 0.58, green: 0.51, blue: 0.42), Color(red: 0.86, green: 0.79, blue: 0.66)]
        case "g7x-compact":
            return [Color(red: 0.08, green: 0.10, blue: 0.12), Color(red: 0.63, green: 0.34, blue: 0.24), Color(red: 0.20, green: 0.48, blue: 0.66)]
        default:
            return Self.previewColors
        }
    }

    var controlSummary: [(String, String)] {
        if filmBase == .compactDigital {
            return [
                ("Tone", "Social pop"),
                ("Color", "Peach vivid"),
                ("Detail", "Soft skin"),
                ("Grain", grainEffectLevel.displayName)
            ]
        }

        return [
            ("Tone", contrast >= 1.08 ? "Hard" : contrast <= 0.96 ? "Soft" : "Balanced"),
            ("Color", saturation >= 1.08 ? "Rich" : saturation <= 0.9 ? "Muted" : "Natural"),
            ("Grain", grainEffectLevel.displayName),
            ("Chrome", colorChromeLevel.displayName)
        ]
    }
}

@MainActor
final class CameraViewModel: ObservableObject {
    nonisolated static let defaultRecipeID = "g7x-compact"

    private static let builtInRecipesByID = Dictionary(
        uniqueKeysWithValues: FilmRecipe.builtIns.map { ($0.id, $0) }
    )

    private static var defaultRecipe: FilmRecipe {
        builtInRecipesByID[defaultRecipeID] ?? FilmRecipe.builtIns[0]
    }

    /// Resolve the same persisted controls as the view model so startup warms
    /// the actual first look, including a customized color cube.
    nonisolated static func launchRecipe(defaults: UserDefaults = .standard) -> FilmRecipe {
        let storedID = defaults.string(forKey: selectedRecipeIDKey) ?? defaultRecipeID
        let base = FilmRecipe.builtIns.first { $0.id == storedID }
            ?? FilmRecipe.builtIns.first { $0.id == defaultRecipeID }
            ?? FilmRecipe.builtIns[0]
        guard let saved = decodeRecipeOverrides(from: defaults.data(forKey: recipeOverridesKey))
            .recipes.values.first(where: { $0.id == base.id }) else {
            return base
        }
        var resolved = base
        resolved.applyControlValues(from: saved)
        resolved.markUserModified(parentRecipeID: base.id)
        return resolved
    }

    enum ReviewSource: Equatable {
        case camera
        case photoLibrary
    }

    enum ToastStyle: Equatable {
        case success
        case error
        case info

        var accessibilityTitle: String {
            switch self {
            case .success: "Success"
            case .error: "Error"
            case .info: "Info"
            }
        }
    }

    struct RenderedPhoto: @unchecked Sendable {
        let image: UIImage
        let data: Data
        let capturedAt: Date
        var isFullResolution = true
        var flashFired = false
        var normalizedSubjectRegions: [CGRect]? = nil
    }

    struct ReviewPreview: @unchecked Sendable {
        let image: UIImage
        let isFullResolution: Bool
        let flashFired: Bool
        var normalizedSubjectRegions: [CGRect]? = nil
    }

    struct ReviewRenderSource: @unchecked Sendable {
        enum Mode: Sendable {
            case camera(
                viewportSize: CGSize,
                previewDrawableSize: CGSize,
                flashFired: Bool,
                grainSeed: UInt32
            )
            case photoLibrary
        }

        let data: Data
        let capturedAt: Date
        let mode: Mode
        let normalizedSubjectRegions: [CGRect]?

        func storing(normalizedSubjectRegions: [CGRect]?) -> Self {
            Self(
                data: data,
                capturedAt: capturedAt,
                mode: mode,
                normalizedSubjectRegions: normalizedSubjectRegions
            )
        }
    }

    typealias ReviewPreviewRenderer = @Sendable (ReviewRenderSource, FilmRecipe) -> ReviewPreview?
    typealias ReviewFullRenderer = @Sendable (ReviewRenderSource, FilmRecipe) -> RenderedPhoto?
    typealias ReviewOriginalRenderer = @Sendable (ReviewRenderSource) -> UIImage?

    private final class ReviewWorkQueue: @unchecked Sendable {
        private struct Work: Sendable {
            let run: @Sendable () -> Void
            let cancel: @Sendable () -> Void
        }

        private let lock = NSLock()
        private let queue = DispatchQueue(
            label: "com.filmycamera.review-render",
            qos: .userInitiated
        )
        private var pending: Work?
        private var isWorking = false

        func submit(
            _ work: @escaping @Sendable () -> Void,
            onCancel: @escaping @Sendable () -> Void = {}
        ) {
            lock.lock()
            let replaced = pending
            pending = Work(run: work, cancel: onCancel)
            guard !isWorking else {
                lock.unlock()
                replaced?.cancel()
                return
            }
            isWorking = true
            lock.unlock()
            replaced?.cancel()
            queue.async { [weak self] in self?.drain() }
        }

        func cancelPending() {
            lock.lock()
            let cancelled = pending
            pending = nil
            lock.unlock()
            cancelled?.cancel()
        }

        func flush() async {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume() }
            }
        }

        private func drain() {
            while true {
                lock.lock()
                guard let work = pending else {
                    isWorking = false
                    lock.unlock()
                    return
                }
                pending = nil
                lock.unlock()
                autoreleasepool { work.run() }
            }
        }
    }

    nonisolated static let selectedRecipeIDKey = "selectedRecipeID"
    nonisolated static let recipeOverridesKey = "recipeOverrides"

    /// New installs and unknown persisted selections land on the G7 X profile.
    private static let fallbackRecipeID = CameraViewModel.defaultRecipeID
    private static let validRecipeIDs = Set(FilmRecipe.builtIns.map(\.id))

    private let defaults: UserDefaults

    @Published var selectedRecipeID: String {
        didSet {
            guard selectedRecipeID != oldValue else { return }
            guard Self.validRecipeIDs.contains(selectedRecipeID) else {
                selectedRecipeID = Self.fallbackRecipeID
                defaults.set(Self.fallbackRecipeID, forKey: Self.selectedRecipeIDKey)
                return
            }
            defaults.set(selectedRecipeID, forKey: Self.selectedRecipeIDKey)
            HapticFeedback.play(.selection)
        }
    }
    @Published private(set) var isCapturing = false
    @Published private(set) var isImporting = false
    @Published private(set) var isSaving = false
    @Published private(set) var saveErrorMessage: String?
    @Published private(set) var saveErrorRequiresSettings = false
    @Published private(set) var toastMessage: String?
    @Published private(set) var toastStyle: ToastStyle = .success
    @Published private(set) var lastCaptureDate: Date?
    @Published private(set) var reviewImage: UIImage?
    @Published private(set) var reviewRecipe: FilmRecipe?
    @Published private(set) var reviewSource: ReviewSource = .camera
    /// False when a library import was bounded to `importPixelBudget`.
    @Published private(set) var reviewIsFullResolution = true
    @Published private(set) var reviewFlashFired = false
    @Published private(set) var isRenderingReview = false
    @Published private(set) var reviewRenderErrorMessage: String?
    @Published private(set) var reviewOriginalImage: UIImage?
    @Published private(set) var isPreparingReviewOriginal = false
    @Published private(set) var pendingReviewRecipeID: String?
    @Published private var recipeOverrides: [String: FilmRecipe] = [:]

    private var toastTask: Task<Void, Never>?
    private var reviewImageData: Data?
    private var reviewCapturedAt: Date?
    private var reviewRenderSource: ReviewRenderSource?
    private var fullResolutionReviewRecipe: FilmRecipe?
    private var fullResolutionReviewImage: UIImage?
    private var fullResolutionReviewIsFullResolution = true
    private var fullResolutionReviewFlashFired = false
    private var reviewWorkGeneration: UInt64 = 0
    private let reviewWorkQueue = ReviewWorkQueue()
    private let reviewPreviewRenderer: ReviewPreviewRenderer
    private let reviewFullRenderer: ReviewFullRenderer
    private let reviewOriginalRenderer: ReviewOriginalRenderer
    private var pendingPhotoSaver: (any PhotoSaving)?

    init(
        defaults: UserDefaults = .standard,
        reviewPreviewRenderer: ReviewPreviewRenderer? = nil,
        reviewFullRenderer: ReviewFullRenderer? = nil,
        reviewOriginalRenderer: ReviewOriginalRenderer? = nil
    ) {
        self.defaults = defaults
        self.reviewPreviewRenderer = reviewPreviewRenderer ?? { source, recipe in
            Self.renderReviewPreview(source: source, recipe: recipe)
        }
        self.reviewFullRenderer = reviewFullRenderer ?? { source, recipe in
            Self.renderReviewFull(source: source, recipe: recipe)
        }
        self.reviewOriginalRenderer = reviewOriginalRenderer ?? { source in
            Self.renderReviewOriginal(source: source)
        }

        let storedRecipeID = defaults.string(forKey: Self.selectedRecipeIDKey)
        selectedRecipeID = storedRecipeID.flatMap {
            Self.validRecipeIDs.contains($0) ? $0 : nil
        } ?? Self.fallbackRecipeID
        if storedRecipeID != selectedRecipeID {
            defaults.set(selectedRecipeID, forKey: Self.selectedRecipeIDKey)
        }

        let decoded = Self.decodeRecipeOverrides(
            from: defaults.data(forKey: Self.recipeOverridesKey)
        )
        var migratedRecipes: [String: FilmRecipe] = [:]
        for savedRecipe in decoded.recipes.values {
            guard let parent = Self.builtInRecipesByID[savedRecipe.id] else {
                continue
            }
            var migratedRecipe = parent
            migratedRecipe.applyControlValues(from: savedRecipe)
            migratedRecipe.markUserModified(parentRecipeID: parent.id)
            migratedRecipes[parent.id] = migratedRecipe
        }
        recipeOverrides = migratedRecipes

        if decoded.shouldRewrite || migratedRecipes != decoded.recipes {
            persistRecipeOverrides()
        }
    }

    nonisolated static func decodeRecipeOverrides(
        from data: Data?
    ) -> (recipes: [String: FilmRecipe], shouldRewrite: Bool) {
        guard let data else { return ([:], false) }

        let decoder = JSONDecoder()
        if let recipes = try? decoder.decode(
            [String: FilmRecipe].self,
            from: data
        ) {
            return (recipes, false)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let rawRecipes = object as? [String: Any] else {
            return ([:], true)
        }

        var recoveredRecipes: [String: FilmRecipe] = [:]
        for (key, rawRecipe) in rawRecipes {
            guard JSONSerialization.isValidJSONObject(rawRecipe),
                  let recipeData = try? JSONSerialization.data(
                      withJSONObject: rawRecipe
                  ),
                  let recipe = try? decoder.decode(
                      FilmRecipe.self,
                      from: recipeData
                  ) else {
                continue
            }
            recoveredRecipes[key] = recipe
        }
        return (recoveredRecipes, true)
    }

    var selectedRecipe: FilmRecipe {
        recipe(for: selectedRecipeID)
    }

    /// The recipe rail, detail sheet, live preview, and exports must all use
    /// the same effective values. Returning resolved overrides here prevents
    /// a customized look from being represented by a stale stock thumbnail.
    var recipes: [FilmRecipe] {
        FilmRecipe.builtIns.map { recipe(for: $0.id) }
    }

    func recipe(for id: String) -> FilmRecipe {
        recipeOverrides[id]
            ?? Self.builtInRecipesByID[id]
            ?? Self.defaultRecipe
    }

    func select(recipe: FilmRecipe) {
        guard Self.validRecipeIDs.contains(recipe.id) else { return }
        selectedRecipeID = recipe.id
    }

    func originalRecipe(for id: String) -> FilmRecipe {
        Self.builtInRecipesByID[id] ?? Self.defaultRecipe
    }

    func update(recipe: FilmRecipe) {
        guard let parent = FilmRecipe.builtIns.first(where: {
            $0.id == recipe.id
        }) else {
            return
        }

        var customizedRecipe = parent
        customizedRecipe.applyControlValues(from: recipe)
        customizedRecipe.markUserModified(parentRecipeID: parent.id)
        recipeOverrides[parent.id] = customizedRecipe
        persistRecipeOverrides()
    }

    func reset(recipeID: String) {
        guard recipeOverrides.removeValue(forKey: recipeID) != nil else { return }
        persistRecipeOverrides()
    }

    func isCustomized(_ recipe: FilmRecipe) -> Bool {
        recipeOverrides[recipe.id] != nil
    }

    private func persistRecipeOverrides() {
        guard let data = try? JSONEncoder().encode(recipeOverrides) else { return }
        defaults.set(data, forKey: Self.recipeOverridesKey)
    }

    func capture(camera: CameraService) {
        guard !isCapturing, !isImporting else { return }
        isCapturing = true
        saveErrorMessage = nil
        saveErrorRequiresSettings = false
        let recipe = selectedRecipe
        let viewportSize = camera.previewViewportSize
        // Use the drawable the viewfinder really rendered into: its scale
        // comes from the window's screen (which can differ from the main
        // screen on an external display) and it is bounded by the pixel
        // budget. Only before the first layout is it derived here.
        let publishedDrawableSize = camera.previewDrawableSize
        let previewDrawableSize: CGSize
        if publishedDrawableSize.width > 0, publishedDrawableSize.height > 0 {
            previewDrawableSize = publishedDrawableSize
        } else {
            let previewScale = FilteredCameraPreviewView.drawableScale(
                for: viewportSize,
                screenScale: UIScreen.main.scale
            )
            previewDrawableSize = CGSize(
                width: viewportSize.width * previewScale,
                height: viewportSize.height * previewScale
            )
        }
        let grainSeed = camera.previewGrainSeed

        camera.capturePhoto { [weak self] capturedPhoto in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard let capturedPhoto else {
                    self.isCapturing = false
                    if camera.availability == .simulator {
                        self.showToast("Capture is available on a physical device", style: .info)
                    } else {
                        self.showToast("Capture could not be completed. Resume the camera and try again.", style: .error)
                    }
                    return
                }

                // The review sheet is a deliberate pause in the camera flow.
                // Keep the session warm so Retake returns to a live viewfinder
                // instantly, but stop feeding preview frames while the still
                // renders; CameraScreen decides when the session itself stops.
                camera.setFrameDeliveryPaused(true)

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let renderedPhoto = autoreleasepool {
                        Self.render(
                            sourceData: capturedPhoto.fileData,
                            recipe: recipe,
                            viewportSize: viewportSize,
                            previewDrawableSize: previewDrawableSize,
                            capturedAt: capturedPhoto.capturedAt,
                            flashFired: capturedPhoto.flashFired,
                            grainSeed: grainSeed
                        )
                    }

                    DispatchQueue.main.async {
                        guard let self else {
                            camera.setFrameDeliveryPaused(false)
                            return
                        }
                        guard let renderedPhoto else {
                            // CameraScreen owns session lifecycle. Ending the
                            // capture without a review lets its visibility-aware
                            // policy decide whether the camera should resume.
                            camera.setFrameDeliveryPaused(false)
                            self.isCapturing = false
                            self.showToast("The selected look could not be rendered. Try the capture again.", style: .error)
                            return
                        }
                        self.reviewImage = renderedPhoto.image
                        self.reviewImageData = renderedPhoto.data
                        self.reviewCapturedAt = renderedPhoto.capturedAt
                        self.reviewRecipe = recipe
                        self.reviewSource = .camera
                        self.reviewIsFullResolution = true
                        self.reviewFlashFired = renderedPhoto.flashFired
                        self.reviewRenderSource = ReviewRenderSource(
                            data: capturedPhoto.fileData,
                            capturedAt: capturedPhoto.capturedAt,
                            mode: .camera(
                                viewportSize: viewportSize,
                                previewDrawableSize: previewDrawableSize,
                                flashFired: capturedPhoto.flashFired,
                                grainSeed: grainSeed
                            ),
                            normalizedSubjectRegions: renderedPhoto.normalizedSubjectRegions
                        )
                        self.fullResolutionReviewRecipe = recipe
                        self.fullResolutionReviewImage = renderedPhoto.image
                        self.fullResolutionReviewIsFullResolution = renderedPhoto.isFullResolution
                        self.fullResolutionReviewFlashFired = renderedPhoto.flashFired
                        self.reviewRenderErrorMessage = nil
                        self.isCapturing = false
                    }
                }
            }
        }
    }

    func importPhoto(data: Data, camera: CameraService? = nil) async {
        guard !isCapturing, !isImporting, !isSaving, reviewImage == nil else { return }

        isImporting = true
        saveErrorMessage = nil
        saveErrorRequiresSettings = false
        camera?.setFrameDeliveryPaused(true)
        let recipe = selectedRecipe
        let importedAt = Date()

        let renderTask = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                Self.renderImported(
                    sourceData: data,
                    recipe: recipe,
                    importedAt: importedAt
                )
            }
        }
        let renderedPhoto = await withTaskCancellationHandler {
            await renderTask.value
        } onCancel: {
            renderTask.cancel()
        }

        isImporting = false
        guard !Task.isCancelled else {
            camera?.setFrameDeliveryPaused(false)
            return
        }
        guard let renderedPhoto else {
            camera?.setFrameDeliveryPaused(false)
            showToast("That photo could not be opened. Try a different image.", style: .error)
            return
        }

        reviewImage = renderedPhoto.image
        reviewImageData = renderedPhoto.data
        reviewCapturedAt = renderedPhoto.capturedAt
        reviewRecipe = recipe
        reviewSource = .photoLibrary
        reviewIsFullResolution = renderedPhoto.isFullResolution
        reviewFlashFired = false
        reviewRenderSource = ReviewRenderSource(
            data: data,
            capturedAt: importedAt,
            mode: .photoLibrary,
            normalizedSubjectRegions: renderedPhoto.normalizedSubjectRegions
        )
        fullResolutionReviewRecipe = recipe
        fullResolutionReviewImage = renderedPhoto.image
        fullResolutionReviewIsFullResolution = renderedPhoto.isFullResolution
        fullResolutionReviewFlashFired = renderedPhoto.flashFired
        reviewRenderErrorMessage = nil
        HapticFeedback.play(.success)
    }

    func reportImportFailure() {
        isImporting = false
        showToast("That photo could not be opened. Try a different image.", style: .error)
    }

    func applyReviewRecipe(_ recipe: FilmRecipe) {
        guard reviewImage != nil,
              let source = reviewRenderSource,
              !isSaving,
              !isPreparingReviewOriginal,
              Self.validRecipeIDs.contains(recipe.id) else {
            return
        }

        if recipe == fullResolutionReviewRecipe,
           let cachedImage = fullResolutionReviewImage {
            reviewWorkGeneration &+= 1
            reviewWorkQueue.cancelPending()
            reviewImage = cachedImage
            reviewRecipe = recipe
            reviewIsFullResolution = fullResolutionReviewIsFullResolution
            reviewFlashFired = fullResolutionReviewFlashFired
            isRenderingReview = false
            pendingReviewRecipeID = nil
            reviewRenderErrorMessage = nil
            saveErrorMessage = nil
            saveErrorRequiresSettings = false
            return
        }

        if recipe == reviewRecipe {
            if isRenderingReview {
                reviewWorkGeneration &+= 1
                reviewWorkQueue.cancelPending()
                isRenderingReview = false
                pendingReviewRecipeID = nil
            }
            reviewRenderErrorMessage = nil
            return
        }

        reviewWorkGeneration &+= 1
        let generation = reviewWorkGeneration
        let renderer = reviewPreviewRenderer
        isRenderingReview = true
        pendingReviewRecipeID = recipe.id
        reviewRenderErrorMessage = nil
        saveErrorMessage = nil
        saveErrorRequiresSettings = false

        reviewWorkQueue.submit { [weak self] in
            let rendered = renderer(source, recipe)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.reviewWorkGeneration == generation,
                      self.reviewRenderSource != nil else {
                    return
                }
                self.isRenderingReview = false
                self.pendingReviewRecipeID = nil
                guard let rendered else {
                    self.reviewRenderErrorMessage = "That look could not be rendered. Your previous review is still ready to save."
                    return
                }
                self.reviewImage = rendered.image
                self.reviewRecipe = recipe
                self.reviewIsFullResolution = rendered.isFullResolution
                self.reviewFlashFired = rendered.flashFired
                if rendered.normalizedSubjectRegions != nil {
                    self.reviewRenderSource = source.storing(
                        normalizedSubjectRegions: rendered.normalizedSubjectRegions
                    )
                }
            }
        }
    }

    func prepareReviewOriginal() async {
        guard reviewImage != nil,
              reviewOriginalImage == nil,
              let source = reviewRenderSource,
              !isSaving,
              !isRenderingReview,
              !isPreparingReviewOriginal else {
            return
        }

        reviewWorkGeneration &+= 1
        let generation = reviewWorkGeneration
        let renderer = reviewOriginalRenderer
        isPreparingReviewOriginal = true
        reviewRenderErrorMessage = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            reviewWorkQueue.submit({ [weak self] in
                    let image = renderer(source)
                    DispatchQueue.main.async { [weak self] in
                        defer { continuation.resume() }
                        guard let self,
                              self.reviewWorkGeneration == generation,
                              self.reviewRenderSource != nil else {
                            return
                        }
                        self.isPreparingReviewOriginal = false
                        guard let image else {
                            self.reviewRenderErrorMessage = "The original preview could not be prepared. Your filtered review is unchanged."
                            return
                        }
                        self.reviewOriginalImage = image
                    }
                }, onCancel: { [weak self] in
                    DispatchQueue.main.async { [weak self] in
                        defer { continuation.resume() }
                        guard let self,
                              self.reviewWorkGeneration == generation else {
                            return
                        }
                        self.isPreparingReviewOriginal = false
                    }
                })
        }
    }

    func waitForReviewWorkToDrainForTesting() async {
        await reviewWorkQueue.flush()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func saveReview(photoLibrary: any PhotoSaving) {
        guard let reviewImage, let reviewRecipe else { return }
        guard !isSaving, !isRenderingReview, !isPreparingReviewOriginal else { return }

        isSaving = true
        saveErrorMessage = nil
        saveErrorRequiresSettings = false
        reviewRenderErrorMessage = nil
        reviewWorkGeneration &+= 1
        let generation = reviewWorkGeneration
        let capturedAt = reviewCapturedAt ?? Date()

        if fullResolutionReviewRecipe == reviewRecipe,
           let reviewImageData {
            performPhotoSave(
                photoLibrary: photoLibrary,
                image: reviewImage,
                imageData: reviewImageData,
                recipe: reviewRecipe,
                capturedAt: capturedAt,
                generation: generation
            )
            return
        }

        guard let source = reviewRenderSource else {
            isSaving = false
            reviewRenderErrorMessage = "The original frame is no longer available. Keep the current review and try again."
            return
        }

        pendingPhotoSaver = photoLibrary
        let renderer = reviewFullRenderer
        reviewWorkQueue.submit { [weak self] in
            let rendered = renderer(source, reviewRecipe)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.reviewWorkGeneration == generation,
                      self.isSaving,
                      self.reviewRenderSource != nil else {
                    return
                }
                guard let rendered else {
                    self.pendingPhotoSaver = nil
                    self.isSaving = false
                    self.reviewRenderErrorMessage = "The selected look could not be prepared at full resolution. Your review is unchanged; try again."
                    return
                }
                self.reviewImage = rendered.image
                self.reviewImageData = rendered.data
                self.reviewCapturedAt = rendered.capturedAt
                self.reviewRecipe = reviewRecipe
                self.reviewIsFullResolution = rendered.isFullResolution
                self.reviewFlashFired = rendered.flashFired
                self.fullResolutionReviewRecipe = reviewRecipe
                self.fullResolutionReviewImage = rendered.image
                self.fullResolutionReviewIsFullResolution = rendered.isFullResolution
                self.fullResolutionReviewFlashFired = rendered.flashFired
                if rendered.normalizedSubjectRegions != nil {
                    self.reviewRenderSource = source.storing(
                        normalizedSubjectRegions: rendered.normalizedSubjectRegions
                    )
                }
                guard let saver = self.pendingPhotoSaver else {
                    self.isSaving = false
                    return
                }
                self.pendingPhotoSaver = nil
                self.performPhotoSave(
                    photoLibrary: saver,
                    image: rendered.image,
                    imageData: rendered.data,
                    recipe: reviewRecipe,
                    capturedAt: rendered.capturedAt,
                    generation: generation
                )
            }
        }
    }

    private func performPhotoSave(
        photoLibrary: any PhotoSaving,
        image: UIImage,
        imageData: Data,
        recipe: FilmRecipe,
        capturedAt: Date,
        generation: UInt64
    ) {
        photoLibrary.save(
            image: image,
            imageData: imageData,
            recipe: recipe,
            capturedAt: capturedAt
        ) { [weak self] result in
            guard let self, self.reviewWorkGeneration == generation else { return }
            self.isSaving = false
            switch result {
            case .success:
                self.lastCaptureDate = capturedAt
                self.clearReviewState()
                self.showToast("Saved with \(recipe.name)")
            case .failure(let error):
                self.saveErrorMessage = error.localizedDescription
                self.saveErrorRequiresSettings = error == .accessDenied
                HapticFeedback.play(.error)
            }
        }
    }

    func discardReview() {
        guard !isSaving else { return }
        clearReviewState()
    }

    private func clearReviewState() {
        reviewWorkGeneration &+= 1
        reviewWorkQueue.cancelPending()
        reviewImage = nil
        reviewImageData = nil
        reviewCapturedAt = nil
        reviewRecipe = nil
        reviewSource = .camera
        reviewIsFullResolution = true
        reviewFlashFired = false
        reviewRenderSource = nil
        fullResolutionReviewRecipe = nil
        fullResolutionReviewImage = nil
        fullResolutionReviewIsFullResolution = true
        fullResolutionReviewFlashFired = false
        reviewOriginalImage = nil
        isRenderingReview = false
        isPreparingReviewOriginal = false
        pendingReviewRecipeID = nil
        reviewRenderErrorMessage = nil
        pendingPhotoSaver = nil
        saveErrorMessage = nil
        saveErrorRequiresSettings = false
    }

    private func showToast(_ message: String, style: ToastStyle = .success) {
        toastTask?.cancel()
        toastMessage = message
        toastStyle = style
        switch style {
        case .success:
            HapticFeedback.play(.success)
        case .error:
            HapticFeedback.play(.error)
        case .info:
            HapticFeedback.play(.warning)
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(style.accessibilityTitle): \(message)"
        )
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    private nonisolated static func render(
        sourceData: Data,
        recipe: FilmRecipe,
        viewportSize: CGSize,
        previewDrawableSize: CGSize,
        capturedAt: Date,
        flashFired: Bool,
        grainSeed: UInt32,
        normalizedSubjectRegions: [CGRect]? = nil
    ) -> RenderedPhoto? {
        // Resolve the source image's EXIF orientation before applying the
        // preview crop. The finished JPEG is written with orientation=1, so
        // its pixels and dimensions must already be in display orientation.
        guard let input = CIImage(
            data: sourceData,
            options: [.applyOrientationProperty: true]
        ) else { return nil }
        let framedInput: CIImage
        if viewportSize.width > 0, viewportSize.height > 0 {
            let crop = CameraFrameLayout.aspectFillCrop(
                sourceExtent: input.extent,
                targetSize: viewportSize
            )
            // The preview rebases its aspect-fill crop to the drawable's
            // zero-origin coordinate space before filtering. Do the same for
            // stills so absolute Core Image phases cannot inherit the sensor
            // crop's x/y origin.
            framedInput = input
                .cropped(to: crop)
                .transformed(by: CGAffineTransform(
                    translationX: -crop.minX,
                    y: -crop.minY
                ))
        } else {
            let extent = input.extent
            framedInput = input.transformed(by: CGAffineTransform(
                translationX: -extent.minX,
                y: -extent.minY
            ))
        }

        let grainPhase = Self.scaledGrainPhase(
            grainSeed,
            grainSize: recipe.grainSize,
            previewSize: previewDrawableSize,
            stillSize: framedInput.extent.size
        )

        let renderContext: FilmRenderer.CaptureContext
        let resolvedSubjectRegions: [CGRect]?
        if recipe.filmBase == .compactDigital {
            let subjectRegions = normalizedSubjectRegions.map {
                denormalizedSubjectRegions($0, in: framedInput.extent)
            } ?? FilmRenderer.portraitSubjectRegions(in: framedInput)
            renderContext = FilmRenderer.CaptureContext(
                flashFired: flashFired,
                subjectRegions: subjectRegions
            )
            resolvedSubjectRegions = Self.normalizedSubjectRegions(
                subjectRegions,
                in: framedInput.extent
            )
        } else {
            renderContext = .standard
            resolvedSubjectRegions = normalizedSubjectRegions
        }

        let filtered = FilmRenderer.render(
            framedInput,
            recipe: recipe,
            quality: .photo,
            captureContext: renderContext,
            grainSeed: grainSeed,
            grainPhase: grainPhase
        )
        guard let output = FilmRenderer.outputCGImage(filtered, from: filtered.extent) else { return nil }
        guard let data = PhotoOutputEncoder.jpegData(
            for: output,
            sourceData: sourceData,
            capturedAt: capturedAt,
            recipe: recipe
        ) else {
            return nil
        }

        let reviewImage = downsampledReviewImage(from: data)
            ?? UIImage(cgImage: output)
        return RenderedPhoto(
            image: reviewImage,
            data: data,
            capturedAt: capturedAt,
            flashFired: flashFired,
            normalizedSubjectRegions: resolvedSubjectRegions
        )
    }

    /// Library imports can be panoramas or scans far larger than any capture.
    /// Full-resolution materialization of such images (RGBA buffer, filter
    /// intermediates, color-space copy, JPEG) can exhaust memory, so cap the
    /// pixel count before rendering. Everyday phone photos stay untouched.
    nonisolated static let importPixelBudget: CGFloat = 40_000_000

    nonisolated static func boundedImportInput(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let area = extent.width * extent.height
        guard area > importPixelBudget, area.isFinite, area > 0,
              let lanczos = CIFilter(name: "CILanczosScaleTransform") else {
            return image
        }

        let scale = (importPixelBudget / area).squareRoot()
        lanczos.setValue(image, forKey: kCIInputImageKey)
        lanczos.setValue(scale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        let boundedExtent = CGRect(
            x: 0,
            y: 0,
            width: max((extent.width * scale).rounded(.down), 1),
            height: max((extent.height * scale).rounded(.down), 1)
        )
        return lanczos.outputImage?.cropped(to: boundedExtent) ?? image
    }

    private nonisolated static func renderImported(
        sourceData: Data,
        recipe: FilmRecipe,
        importedAt: Date,
        normalizedSubjectRegions: [CGRect]? = nil
    ) -> RenderedPhoto? {
        guard !Task.isCancelled, let input = CIImage(
            data: sourceData,
            options: [.applyOrientationProperty: true]
        ) else { return nil }

        let extent = input.extent
        guard !extent.isEmpty, extent.width.isFinite, extent.height.isFinite else {
            return nil
        }

        // Library photos keep their original framing. Rebase to a zero origin
        // so spatial effects such as grain are independent of EXIF transforms.
        let unboundedInput = input.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let framedInput = Self.boundedImportInput(unboundedInput)
        let isFullResolution = framedInput.extent.size == unboundedInput.extent.size
        guard !Task.isCancelled else { return nil }
        let renderContext: FilmRenderer.CaptureContext
        let resolvedSubjectRegions: [CGRect]?
        if recipe.filmBase == .compactDigital {
            let subjectRegions = normalizedSubjectRegions.map {
                denormalizedSubjectRegions($0, in: framedInput.extent)
            } ?? FilmRenderer.portraitSubjectRegions(in: framedInput)
            renderContext = FilmRenderer.CaptureContext(
                subjectRegions: subjectRegions
            )
            resolvedSubjectRegions = Self.normalizedSubjectRegions(
                subjectRegions,
                in: framedInput.extent
            )
        } else {
            renderContext = .standard
            resolvedSubjectRegions = normalizedSubjectRegions
        }
        guard !Task.isCancelled else { return nil }
        let filtered = FilmRenderer.render(
            framedInput,
            recipe: recipe,
            quality: .export,
            captureContext: renderContext
        )
        guard !Task.isCancelled,
              let output = FilmRenderer.outputCGImage(filtered, from: filtered.extent),
              !Task.isCancelled,
              let data = PhotoOutputEncoder.jpegData(
                for: output,
                sourceData: sourceData,
                capturedAt: importedAt,
                recipe: recipe
              ) else {
            return nil
        }

        guard !Task.isCancelled else { return nil }
        return RenderedPhoto(
            image: downsampledReviewImage(from: data) ?? UIImage(cgImage: output),
            data: data,
            capturedAt: importedAt,
            isFullResolution: isFullResolution,
            normalizedSubjectRegions: resolvedSubjectRegions
        )
    }

    nonisolated static func renderReviewFull(
        source: ReviewRenderSource,
        recipe: FilmRecipe
    ) -> RenderedPhoto? {
        switch source.mode {
        case .camera(let viewportSize, let previewDrawableSize, let flashFired, let grainSeed):
            return render(
                sourceData: source.data,
                recipe: recipe,
                viewportSize: viewportSize,
                previewDrawableSize: previewDrawableSize,
                capturedAt: source.capturedAt,
                flashFired: flashFired,
                grainSeed: grainSeed,
                normalizedSubjectRegions: source.normalizedSubjectRegions
            )
        case .photoLibrary:
            return renderImported(
                sourceData: source.data,
                recipe: recipe,
                importedAt: source.capturedAt,
                normalizedSubjectRegions: source.normalizedSubjectRegions
            )
        }
    }

    nonisolated static func renderReviewPreview(
        source: ReviewRenderSource,
        recipe: FilmRecipe
    ) -> ReviewPreview? {
        guard let prepared = preparedReviewInput(source: source) else { return nil }
        let previewInput = boundedReviewPreviewInput(prepared.image)
        let flashFired: Bool
        let renderQuality: FilmRenderer.Quality
        let grainSeed: UInt32
        let grainPhase: CGPoint
        switch source.mode {
        case .camera(_, let previewDrawableSize, let didFireFlash, let seed):
            flashFired = didFireFlash
            renderQuality = .photo
            grainSeed = seed
            grainPhase = scaledGrainPhase(
                seed,
                grainSize: recipe.grainSize,
                previewSize: previewDrawableSize,
                stillSize: previewInput.extent.size
            )
        case .photoLibrary:
            flashFired = false
            renderQuality = .export
            grainSeed = 0
            grainPhase = .zero
        }
        let context: FilmRenderer.CaptureContext
        let resolvedSubjectRegions: [CGRect]?
        if recipe.filmBase == .compactDigital {
            let subjectRegions = source.normalizedSubjectRegions.map {
                denormalizedSubjectRegions($0, in: previewInput.extent)
            } ?? FilmRenderer.portraitSubjectRegions(in: previewInput)
            context = FilmRenderer.CaptureContext(
                flashFired: flashFired,
                subjectRegions: subjectRegions
            )
            resolvedSubjectRegions = Self.normalizedSubjectRegions(
                subjectRegions,
                in: previewInput.extent
            )
        } else {
            context = .standard
            resolvedSubjectRegions = source.normalizedSubjectRegions
        }
        let filtered = FilmRenderer.render(
            previewInput,
            recipe: recipe,
            quality: renderQuality,
            captureContext: context,
            grainSeed: grainSeed,
            grainPhase: grainPhase
        )
        guard let output = FilmRenderer.outputCGImage(filtered, from: filtered.extent) else {
            return nil
        }
        return ReviewPreview(
            image: UIImage(cgImage: output),
            isFullResolution: prepared.isFullResolution,
            flashFired: flashFired,
            normalizedSubjectRegions: resolvedSubjectRegions
        )
    }

    private nonisolated static func normalizedSubjectRegions(
        _ regions: [CGRect],
        in extent: CGRect
    ) -> [CGRect] {
        guard extent.width > 0, extent.height > 0 else { return [] }
        return regions.compactMap { region in
            let clipped = region.intersection(extent)
            guard !clipped.isNull, !clipped.isEmpty else { return nil }
            return CGRect(
                x: (clipped.minX - extent.minX) / extent.width,
                y: (clipped.minY - extent.minY) / extent.height,
                width: clipped.width / extent.width,
                height: clipped.height / extent.height
            )
        }
    }

    private nonisolated static func denormalizedSubjectRegions(
        _ regions: [CGRect],
        in extent: CGRect
    ) -> [CGRect] {
        guard extent.width > 0, extent.height > 0 else { return [] }
        return regions.map { region in
            CGRect(
                x: extent.minX + region.minX * extent.width,
                y: extent.minY + region.minY * extent.height,
                width: region.width * extent.width,
                height: region.height * extent.height
            )
        }
    }

    nonisolated static func renderReviewOriginal(
        source: ReviewRenderSource
    ) -> UIImage? {
        guard let prepared = preparedReviewInput(source: source) else { return nil }
        let previewInput = boundedReviewPreviewInput(prepared.image)
        guard let output = FilmRenderer.outputCGImage(previewInput, from: previewInput.extent) else {
            return nil
        }
        return UIImage(cgImage: output)
    }

    private nonisolated static func preparedReviewInput(
        source: ReviewRenderSource
    ) -> (image: CIImage, isFullResolution: Bool)? {
        guard let imageSource = CGImageSourceCreateWithData(source.data as CFData, nil) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            as? [String: Any]
        let sourceWidth = (properties?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue
        let sourceHeight = (properties?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_800,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) else { return nil }
        let input = CIImage(cgImage: thumbnail)
        let extent = input.extent
        guard !extent.isEmpty, extent.width.isFinite, extent.height.isFinite else {
            return nil
        }

        switch source.mode {
        case .camera(let viewportSize, _, _, _):
            if viewportSize.width > 0, viewportSize.height > 0 {
                let crop = CameraFrameLayout.aspectFillCrop(
                    sourceExtent: extent,
                    targetSize: viewportSize
                )
                return (
                    input.cropped(to: crop).transformed(by: CGAffineTransform(
                        translationX: -crop.minX,
                        y: -crop.minY
                    )),
                    true
                )
            }
            return (
                input.transformed(by: CGAffineTransform(
                    translationX: -extent.minX,
                    y: -extent.minY
                )),
                true
            )
        case .photoLibrary:
            let sourceArea = (sourceWidth ?? Double(thumbnail.width))
                * (sourceHeight ?? Double(thumbnail.height))
            return (
                input,
                sourceArea.isFinite && sourceArea <= Double(importPixelBudget)
            )
        }
    }

    private nonisolated static func boundedReviewPreviewInput(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let maximumDimension = max(extent.width, extent.height)
        guard maximumDimension.isFinite, maximumDimension > 1_800,
              let lanczos = CIFilter(name: "CILanczosScaleTransform") else {
            return image
        }
        let scale = 1_800 / maximumDimension
        lanczos.setValue(image, forKey: kCIInputImageKey)
        lanczos.setValue(scale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        let boundedExtent = CGRect(
            x: 0,
            y: 0,
            width: max((extent.width * scale).rounded(.down), 1),
            height: max((extent.height * scale).rounded(.down), 1)
        )
        return lanczos.outputImage?.cropped(to: boundedExtent) ?? image
    }

    /// FilmRenderer interprets grain phase in output pixels after scaling the
    /// deterministic texture. Match the renderer's effective texture scale
    /// for both images so clamped large-grain recipes preserve the same
    /// texture coordinates between preview and capture.
    nonisolated static func scaledGrainPhase(
        _ seed: UInt32,
        grainSize: Double = 1,
        previewSize: CGSize,
        stillSize: CGSize
    ) -> CGPoint {
        let previewPhase = CGPoint(
            x: CGFloat(seed & 0x1FF),
            y: CGFloat((seed >> 9) & 0x1FF)
        )
        let previewDimension = max(previewSize.width, previewSize.height)
        let stillDimension = max(stillSize.width, stillSize.height)
        guard previewDimension.isFinite,
              stillDimension.isFinite,
              previewDimension > 0,
              stillDimension > 0 else {
            return previewPhase
        }

        let previewTextureScale = effectiveGrainTextureScale(
            grainSize: grainSize,
            imageSize: previewSize
        )
        let stillTextureScale = effectiveGrainTextureScale(
            grainSize: grainSize,
            imageSize: stillSize
        )
        let scale = stillTextureScale / previewTextureScale
        guard scale.isFinite, scale > 0 else { return previewPhase }
        return CGPoint(
            x: previewPhase.x * scale,
            y: previewPhase.y * scale
        )
    }

    /// Keep this in lockstep with FilmRenderer's private grain scale. The
    /// phase is applied after the grain texture transform, so the effective
    /// (including clamped) scale—not just the image-size ratio—is the mapping
    /// that keeps preview and still coordinates aligned.
    nonisolated static func effectiveGrainTextureScale(
        grainSize: Double,
        imageSize: CGSize
    ) -> CGFloat {
        let outputDimension = max(imageSize.width, imageSize.height)
        guard outputDimension.isFinite, outputDimension > 0 else { return 1 }

        let resolutionScale = max(outputDimension / 1080, 0.5)
        let finiteGrainSize = grainSize.isFinite ? CGFloat(grainSize) : 1
        return max(0.35, min(finiteGrainSize * resolutionScale, 8))
    }

    private nonisolated static func downsampledReviewImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

}
