@preconcurrency import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct CaptureModesPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let enabled: Bool
    let focus: (CGPoint) -> Void
    let hardware: (Int) -> Void

    func makeUIView(context: Context) -> ModesPreviewView {
        let view = ModesPreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        view.focus = focus
        view.hardware = hardware
        view.configureHardwareEvents()
        return view
    }

    func updateUIView(_ view: ModesPreviewView, context: Context) {
        view.focus = focus
        view.hardware = hardware
        view.captureEnabled = enabled
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: ModesPreviewView, coordinator: ()) {
        view.captureEnabled = false
        view.preview.session = nil
    }
}

@MainActor
final class ModesPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var focus: (CGPoint) -> Void = { _ in }
    var hardware: (Int) -> Void = { _ in }
    private var captureInteraction: UIInteraction?
    var captureEnabled = false {
        didSet {
            if #available(iOS 17.2, *), let interaction = captureInteraction as? AVCaptureEventInteraction {
                interaction.isEnabled = captureEnabled
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        isAccessibilityElement = true
        accessibilityLabel = "Camera preview"
        accessibilityHint = "The reference is a guide only and is not included in the capture."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard captureEnabled else { return }
        let point = preview.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self))
        focus(point)
    }

    func configureHardwareEvents() {
        guard #available(iOS 17.2, *) else { return }
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard let self, captureEnabled else { return }
            switch event.phase {
            case .began: hardware(0)
            case .ended: hardware(1)
            case .cancelled: hardware(2)
            @unknown default: break
            }
        }
        interaction.isEnabled = false
        addInteraction(interaction)
        captureInteraction = interaction
    }
}

/// A single touch recognizer owns tap vs. hold. SwiftUI Button + simultaneous
/// long-press can produce an extra shutter on release, so this control avoids that race.
struct CaptureModesShutter: UIViewRepresentable {
    let enabled: Bool
    let canHold: Bool
    let isRecording: Bool
    let label: String
    let tap: () -> Void
    let beginHold: () -> Void
    let endHold: () -> Void

    func makeUIView(context: Context) -> ModesShutterControl { ModesShutterControl() }
    func updateUIView(_ view: ModesShutterControl, context: Context) {
        view.isEnabled = enabled
        view.canHold = canHold
        view.recording = isRecording
        view.tap = tap
        view.beginHold = beginHold
        view.endHold = endHold
        view.accessibilityLabel = label
        view.accessibilityIdentifier = "capture-modes-shutter"
        view.setNeedsLayout()
    }
    static func dismantleUIView(_ view: ModesShutterControl, coordinator: ()) { view.cancelTouch() }
}

@MainActor
final class ModesShutterControl: UIControl {
    var canHold = false
    var recording = false
    var tap: () -> Void = {}
    var beginHold: () -> Void = {}
    var endHold: () -> Void = {}
    private var holdTimer: Timer?
    private var held = false
    private let innerDisc = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Tap to start or stop. In Burst mode, hold to capture and release to finish."
        innerDisc.isUserInteractionEnabled = false
        addSubview(innerDisc)
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        innerDisc.frame = bounds.insetBy(dx: recording ? 22 : 7, dy: recording ? 22 : 7)
        innerDisc.layer.cornerRadius = recording ? 7 : innerDisc.bounds.width / 2
        innerDisc.backgroundColor = recording ? .systemRed : .white
        alpha = isEnabled ? 1 : 0.35
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        held = false
        if canHold {
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, isTracking, isEnabled else { return }
                    held = true
                    beginHold()
                }
            }
        }
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !bounds.insetBy(dx: -35, dy: -35).contains(touch.location(in: self)) { cancelTouch(); return false }
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        holdTimer?.invalidate(); holdTimer = nil
        if held { held = false; endHold() }
        else if isEnabled { tap() }
    }
    override func cancelTracking(with event: UIEvent?) { cancelTouch() }
    func cancelTouch() {
        holdTimer?.invalidate(); holdTimer = nil
        if held { held = false; endHold() }
    }
    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        tap()
        return true
    }
}
