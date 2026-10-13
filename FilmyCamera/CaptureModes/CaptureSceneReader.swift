import Foundation
import ImageIO
import Vision

/// User-initiated local recognition, not Apple's private Visual Intelligence service.
/// Text and QR payloads are untrusted data; the UI never executes or opens them automatically.
enum CaptureSceneReader {
    static func read(_ data: Data) throws -> CaptureSceneAnalysis {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048
              ] as CFDictionary) else { throw CaptureModesError.invalidImage }
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        let codes = VNDetectBarcodesRequest()
        let classify = VNClassifyImageRequest()
        try VNImageRequestHandler(cgImage: image).perform([text, codes, classify])
        try Task.checkCancellation()
        let recognized = (text.results ?? []).compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
            return candidate.string
        }.joined(separator: "\n")
        let payloads = Array(Set((codes.results ?? []).compactMap(\.payloadStringValue))).sorted()
        let labels = (classify.results ?? []).filter { $0.confidence >= 0.2 }.prefix(5)
            .map { "\($0.identifier.replacingOccurrences(of: "_", with: " ")) (\(Int($0.confidence * 100))%)" }
        return CaptureSceneAnalysis(text: recognized, codes: payloads, labels: labels)
    }
}
