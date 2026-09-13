import Foundation

/// The final presentation applied after a recipe has rendered.
enum PhotoFinish: String, CaseIterable, Codable, Sendable {
    /// Preserve the existing edge-to-edge photo output.
    case photo

    /// Place the unscaled photo on neutral-white instant-print paper.
    case instantPrint
}
