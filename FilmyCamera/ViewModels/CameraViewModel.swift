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
        case "classic-negative": return "Warm highlights, restrained greens, and a textured negative feel for street scenes and quiet rooms."
        case "nostalgic-negative": return "Amber light, softened blues, and gentle contrast for a memory-like everyday palette."
        case "reala-ace": return "Natural color, open shadows, and a clean negative finish that lets the scene stay itself."
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
        case "classic-negative":
            return [Color(red: 0.13, green: 0.21, blue: 0.22), Color(red: 0.69, green: 0.44, blue: 0.30), Color(red: 0.92, green: 0.73, blue: 0.51)]
        case "nostalgic-negative":
            return [Color(red: 0.18, green: 0.23, blue: 0.26), Color(red: 0.72, green: 0.48, blue: 0.34), Color(red: 0.89, green: 0.71, blue: 0.50)]
        case "reala-ace":
            return [Color(red: 0.16, green: 0.25, blue: 0.27), Color(red: 0.58, green: 0.51, blue: 0.42), Color(red: 0.86, green: 0.79, blue: 0.66)]
        default:
            return Self.previewColors
        }
    }

    var controlSummary: [(String, String)] {
        [
            ("Tone", contrast >= 1.08 ? "Hard" : contrast <= 0.96 ? "Soft" : "Balanced"),
            ("Color", saturation >= 1.08 ? "Rich" : saturation <= 0.9 ? "Muted" : "Natural"),
            ("Grain", grain >= 0.18 ? "Strong" : grain > 0 ? "Fine" : "Off"),
            ("Chrome", colorChrome >= 0.5 ? "Deep" : colorChrome > 0 ? "Subtle" : "Off")
        ]
    }
}

@MainActor
final class CameraViewModel: ObservableObject {
    private struct RenderedPhoto: @unchecked Sendable {
        let image: UIImage
        let data: Data
        let capturedAt: Date
    }

    @Published var selectedRecipeID: String = UserDefaults.standard.string(forKey: "selectedRecipeID") ?? FilmRecipe.builtIns[0].id {
        didSet {
            UserDefaults.standard.set(selectedRecipeID, forKey: "selectedRecipeID")
        }
    }
    @Published private(set) var isCapturing = false
    @Published private(set) var isSaving = false
    @Published private(set) var saveErrorMessage: String?
    @Published private(set) var toastMessage: String?
    @Published private(set) var lastCaptureDate: Date?
    @Published private(set) var reviewImage: UIImage?
    @Published private(set) var reviewRecipe: FilmRecipe?
    @Published private var recipeOverrides: [String: FilmRecipe] = [:]

    private var toastTask: Task<Void, Never>?
    private var reviewImageData: Data?
    private var reviewCapturedAt: Date?

    init() {
        guard let data = UserDefaults.standard.data(forKey: "recipeOverrides"),
              let savedRecipes = try? JSONDecoder().decode([String: FilmRecipe].self, from: data) else {
            return
        }
        recipeOverrides = savedRecipes
    }

    var selectedRecipe: FilmRecipe {
        recipeOverrides[selectedRecipeID]
            ?? FilmRecipe.builtIns.first(where: { $0.id == selectedRecipeID })
            ?? FilmRecipe.builtIns[0]
    }

    func select(recipe: FilmRecipe) {
        selectedRecipeID = recipe.id
    }

    func originalRecipe(for id: String) -> FilmRecipe {
        FilmRecipe.builtIns.first(where: { $0.id == id }) ?? FilmRecipe.builtIns[0]
    }

    func update(recipe: FilmRecipe) {
        recipeOverrides[recipe.id] = recipe
        persistRecipeOverrides()
    }

    func reset(recipeID: String) {
        recipeOverrides.removeValue(forKey: recipeID)
        persistRecipeOverrides()
    }

    func isCustomized(_ recipe: FilmRecipe) -> Bool {
        recipeOverrides[recipe.id] != nil
    }

    private func persistRecipeOverrides() {
        guard let data = try? JSONEncoder().encode(recipeOverrides) else { return }
        UserDefaults.standard.set(data, forKey: "recipeOverrides")
    }

    func capture(camera: CameraService) {
        guard !isCapturing else { return }
        isCapturing = true
        saveErrorMessage = nil
        let recipe = selectedRecipe
        let viewportSize = camera.previewViewportSize

        camera.capturePhoto { [weak self] capturedPhoto in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard let capturedPhoto else {
                    self.isCapturing = false
                    if camera.availability == .simulator {
                        self.showToast("Capture is available on a physical iPhone")
                    } else {
                        self.showToast("Capture could not be completed. Resume the camera and try again.")
                    }
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let renderedPhoto = autoreleasepool {
                        Self.render(
                            sourceData: capturedPhoto.fileData,
                            recipe: recipe,
                            viewportSize: viewportSize,
                            capturedAt: capturedPhoto.capturedAt,
                            grainSeed: Self.grainSeed(
                                for: capturedPhoto.capturedAt,
                                dimensions: capturedPhoto.dimensions
                            )
                        )
                    }

                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isCapturing = false
                        guard let renderedPhoto else {
                            self.showToast("The selected look could not be rendered. Try the capture again.")
                            return
                        }
                        self.reviewImage = renderedPhoto.image
                        self.reviewImageData = renderedPhoto.data
                        self.reviewCapturedAt = renderedPhoto.capturedAt
                        self.reviewRecipe = recipe
                    }
                }
            }
        }
    }

    func saveReview(photoLibrary: PhotoLibraryService) {
        guard let reviewImage, let reviewRecipe else { return }
        guard !isSaving else { return }

        isSaving = true
        saveErrorMessage = nil
        photoLibrary.save(
            image: reviewImage,
            imageData: reviewImageData,
            recipe: reviewRecipe,
            capturedAt: reviewCapturedAt ?? Date()
        ) { [weak self] saved in
            guard let self else { return }
            self.isSaving = false
            if saved {
                self.lastCaptureDate = self.reviewCapturedAt ?? Date()
                self.reviewImage = nil
                self.reviewImageData = nil
                self.reviewCapturedAt = nil
                self.reviewRecipe = nil
                self.showToast("Saved with \(reviewRecipe.name)")
            } else {
                self.saveErrorMessage = "Photo access is needed to save this frame. Enable Photos access in Settings, then try again."
            }
        }
    }

    func discardReview() {
        guard !isSaving else { return }
        reviewImage = nil
        reviewImageData = nil
        reviewCapturedAt = nil
        reviewRecipe = nil
        saveErrorMessage = nil
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
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
        capturedAt: Date,
        grainSeed: UInt32
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
            framedInput = input.cropped(to: crop)
        } else {
            framedInput = input
        }

        let filtered = FilmRenderer.render(
            framedInput,
            recipe: recipe,
            quality: .photo,
            grainSeed: grainSeed
        )
        guard let output = FilmRenderer.sharedContext.createCGImage(filtered, from: filtered.extent) else { return nil }
        guard let data = PhotoOutputEncoder.jpegData(
            for: output,
            sourceData: sourceData,
            capturedAt: capturedAt
        ) else {
            return nil
        }

        let reviewImage = downsampledReviewImage(from: data)
            ?? UIImage(cgImage: output)
        return RenderedPhoto(
            image: reviewImage,
            data: data,
            capturedAt: capturedAt
        )
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

    private nonisolated static func grainSeed(
        for date: Date,
        dimensions: CMVideoDimensions
    ) -> UInt32 {
        let timestamp = UInt32(truncatingIfNeeded: Int64(date.timeIntervalSince1970.rounded()))
        let width = UInt32(truncatingIfNeeded: dimensions.width)
        let height = UInt32(truncatingIfNeeded: dimensions.height)
        return timestamp &* 1_664_525 &+ width &* 1_013 &+ height
    }

}
