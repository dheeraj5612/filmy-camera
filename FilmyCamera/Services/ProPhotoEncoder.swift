import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// The legacy renderer is calibrated in gamma-encoded sRGB. Use its extended
/// counterpart, not a linear working space that would change every film LUT.
/// Half-float intermediates keep P3 colors and highlight values until encoding.
enum ProPhotoEncoder {
    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedSRGB)!,
        .workingFormat: CIFormat.RGBAh,
        .outputColorSpace: colorSpace,
        .cacheIntermediates: false
    ])

    // Evaluate the gain in linear light, while leaving the look's calibrated
    // gamma-domain graph intact. Signed transfer functions retain wide-gamut
    // colors that lie outside the unit sRGB cube. No gain is invented for SDR.
    private static let highlightKernel = CIColorKernel(source: """
        vec3 linearize(vec3 c) {
            vec3 a = abs(c);
            return sign(c) * mix(a / 12.92, pow((a + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), a));
        }
        vec3 encode(vec3 c) {
            vec3 a = abs(c);
            return sign(c) * mix(a * 12.92, 1.055 * pow(a, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), a));
        }
        kernel vec4 filmyHighlights(__sample look, __sample sdr, __sample hdr, float headroom) {
            vec3 weights = vec3(0.2126, 0.7152, 0.0722);
            float reference = max(dot(linearize(sdr.rgb), weights), 0.001);
            float gain = clamp(dot(linearize(hdr.rgb), weights) / reference, 1.0, headroom);
            return vec4(encode(linearize(look.rgb) * gain), look.a);
        }
        """
    )

    static func sized(_ image: CIImage, resolution: ProCaptureOptions.Resolution) -> CIImage {
        let scale = ProCapturePolicy.outputScale(width: image.extent.width, height: image.extent.height, resolution: resolution)
        guard scale < 0.9999 else { return image }
        let resized = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        // Fractional extents can cause a one-pixel encoder disagreement.
        return resized.cropped(to: CGRect(x: 0, y: 0, width: floor(resized.extent.width), height: floor(resized.extent.height)))
    }

    static func heifData(image: CIImage, sourceSDR: CIImage, sourceHDR: CIImage?, sourceData: Data,
                         recipe: FilmRecipe, capturedAt: Date, options: ProCaptureOptions) -> Data? {
        let primary = sized(image, resolution: options.resolution)
        var exif = PhotoOutputEncoder.captureExif(from: sourceData)
        exif[kCGImagePropertyExifPixelXDimension as String] = Int(primary.extent.width)
        exif[kCGImagePropertyExifPixelYDimension as String] = Int(primary.extent.height)
        // EXIF 65535 means the ICC profile, not an sRGB declaration, defines the color space.
        exif[kCGImagePropertyExifColorSpace as String] = 65535
        if let comment = PhotoOutputEncoder.provenanceJSON(for: recipe,
            appVersion: PhotoOutputEncoder.currentApplicationVersion, appBuild: PhotoOutputEncoder.currentApplicationBuild) {
            exif[kCGImagePropertyExifUserComment as String] = comment
        }
        let properties: [String: Any] = [
            kCGImagePropertyOrientation as String: 1,
            kCGImagePropertyExifDictionary as String: exif,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFSoftware as String: "Filmy Camera",
                kCGImagePropertyTIFFImageDescription as String: recipe.name
            ]
        ]
        let output = primary.settingProperties(properties)
        var encoding: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95
        ]
        if #available(iOS 18.0, *), options.hdr, let sourceHDR, sourceHDR.contentHeadroom > 1.01,
           let kernel = highlightKernel,
           let hdr = kernel.apply(extent: primary.extent, arguments: [primary,
               sized(sourceSDR, resolution: options.resolution), sized(sourceHDR, resolution: options.resolution),
               min(sourceHDR.contentHeadroom, 16)]) {
            // Core Image generates a new gain map from the ACTUALLY EDITED
            // SDR/HDR pair. Reusing the camera's original map would be wrong
            // after cropping, tone changes, grain or print composition.
            encoding[.hdrImage] = hdr.settingProperties(properties)
        }
        return context.heifRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace, options: encoding)
    }

    static func containsHDRGainMap(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
    }

    static func fileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else { return "jpg" }
        return UTType(type as String)?.preferredFilenameExtension ?? "jpg"
    }
}
