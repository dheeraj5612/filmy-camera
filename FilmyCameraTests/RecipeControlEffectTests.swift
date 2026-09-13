import CoreImage
import UIKit
import XCTest
@testable import FilmyCamera

/// Proves that each exposed numeric recipe control changes decoded pixels,
/// using the relevant prerequisite mode and a fixture with tone, hue, edges,
/// noise, and bright detail. Model-value round trips cannot catch a dead FX.
final class RecipeControlEffectTests: XCTestCase {
    func testEveryNumericRecipeControlChangesRenderedPixels() throws {
        let input = Self.controlFixture()
        XCTAssertEqual(Set(Self.controls.map(\.0)), Set(FilmRecipe.Control.allCases),
                       "A new numeric control needs a rendered-pixel acceptance case")
        var observations: [String] = []
        for (control, keyPath) in Self.controls {
            try autoreleasepool {
                let isMonochrome = control == .monochromaticWarmCool || control == .monochromaticGreenMagenta
                var low = FilmRecipe(id: "control-\(control.rawValue)", name: control.displayName,
                                     subtitle: "Control acceptance", filmBase: isMonochrome ? .acros : .standard,
                                     saturation: isMonochrome ? 0 : 1,
                                     palette: .init(saturation: isMonochrome ? 0 : 1))
                if control == .colorTemperature { low.whiteBalance.mode = .colorTemperature }
                if control == .grainSize { low.grain = 1 }
                var high = low
                low[keyPath: keyPath] = control.editorRange.lowerBound
                high[keyPath: keyPath] = control.editorRange.upperBound
                let lowPixels = Self.pixels(FilmRenderer.render(input, recipe: low, quality: .photo, grainSeed: 73))
                let highPixels = Self.pixels(FilmRenderer.render(input, recipe: high, quality: .photo, grainSeed: 73))
                XCTAssertTrue(lowPixels.allSatisfy(\.isFinite), control.rawValue)
                XCTAssertTrue(highPixels.allSatisfy(\.isFinite), control.rawValue)
                let difference = Self.meanRGBDifference(lowPixels, highPixels)
                XCTAssertGreaterThan(difference, 0.000_001,
                                     "\(control.displayName) has no observable effect on rendered pixels")
                observations.append("\(control.rawValue): endpoint mean RGB difference=\(difference)")
                let lowImage = try XCTUnwrap(FilmRenderer.outputCGImage(
                    FilmRenderer.render(input, recipe: low, quality: .photo, grainSeed: 73)))
                let highImage = try XCTUnwrap(FilmRenderer.outputCGImage(
                    FilmRenderer.render(input, recipe: high, quality: .photo, grainSeed: 73)))
                for (name, image) in [("minimum", lowImage), ("maximum", highImage)] {
                    let attachment = XCTAttachment(image: UIImage(cgImage: image))
                    attachment.name = "control-\(control.rawValue)-\(name)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "every-numeric-control-pixel-response"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testIncandescentWhiteBalanceReducesWarmCastAtEveryQuality() throws {
        let input = CIImage(color: CIColor(red: 0.62, green: 0.50, blue: 0.40))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            var recipe = FilmRecipe(id: "tungsten-compensation", name: "WB", subtitle: "Test")
            let asShot = Self.pixels(FilmRenderer.render(input, recipe: recipe, quality: quality))
            recipe.whiteBalance.mode = .incandescent
            let balanced = Self.pixels(FilmRenderer.render(input, recipe: recipe, quality: quality))
            XCTAssertLessThan(Self.meanRedMinusBlue(balanced), Self.meanRedMinusBlue(asShot) - 0.001,
                              "Incandescent should compensate tungsten warmth, not increase it")
        }
    }

    func testUnderwaterWhiteBalanceReducesBlueCastAtEveryQuality() throws {
        let input = CIImage(color: CIColor(red: 0.38, green: 0.50, blue: 0.62))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            var recipe = FilmRecipe(id: "underwater-compensation", name: "WB", subtitle: "Test")
            let asShot = Self.pixels(FilmRenderer.render(input, recipe: recipe, quality: quality))
            recipe.whiteBalance.mode = .underwater
            let balanced = Self.pixels(FilmRenderer.render(input, recipe: recipe, quality: quality))
            XCTAssertGreaterThan(Self.meanRedMinusBlue(balanced), Self.meanRedMinusBlue(asShot) + 0.001,
                                 "Underwater should reduce blue cast, not increase it")
        }
    }

    func testPositiveHighlightsBrightenAndPositiveShadowsDarkenAtEveryQuality() {
        // Public directional contract:
        // https://www.fujifilm-x.com/en-gb/learning-centre/creating-your-own-black-white-look/
        let extent = CGRect(x: 0, y: 0, width: 16, height: 16)
        let highlights = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)).cropped(to: extent)
        let shadows = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: extent)
        for quality in [FilmRenderer.Quality.preview, .photo, .export] {
            let neutral = FilmRecipe(id: "tone-polarity", name: "Tone", subtitle: "Test")
            var harderHighlights = neutral
            harderHighlights.tone.highlight = 1
            var softerHighlights = neutral
            softerHighlights.tone.highlight = -1
            let brightReference = Self.pixels(FilmRenderer.render(highlights, recipe: neutral, quality: quality))[0]
            XCTAssertGreaterThan(Self.pixels(FilmRenderer.render(highlights, recipe: harderHighlights, quality: quality))[0],
                                 brightReference + 0.001)
            XCTAssertLessThan(Self.pixels(FilmRenderer.render(highlights, recipe: softerHighlights, quality: quality))[0],
                              brightReference - 0.001)
            var harderShadows = neutral
            harderShadows.tone.shadow = 1
            var softerShadows = neutral
            softerShadows.tone.shadow = -1
            let darkReference = Self.pixels(FilmRenderer.render(shadows, recipe: neutral, quality: quality))[0]
            XCTAssertLessThan(Self.pixels(FilmRenderer.render(shadows, recipe: harderShadows, quality: quality))[0],
                              darkReference - 0.001)
            XCTAssertGreaterThan(Self.pixels(FilmRenderer.render(shadows, recipe: softerShadows, quality: quality))[0],
                                 darkReference + 0.001)
        }
    }

    private static var controls: [(FilmRecipe.Control, WritableKeyPath<FilmRecipe, Double>)] { [
        (.exposure, \.exposure), (.highlights, \.tone.highlight), (.shadows, \.tone.shadow),
        (.color, \.saturation), (.contrast, \.contrast), (.colorChrome, \.colorChrome),
        (.blueResponse, \.blueResponse), (.fxBlue, \.fxBlue), (.temperature, \.whiteBalance.temperature),
        (.tint, \.whiteBalance.tint), (.colorTemperature, \.whiteBalance.kelvin),
        (.monochromaticWarmCool, \.monochromaticColor.warmCool),
        (.monochromaticGreenMagenta, \.monochromaticColor.greenMagenta),
        (.sharpness, \.sharpness), (.noiseReduction, \.noiseReduction), (.clarity, \.clarity),
        (.grain, \.grain), (.grainSize, \.grainSize), (.vignette, \.vignette), (.halation, \.halation),
        (.paletteRedBias, \.palette.redBias), (.paletteGreenBias, \.palette.greenBias),
        (.paletteBlueBias, \.palette.blueBias), (.paletteRedGreenMix, \.palette.redGreenMix),
        (.paletteGreenBlueMix, \.palette.greenBlueMix), (.paletteBlueRedMix, \.palette.blueRedMix),
        (.paletteSaturation, \.palette.saturation)
    ] }

    private static func pixels(_ image: CIImage) -> [Float] {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        FilmRenderer.sharedContext.render(image, toBitmap: &pixels,
                                          rowBytes: width * 4 * MemoryLayout<Float>.size,
                                          bounds: image.extent, format: .RGBAf,
                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return pixels
    }

    private static func meanRGBDifference(_ lhs: [Float], _ rhs: [Float]) -> Double {
        var total: Double = 0
        for offset in stride(from: 0, to: lhs.count, by: 4) {
            for channel in 0..<3 { total += Double(abs(lhs[offset + channel] - rhs[offset + channel])) }
        }
        return total / Double(lhs.count / 4 * 3)
    }

    private static func meanRedMinusBlue(_ pixels: [Float]) -> Double {
        var total: Double = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            total += Double(pixels[offset] - pixels[offset + 2])
        }
        return total / Double(pixels.count / 4)
    }

    private static func controlFixture() -> CIImage {
        let width = 256, height = 192
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let texture = ((x * 37 + y * 71) % 11) - 5
                let red = y < height / 2 ? x * 255 / (width - 1) : 128 + (x % 32 < 16 ? -75 : 75)
                let green = y < height / 2 ? red : y * 255 / (height - 1)
                let blue = y < height / 2 ? red : 255 - x * 255 / (width - 1)
                for (channel, value) in [red, green, blue].enumerated() {
                    bytes[offset + channel] = UInt8(clamping: value + texture)
                }
            }
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4,
                       size: CGSize(width: width, height: height), format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
