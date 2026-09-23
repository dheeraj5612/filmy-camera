import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The SDR film transform is unchanged. HDR is reconstructed after that
/// transform using the captured HDR/SDR luminance ratio, in linear light. This
/// preserves captured highlight headroom without inventing HDR from SDR or
/// incorrectly attaching the original gain map to newly graded SDR pixels.
enum ProPhotoOutput {
    nonisolated(unsafe) static let context: CIContext = {
        var options: [CIContextOption: Any] = [.cacheIntermediates: false, .workingFormat: CIFormat.RGBAh]
        // Match the established film pipeline's working space, including its
        // skin and halation regression fixes. Only the output profile changes.
        options[.workingColorSpace] = CGColorSpace(name: CGColorSpace.sRGB)
        if let device = FilmRenderer.metalDevice { return CIContext(mtlDevice: device, options: options) }
        options[.useSoftwareRenderer] = true
        return CIContext(options: options)
    }()

    nonisolated(unsafe) private static let headroomKernel = CIColorKernel(source: """
        vec3 linearize(vec3 c) {
            c = max(c, vec3(0.0));
            return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
        }
        vec3 encodeSRGB(vec3 c) {
            c = max(c, vec3(0.0));
            return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
        }
        kernel vec4 restoreCapturedHeadroom(__sample film, __sample sourceSDR, __sample sourceHDR) {
            vec3 weights = vec3(0.2126, 0.7152, 0.0722);
            float sdrLuma = dot(linearize(sourceSDR.rgb), weights);
            float hdrLuma = dot(linearize(sourceHDR.rgb), weights);
            float gain = clamp(hdrLuma / max(sdrLuma, 0.002), 1.0, 16.0);
            // Avoid amplifying near-black decode noise or grain.
            gain = mix(1.0, gain, smoothstep(0.02, 0.18, sdrLuma));
            return vec4(encodeSRGB(linearize(film.rgb) * gain), film.a);
        }
        """
    )

    static func preservingHeadroom(film: CIImage, sourceSDR: CIImage, sourceHDR: CIImage) -> CIImage? {
        guard !film.extent.isEmpty, film.extent == sourceSDR.extent, sourceSDR.extent == sourceHDR.extent else { return nil }
        return headroomKernel?.apply(extent: film.extent, arguments: [film, sourceSDR, sourceHDR])
    }

    static func encode(
        _ image: CIImage, sourceData: Data, capturedAt: Date, recipe: FilmRecipe, settings: ProCaptureSettings
    ) -> Data? {
        guard settings.incompatibility == nil else { return nil }
        let hdr = settings.dynamicRange == .hdr
        let profile = hdr ? CGColorSpace.itur_2100_PQ
            : settings.colorGamut == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB
        guard let colorSpace = CGColorSpace(name: profile) else { return nil }
        let properties = PhotoOutputEncoder.exportProperties(
            width: Int(image.extent.width), height: Int(image.extent.height),
            sourceData: sourceData, capturedAt: capturedAt, recipe: recipe,
            profileName: hdr ? "ITU-R BT.2100 PQ" : settings.colorGamut == .displayP3 ? "Display P3" : PhotoOutputEncoder.outputProfileName,
            isSRGB: !hdr && settings.colorGamut == .sRGB
        )
        let tagged = image.settingProperties(properties)
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95
        ]
        if hdr {
            // A real 10-bit PQ representation, not an 8-bit JPEG with an HDR
            // label. Failure is returned, never silently downgraded to SDR.
            return try? context.heif10Representation(of: tagged, colorSpace: colorSpace, options: options)
        }
        if settings.format != .jpeg {
            return context.heifRepresentation(of: tagged, format: .RGBA8, colorSpace: colorSpace, options: options)
        }
        guard let image = context.createCGImage(tagged, from: tagged.extent, format: .RGBA8, colorSpace: colorSpace) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func framedSource(_ input: CIImage, viewportSize: CGSize, resolution: ProCaptureSettings.Resolution) -> CIImage {
        let scale = PhotoResolutionPolicy.outputScale(
            sourcePixels: Double(input.extent.width * input.extent.height), resolution: resolution
        )
        let sized = scale < 1 ? input.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]) : input
        let proposed = viewportSize.width > 0 && viewportSize.height > 0
            ? CameraFrameLayout.aspectFillCrop(sourceExtent: sized.extent, targetSize: viewportSize).intersection(sized.extent)
            : sized.extent
        let crop = CGRect(x: ceil(proposed.minX), y: ceil(proposed.minY),
                          width: max(1, floor(proposed.maxX) - ceil(proposed.minX)),
                          height: max(1, floor(proposed.maxY) - ceil(proposed.minY)))
        return sized.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }
}
