import SwiftUI
import UIKit

/// Original cut-frame monogram. This is geometry, not an SF Symbol or a
/// bundled font. The icon generator uses the same normalized vertices.
struct FilmyFrameMark: Shape {
    func path(in rect: CGRect) -> Path {
        let vertices: [CGPoint] = [
            .init(x: 0.18, y: 0.14), .init(x: 0.86, y: 0.14),
            .init(x: 0.86, y: 0.34), .init(x: 0.40, y: 0.34),
            .init(x: 0.40, y: 0.45), .init(x: 0.73, y: 0.45),
            .init(x: 0.73, y: 0.65), .init(x: 0.40, y: 0.65),
            .init(x: 0.40, y: 0.84), .init(x: 0.18, y: 0.94)
        ]
        return Path { path in
            for (index, vertex) in vertices.enumerated() {
                let point = CGPoint(x: rect.minX + vertex.x * rect.width,
                                    y: rect.minY + vertex.y * rect.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

/// A hand-drawn monoline wordmark. Custom f crossbar and open m joins echo
/// the frame index without importing, shipping or impersonating a typeface.
struct FilmyWordmark: Shape {
    func path(in rect: CGRect) -> Path {
        var strokes = Path()
        strokes.move(to: CGPoint(x: 18, y: 59))
        strokes.addLine(to: CGPoint(x: 18, y: 21))
        strokes.addQuadCurve(to: CGPoint(x: 36, y: 9), control: CGPoint(x: 18, y: 6))
        strokes.move(to: CGPoint(x: 6, y: 29))
        strokes.addLine(to: CGPoint(x: 34, y: 29))
        strokes.move(to: CGPoint(x: 53, y: 29))
        strokes.addLine(to: CGPoint(x: 53, y: 59))
        strokes.move(to: CGPoint(x: 76, y: 9))
        strokes.addLine(to: CGPoint(x: 76, y: 59))
        strokes.move(to: CGPoint(x: 99, y: 59))
        strokes.addLine(to: CGPoint(x: 99, y: 29))
        strokes.move(to: CGPoint(x: 99, y: 37))
        strokes.addCurve(to: CGPoint(x: 124, y: 39),
                         control1: CGPoint(x: 106, y: 20), control2: CGPoint(x: 124, y: 23))
        strokes.addLine(to: CGPoint(x: 124, y: 59))
        strokes.move(to: CGPoint(x: 124, y: 37))
        strokes.addCurve(to: CGPoint(x: 150, y: 39),
                         control1: CGPoint(x: 132, y: 20), control2: CGPoint(x: 150, y: 23))
        strokes.addLine(to: CGPoint(x: 150, y: 59))
        strokes.move(to: CGPoint(x: 171, y: 29))
        strokes.addLine(to: CGPoint(x: 184, y: 57))
        strokes.move(to: CGPoint(x: 198, y: 29))
        strokes.addLine(to: CGPoint(x: 183, y: 65))
        strokes.addQuadCurve(to: CGPoint(x: 170, y: 77), control: CGPoint(x: 179, y: 77))
        var mark = strokes.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        mark.addEllipse(in: CGRect(x: 48.5, y: 6.5, width: 9, height: 9))
        return mark.applying(CGAffineTransform(scaleX: rect.width / 208, y: rect.height / 86)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

struct FilmyBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            FilmyFrameMark()
                .fill(FilmyTheme.accent)
                .frame(width: 20, height: 24)
            FilmyWordmark()
                .fill(FilmyTheme.primary)
                .frame(width: 72, height: 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filmy Camera")
    }
}

/// Compare never rewrites a look. It is intentionally a real Button rather
/// than a long-press-only affordance, so VoiceOver, Switch Control and agents
/// can operate it without timing-sensitive gestures.
struct OriginalPreviewButton: View {
    let isShowingOriginal: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 18, weight: .medium))
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Original").font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(isShowingOriginal ? FilmyTheme.background : FilmyTheme.primary)
            .frame(minWidth: 56, minHeight: 52)
            .background(isShowingOriginal ? FilmyTheme.accent : FilmyTheme.backgroundRaised,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("camera-compare-original")
        .accessibilityLabel("Original preview")
        .accessibilityValue(isShowingOriginal ? "Original" : "Look")
        .accessibilityHint("Compare without changing the look used for capture. Tap again to return to the look.")
        .accessibilityAddTraits(isShowingOriginal ? .isSelected : [])
    }
}

/// A relative EV drag lane, with explicit step buttons and a reset as equally
/// capable alternatives. CameraService remains authoritative for quantization
/// and each device's narrower hardware limits.
struct ExposureDragControl: View {
    let value: Float
    let onChange: (Float) -> Void
    @State private var startingValue: Float?
    @State private var lastSubmittedValue: Float?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            stepButton(symbol: "minus", amount: -1.0 / 3.0, label: "Decrease exposure")
            VStack(spacing: 5) {
                Text(String(format: "%+.1f EV", value))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(abs(value) < 0.05 ? FilmyTheme.primary : FilmyTheme.utility)
                HStack(alignment: .center, spacing: 5) {
                    ForEach(-6...6, id: \.self) { tick in
                        Rectangle()
                            .fill(abs(Float(tick) / 3 - value) < 0.16 ? FilmyTheme.utility : .white.opacity(0.45))
                            .frame(width: 2, height: tick == 0 ? 10 : (tick % 3 == 0 ? 7 : 4))
                    }
                }
            }
            .frame(minWidth: 108, minHeight: 48)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { drag in
                    guard isEnabled else { return }
                    if startingValue == nil {
                        startingValue = value
                        lastSubmittedValue = value
                    }
                    guard let startingValue else { return }
                    let proposed = Self.dragValue(startingAt: startingValue, translation: drag.translation.width)
                    // Do not enqueue one device configuration for every pixel.
                    guard proposed != lastSubmittedValue else { return }
                    lastSubmittedValue = proposed
                    HapticFeedback.play(.controlStep)
                    onChange(proposed)
                }
                .onEnded { _ in resetDrag() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Exposure")
            .accessibilityValue(String(format: "%+.1f EV", value))
            .accessibilityHint("Swipe up or down to adjust in one-third stops. A horizontal drag adjusts exposure visually.")
            .accessibilityIdentifier("exposure-control")
            .accessibilityAdjustableAction { direction in
                HapticFeedback.play(.controlStep)
                onChange(value + (direction == .increment ? 1.0 / 3.0 : -1.0 / 3.0))
            }
            .accessibilityAction(named: "Reset exposure") { onChange(0) }
            stepButton(symbol: "plus", amount: 1.0 / 3.0, label: "Increase exposure")
            if abs(value) > 0.05 {
                Button { onChange(0) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exposure-reset")
                .accessibilityLabel("Reset exposure")
            }
        }
        .foregroundStyle(FilmyTheme.primary)
        .viewfinderChrome(RoundedRectangle(cornerRadius: 10))
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { resetDrag() }
        }
        .onDisappear(perform: resetDrag)
    }

    private func resetDrag() {
        startingValue = nil
        lastSubmittedValue = nil
    }

    static func dragValue(startingAt value: Float, translation: CGFloat) -> Float {
        guard value.isFinite, translation.isFinite else { return 0 }
        let proposed = value + Float(translation / 36) / 3
        return (min(max(proposed, -2), 2) * 3).rounded() / 3
    }

    private func stepButton(symbol: String, amount: Float, label: String) -> some View {
        Button {
            HapticFeedback.play(.controlStep)
            onChange(value + amount)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(amount < 0 ? "exposure-decrease" : "exposure-increase")
    }
}

/// One aligned image plane, not two independently fitted thumbnails. This is
/// only used when the source and processed photo have the same aspect ratio.
/// Instant Print uses whole-image comparison because its border changes that
/// geometry. Nothing here touches export pixels.
struct PhotoComparisonView: View {
    let original: UIImage
    let look: UIImage
    @Binding var fraction: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Image(uiImage: look).resizable().scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                Image(uiImage: original).resizable().scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: proxy.size.width * fraction)
                    }
                Rectangle().fill(.white).frame(width: 1)
                    .offset(x: proxy.size.width * fraction)
                    .allowsHitTesting(false)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .frame(width: 52, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .position(x: min(max(proxy.size.width * fraction, 26), max(proxy.size.width - 26, 26)),
                              y: proxy.size.height / 2)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("comparison-image"))
                        .onChanged { value in
                            fraction = Self.clampedFraction(value.location.x / max(proxy.size.width, 1))
                        })
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("review-comparison-divider")
                    .accessibilityLabel("Original and look divider")
                    .accessibilityValue("\(Int(fraction * 100)) percent original")
                    .accessibilityHint("Swipe up to reveal more original, or down to reveal more of the look")
                    .accessibilityAdjustableAction { direction in
                        fraction = Self.clampedFraction(fraction + (direction == .increment ? 0.1 : -0.1))
                    }
                    .accessibilityAction(named: "Show all original") { fraction = 1 }
                    .accessibilityAction(named: "Show all look") { fraction = 0 }
            }
            .overlay(alignment: .top) {
                HStack {
                    if fraction > 0 { comparisonLabel("Original") }
                    Spacer()
                    if fraction < 1 { comparisonLabel("Look") }
                }
                .padding(10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .coordinateSpace(name: "comparison-image")
            .clipped()
        }
    }

    private func comparisonLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
    }

    static func clampedFraction(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    static func hasMatchingAspect(_ first: CGSize, _ second: CGSize) -> Bool {
        guard first.width.isFinite, first.height.isFinite, second.width.isFinite, second.height.isFinite,
              first.width > 0, first.height > 0, second.width > 0, second.height > 0 else { return false }
        return abs(first.width / first.height - second.width / second.height) < 0.005
    }
}
