import Combine
import CoreImage
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
    @Published var selectedRecipeID: String = FilmRecipe.builtIns[0].id
    @Published private(set) var isCapturing = false
    @Published private(set) var toastMessage: String?
    @Published private(set) var lastCaptureDate: Date?

    private var toastTask: Task<Void, Never>?

    var selectedRecipe: FilmRecipe {
        FilmRecipe.builtIns.first(where: { $0.id == selectedRecipeID }) ?? FilmRecipe.builtIns[0]
    }

    func select(recipe: FilmRecipe) {
        selectedRecipeID = recipe.id
    }

    func capture(camera: CameraService, photoLibrary: PhotoLibraryService) {
        guard !isCapturing else { return }
        isCapturing = true
        let recipe = selectedRecipe

        camera.capturePhoto { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard let image else {
                    self.isCapturing = false
                    self.showToast("Capture is available on a physical iPhone")
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let finishedImage = Self.render(image: image, recipe: recipe) ?? image

                    DispatchQueue.main.async {
                        guard let self else { return }
                        photoLibrary.save(image: finishedImage) { [weak self] saved in
                            guard let self else { return }
                            self.isCapturing = false
                            if saved {
                                self.lastCaptureDate = Date()
                                self.showToast("Saved with \(recipe.name)")
                            } else {
                                self.showToast("Photo access is needed to save")
                            }
                        }
                    }
                }
            }
        }
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

    private nonisolated static func render(image: UIImage, recipe: FilmRecipe) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let filtered = FilmRenderer.render(input, recipe: recipe, quality: .photo)
        guard let output = FilmRenderer.sharedContext.createCGImage(filtered, from: filtered.extent) else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}
