import SwiftUI

/// A film-inspired set of camera and finishing controls.
///
/// The values intentionally mirror the public vocabulary used by modern film
/// cameras. They are data, rather than a collection of opaque filter names, so
/// the renderer and the UI can both inspect the look.
public struct FilmRecipe: Identifiable, Codable, Hashable, Sendable {
    public enum FilmBase: String, CaseIterable, Codable, Hashable, Sendable {
        case standard
        case provia
        case classicChrome
        case velvia
        case astia
        case proNegative
        case proNegStandard
        case eterna
        case eternaBleachBypass
        case acros
        case acrosYellow
        case acrosRed
        case acrosGreen
        case classicNegative
        case nostalgicNegative
        case realaAce
        case monochrome

        public var displayName: String {
            switch self {
            case .standard, .provia: return "Provia / Standard"
            case .classicChrome: return "Classic Chrome"
            case .velvia: return "Velvia / Vivid"
            case .astia: return "Astia / Soft"
            case .proNegative: return "Pro Neg. High"
            case .proNegStandard: return "Pro Neg. Standard"
            case .eterna: return "Eterna / Cinema"
            case .eternaBleachBypass: return "Eterna Bleach Bypass"
            case .acros: return "Acros"
            case .acrosYellow: return "Acros + Ye Filter"
            case .acrosRed: return "Acros + R Filter"
            case .acrosGreen: return "Acros + G Filter"
            case .classicNegative: return "Classic Negative"
            case .nostalgicNegative: return "Nostalgic Negative"
            case .realaAce: return "Reala Ace"
            case .monochrome: return "Acros Monochrome"
            }
        }
    }

    /// Public Fujifilm-style dynamic-range modes. These are expressed as
    /// capture/render intent; JPEG input cannot recover highlights that were
    /// already clipped by the source camera.
    public enum DynamicRange: Int, CaseIterable, Codable, Hashable, Sendable {
        case dr100 = 100
        case dr200 = 200
        case dr400 = 400

        public var displayName: String { "DR\(rawValue)" }

        var highlightProtection: Double {
            switch self {
            case .dr100: return 0
            case .dr200: return 0.16
            case .dr400: return 0.30
            }
        }
    }

    public struct Palette: Codable, Hashable, Sendable {
        public var redBias: Double
        public var greenBias: Double
        public var blueBias: Double
        public var redGreenMix: Double
        public var greenBlueMix: Double
        public var blueRedMix: Double
        public var saturation: Double

        public init(
            redBias: Double = 0,
            greenBias: Double = 0,
            blueBias: Double = 0,
            redGreenMix: Double = 0,
            greenBlueMix: Double = 0,
            blueRedMix: Double = 0,
            saturation: Double = 1
        ) {
            self.redBias = redBias
            self.greenBias = greenBias
            self.blueBias = blueBias
            self.redGreenMix = redGreenMix
            self.greenBlueMix = greenBlueMix
            self.blueRedMix = blueRedMix
            self.saturation = saturation
        }
    }

    public struct Tone: Codable, Hashable, Sendable {
        public var highlight: Double
        public var shadow: Double

        public init(highlight: Double = 0, shadow: Double = 0) {
            self.highlight = highlight
            self.shadow = shadow
        }
    }

    public struct WhiteBalanceShift: Codable, Hashable, Sendable {
        /// A normalized temperature shift. Positive values warm the image.
        public var temperature: Double
        /// A normalized tint shift. Positive values move toward magenta.
        public var tint: Double

        public init(temperature: Double = 0, tint: Double = 0) {
            self.temperature = temperature
            self.tint = tint
        }
    }

    public let id: String
    public let name: String
    public let subtitle: String
    public let filmBase: FilmBase
    public var exposure: Double
    public var tone: Tone
    public var saturation: Double
    public var contrast: Double
    public var dynamicRange: DynamicRange
    public var whiteBalance: WhiteBalanceShift
    public var colorChrome: Double
    public var blueResponse: Double
    public var fxBlue: Double
    public var sharpness: Double
    public var noiseReduction: Double
    public var clarity: Double
    public var grain: Double
    public var grainSize: Double
    public var vignette: Double
    public var halation: Double
    public var palette: Palette

    public init(
        id: String,
        name: String,
        subtitle: String,
        filmBase: FilmBase = .standard,
        exposure: Double = 0,
        tone: Tone = Tone(),
        saturation: Double = 1,
        contrast: Double = 1,
        dynamicRange: DynamicRange = .dr100,
        whiteBalance: WhiteBalanceShift = WhiteBalanceShift(),
        colorChrome: Double = 0,
        blueResponse: Double = 0,
        fxBlue: Double = 0,
        sharpness: Double = 0,
        noiseReduction: Double = 0,
        clarity: Double = 0,
        grain: Double = 0,
        grainSize: Double = 1,
        vignette: Double = 0,
        halation: Double = 0,
        palette: Palette = Palette()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.filmBase = filmBase
        self.exposure = exposure
        self.tone = tone
        self.saturation = saturation
        self.contrast = contrast
        self.dynamicRange = dynamicRange
        self.whiteBalance = whiteBalance
        self.colorChrome = colorChrome
        self.blueResponse = blueResponse
        self.fxBlue = fxBlue
        self.sharpness = sharpness
        self.noiseReduction = noiseReduction
        self.clarity = clarity
        self.grain = grain
        self.grainSize = grainSize
        self.vignette = vignette
        self.halation = halation
        self.palette = palette
    }

    // These aliases keep the model convenient for controls that use the same
    // terms as the camera UI.
    public var highlightTone: Double { tone.highlight }
    public var shadowTone: Double { tone.shadow }
    public var temperatureShift: Double { whiteBalance.temperature }
    public var tintShift: Double { whiteBalance.tint }
    public var grainAmount: Double { grain }
    public var vignetteAmount: Double { vignette }

    /// Colors used by the recipe rail and other lightweight UI previews.
    /// The renderer never uses these swatches as image data; they are UI hints.
    public static let previewColors: [Color] = [
        Color(red: 0.44, green: 0.34, blue: 0.25),
        Color(red: 0.58, green: 0.28, blue: 0.18),
        Color(red: 0.32, green: 0.43, blue: 0.39),
        Color(red: 0.25, green: 0.35, blue: 0.43),
        Color(red: 0.56, green: 0.44, blue: 0.28),
        Color(red: 0.68, green: 0.68, blue: 0.62)
    ]

    /// The initial recipe library. Names refer to public film-camera
    /// conventions; the app is not affiliated with or calibrated by Fujifilm.
    public static let builtIns: [FilmRecipe] = [
        FilmRecipe(
            id: "provia-standard",
            name: "Provia Standard",
            subtitle: "Natural color / clean daylight",
            filmBase: .provia,
            tone: Tone(highlight: 0.02, shadow: 0.00),
            saturation: 1.00,
            contrast: 1.00,
            dynamicRange: .dr100,
            whiteBalance: WhiteBalanceShift(),
            colorChrome: 0.18,
            blueResponse: 0.02,
            fxBlue: 0.00,
            sharpness: 0.02,
            noiseReduction: 0.01,
            clarity: 0.02,
            grain: 0.08,
            grainSize: 0.78,
            vignette: 0.04,
            halation: 0.01,
            palette: Palette(
                redBias: 0.006,
                greenBias: 0.004,
                blueBias: 0.004,
                redGreenMix: 0.004,
                greenBlueMix: 0.002,
                blueRedMix: 0.004,
                saturation: 1.00
            )
        ),
        FilmRecipe(
            id: "classic-chrome",
            name: "Classic Chrome",
            subtitle: "Muted color / hard light",
            filmBase: .classicChrome,
            tone: Tone(highlight: -0.18, shadow: 0.10),
            saturation: 0.88,
            contrast: 1.06,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.02, tint: -0.01),
            colorChrome: 0.72,
            blueResponse: 0.18,
            fxBlue: 0.16,
            sharpness: 0.04,
            noiseReduction: 0.01,
            clarity: 0.10,
            grain: 0.16,
            grainSize: 1.0,
            vignette: 0.12,
            halation: 0.04,
            palette: Palette(
                redBias: 0.012,
                greenBias: 0.004,
                blueBias: -0.012,
                redGreenMix: 0.018,
                greenBlueMix: -0.010,
                blueRedMix: -0.014,
                saturation: 0.96
            )
        ),
        FilmRecipe(
            id: "velvia-vivid",
            name: "Velvia Vivid",
            subtitle: "Deep color / rich contrast",
            filmBase: .velvia,
            tone: Tone(highlight: -0.08, shadow: -0.14),
            saturation: 1.22,
            contrast: 1.12,
            dynamicRange: .dr100,
            whiteBalance: WhiteBalanceShift(temperature: 0.04, tint: -0.02),
            colorChrome: 0.86,
            blueResponse: 0.34,
            fxBlue: 0.34,
            sharpness: 0.16,
            noiseReduction: 0.01,
            clarity: 0.18,
            grain: 0.12,
            grainSize: 0.85,
            vignette: 0.10,
            halation: 0.02,
            palette: Palette(
                redBias: 0.016,
                greenBias: 0.010,
                blueBias: 0.022,
                redGreenMix: 0.028,
                greenBlueMix: -0.020,
                blueRedMix: 0.014,
                saturation: 1.06
            )
        ),
        FilmRecipe(
            id: "astia-soft",
            name: "Astia Soft",
            subtitle: "Portrait color / gentle rolloff",
            filmBase: .astia,
            tone: Tone(highlight: 0.10, shadow: 0.08),
            saturation: 1.02,
            contrast: 0.96,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.03, tint: 0.02),
            colorChrome: 0.34,
            blueResponse: 0.04,
            fxBlue: 0.05,
            sharpness: -0.02,
            noiseReduction: 0.03,
            clarity: 0.02,
            grain: 0.10,
            grainSize: 0.90,
            vignette: 0.08,
            halation: 0.03,
            palette: Palette(
                redBias: 0.018,
                greenBias: 0.006,
                blueBias: -0.004,
                redGreenMix: 0.010,
                greenBlueMix: 0.002,
                blueRedMix: -0.004,
                saturation: 0.99
            )
        ),
        FilmRecipe(
            id: "pro-neg-high",
            name: "Pro Neg. High",
            subtitle: "Neutral color / defined edges",
            filmBase: .proNegative,
            tone: Tone(highlight: -0.06, shadow: -0.02),
            saturation: 0.96,
            contrast: 1.08,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.01, tint: 0.01),
            colorChrome: 0.28,
            blueResponse: 0.02,
            fxBlue: 0.02,
            sharpness: 0.12,
            noiseReduction: 0.03,
            clarity: 0.16,
            grain: 0.11,
            grainSize: 0.78,
            vignette: 0.06,
            halation: 0.01,
            palette: Palette(
                redBias: 0.010,
                greenBias: 0.004,
                blueBias: 0.000,
                redGreenMix: 0.006,
                greenBlueMix: -0.004,
                blueRedMix: -0.004,
                saturation: 0.98
            )
        ),
        FilmRecipe(
            id: "eterna-cinema",
            name: "Eterna Cinema",
            subtitle: "Low saturation / soft shadows",
            filmBase: .eterna,
            tone: Tone(highlight: 0.16, shadow: 0.18),
            saturation: 0.78,
            contrast: 0.91,
            dynamicRange: .dr400,
            whiteBalance: WhiteBalanceShift(temperature: -0.02, tint: -0.01),
            colorChrome: 0.20,
            blueResponse: -0.06,
            fxBlue: -0.06,
            sharpness: -0.04,
            noiseReduction: 0.05,
            clarity: -0.04,
            grain: 0.18,
            grainSize: 1.15,
            vignette: 0.16,
            halation: 0.10,
            palette: Palette(
                redBias: 0.004,
                greenBias: 0.010,
                blueBias: 0.016,
                redGreenMix: -0.006,
                greenBlueMix: 0.010,
                blueRedMix: 0.002,
                saturation: 0.96
            )
        ),
        FilmRecipe(
            id: "acros-monochrome",
            name: "Acros Monochrome",
            subtitle: "Fine grain / tonal depth",
            filmBase: .monochrome,
            tone: Tone(highlight: -0.04, shadow: -0.12),
            saturation: 0,
            contrast: 1.08,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(),
            colorChrome: 0,
            blueResponse: 0,
            fxBlue: 0,
            sharpness: 0.10,
            noiseReduction: 0.02,
            clarity: 0.12,
            grain: 0.14,
            grainSize: 0.72,
            vignette: 0.14,
            halation: 0.02,
            palette: Palette(
                redBias: 0,
                greenBias: 0,
                blueBias: 0,
                redGreenMix: 0,
                greenBlueMix: 0,
                blueRedMix: 0,
                saturation: 0
            )
        ),
        FilmRecipe(
            id: "classic-negative",
            name: "Classic Negative",
            subtitle: "Cyan shadows / warm highlights",
            filmBase: .classicNegative,
            tone: Tone(highlight: -0.06, shadow: 0.18),
            saturation: 0.96,
            contrast: 1.04,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.03, tint: 0.01),
            colorChrome: 0.56,
            blueResponse: 0.24,
            fxBlue: 0.20,
            sharpness: 0.02,
            noiseReduction: 0.02,
            clarity: 0.06,
            grain: 0.20,
            grainSize: 1.12,
            vignette: 0.14,
            halation: 0.06,
            palette: Palette(
                redBias: 0.018,
                greenBias: 0.002,
                blueBias: 0.012,
                redGreenMix: -0.012,
                greenBlueMix: 0.006,
                blueRedMix: 0.022,
                saturation: 0.98
            )
        ),
        FilmRecipe(
            id: "nostalgic-negative",
            name: "Nostalgic Negative",
            subtitle: "Amber light / cool shadows",
            filmBase: .nostalgicNegative,
            tone: Tone(highlight: -0.08, shadow: 0.16),
            saturation: 1.02,
            contrast: 1.02,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.08, tint: 0.01),
            colorChrome: 0.58,
            blueResponse: 0.30,
            fxBlue: 0.26,
            sharpness: 0.01,
            noiseReduction: 0.02,
            clarity: 0.03,
            grain: 0.24,
            grainSize: 1.35,
            vignette: 0.18,
            halation: 0.12,
            palette: Palette(
                redBias: 0.024,
                greenBias: -0.004,
                blueBias: 0.020,
                redGreenMix: 0.012,
                greenBlueMix: 0.010,
                blueRedMix: -0.018,
                saturation: 1.00
            )
        ),
        FilmRecipe(
            id: "eterna-bleach-bypass",
            name: "Eterna Bleach Bypass",
            subtitle: "Desaturated / high contrast cinema",
            filmBase: .eternaBleachBypass,
            tone: Tone(highlight: -0.12, shadow: -0.16),
            saturation: 0.54,
            contrast: 1.18,
            dynamicRange: .dr400,
            whiteBalance: WhiteBalanceShift(temperature: -0.02, tint: -0.02),
            colorChrome: 0.10,
            blueResponse: 0.08,
            fxBlue: 0.10,
            sharpness: 0.16,
            noiseReduction: 0.02,
            clarity: 0.14,
            grain: 0.22,
            grainSize: 1.18,
            vignette: 0.18,
            halation: 0.04,
            palette: Palette(
                redBias: 0.004,
                greenBias: 0.008,
                blueBias: 0.014,
                redGreenMix: 0.002,
                greenBlueMix: 0.008,
                blueRedMix: 0.004,
                saturation: 0.94
            )
        ),
        FilmRecipe(
            id: "pro-neg-standard",
            name: "Pro Neg. Standard",
            subtitle: "Soft portrait / natural gradation",
            filmBase: .proNegStandard,
            tone: Tone(highlight: 0.08, shadow: 0.10),
            saturation: 0.92,
            contrast: 0.94,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.02, tint: 0.02),
            colorChrome: 0.18,
            blueResponse: 0.02,
            fxBlue: 0.02,
            sharpness: -0.02,
            noiseReduction: 0.04,
            clarity: -0.04,
            grain: 0.12,
            grainSize: 0.84,
            vignette: 0.08,
            halation: 0.03,
            palette: Palette(
                redBias: 0.016,
                greenBias: 0.004,
                blueBias: -0.002,
                redGreenMix: 0.006,
                greenBlueMix: 0.002,
                blueRedMix: -0.002,
                saturation: 0.98
            )
        ),
        FilmRecipe(
            id: "reala-ace",
            name: "Reala Ace",
            subtitle: "Natural color / gentle cyan",
            filmBase: .realaAce,
            tone: Tone(highlight: 0.02, shadow: 0.03),
            saturation: 0.96,
            contrast: 1.00,
            dynamicRange: .dr200,
            whiteBalance: WhiteBalanceShift(temperature: 0.01, tint: 0.01),
            colorChrome: 0.18,
            blueResponse: 0.14,
            fxBlue: 0.12,
            sharpness: 0.02,
            noiseReduction: 0.02,
            clarity: 0.02,
            grain: 0.10,
            grainSize: 0.90,
            vignette: 0.06,
            halation: 0.02,
            palette: Palette(
                redBias: 0.012,
                greenBias: 0.004,
                blueBias: 0.008,
                redGreenMix: 0.006,
                greenBlueMix: 0.004,
                blueRedMix: 0.006,
                saturation: 0.99
            )
        )
    ]
}
