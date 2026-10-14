import CoreGraphics

/// Preview-space geometry is deliberately separate from AVFoundation's sensor
/// coordinates. CameraScreen applies the same crop/rotation/mirror transform
/// as tap-to-focus before delivering a tracked point to CameraService.
enum FocusAssistGeometry {
    static func seed(at point: CGPoint) -> CGRect {
        let x = point.x.isFinite ? min(max(point.x, 0), 1) : 0.5
        let y = point.y.isFinite ? min(max(point.y, 0), 1) : 0.5
        return CGRect(x: min(max(x - 0.09, 0), 0.82), y: min(max(1 - y - 0.09, 0), 0.82), width: 0.18, height: 0.18)
    }
    static func displayPoint(_ visionBox: CGRect) -> CGPoint {
        CGPoint(x: visionBox.midX, y: 1 - visionBox.midY)
    }
    static func displayRect(_ visionBox: CGRect, size: CGSize) -> CGRect {
        CGRect(x: visionBox.minX * size.width, y: (1 - visionBox.maxY) * size.height,
               width: visionBox.width * size.width, height: visionBox.height * size.height)
    }
}
