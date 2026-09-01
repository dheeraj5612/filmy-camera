import SwiftUI
import UIKit

// MARK: - Design tokens

/// The visual system for Filmy Camera. Surfaces are near-black with a faint
/// warm cast, ink is a soft warm white, and a single amber accent carries the
/// "halation" character of film without decorating the viewfinder.
enum FilmyTheme {
    // Surfaces
    static let background = Color(red: 0.043, green: 0.039, blue: 0.035)
    static let backgroundRaised = Color(red: 0.078, green: 0.071, blue: 0.063)
    static let panel = Color(red: 0.102, green: 0.094, blue: 0.082)
    static let panelRaised = Color(red: 0.148, green: 0.136, blue: 0.118)
    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.14)

    // Ink
    static let primary = Color(red: 0.97, green: 0.955, blue: 0.93)
    static let secondary = Color(red: 0.97, green: 0.955, blue: 0.93).opacity(0.64)
    // 0.56 keeps 10-11pt supporting text above 4.5:1 on both background and panel.
    static let tertiary = Color(red: 0.97, green: 0.955, blue: 0.93).opacity(0.56)

    // Signal colors
    static let accent = Color(red: 0.96, green: 0.73, blue: 0.30)
    static let accentWarm = Color(red: 0.95, green: 0.49, blue: 0.36)
    static let mint = Color(red: 0.47, green: 0.86, blue: 0.66)
    static let danger = Color(red: 1.0, green: 0.44, blue: 0.40)

    // Chrome that floats over the live viewfinder
    static let chromeFill = Color.black.opacity(0.42)
    static let chromeStroke = Color.white.opacity(0.13)

    static let cornerRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let actionPlateRadius: CGFloat = 24
    static let minimumHitTarget: CGFloat = 44
    static let pageMargin: CGFloat = 20

    static let titleFont = Font.system(.title2, design: .default).weight(.bold)
    static let bodyFont = Font.system(.body, design: .default)
    static let metadataFont = Font.system(.caption, design: .rounded).weight(.semibold)

    static let pageGradient = LinearGradient(
        colors: [backgroundRaised, background, background],
        startPoint: .top,
        endPoint: .bottom
    )

    static let plateGradient = LinearGradient(
        colors: [panelRaised, panel],
        startPoint: .top,
        endPoint: .bottom
    )

    static let chromeGradient = LinearGradient(
        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let navBarGradient = LinearGradient(
        colors: [panelRaised.opacity(0.98), panel.opacity(0.98)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Backgrounds and chrome

struct FilmyPageBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            FilmyTheme.pageGradient

            RadialGradient(
                colors: [FilmyTheme.accent.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Frosted, darkened chrome for controls that sit over the live preview.
struct ViewfinderChromeModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(FilmyTheme.chromeStroke, lineWidth: 1)
            }
    }
}

extension View {
    func viewfinderChrome<S: InsettableShape>(
        _ shape: S,
        fill: Color = FilmyTheme.chromeFill
    ) -> some View {
        modifier(ViewfinderChromeModifier(shape: shape, fill: fill))
    }

    func viewfinderCapsule(fill: Color = FilmyTheme.chromeFill) -> some View {
        viewfinderChrome(Capsule(), fill: fill)
    }
}

/// Frosted circle or capsule used behind icon-only viewfinder buttons.
struct ChromeShapeBackground<S: InsettableShape>: View {
    let shape: S
    var fillColor: Color = FilmyTheme.chromeFill

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(fillColor) }
            .overlay { shape.strokeBorder(FilmyTheme.chromeStroke, lineWidth: 1) }
    }
}

// MARK: - Button styles

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

struct FilmyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(FilmyTheme.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

struct FilmySecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(FilmyTheme.panelRaised, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == FilmyPrimaryButtonStyle {
    static var filmyPrimary: FilmyPrimaryButtonStyle { FilmyPrimaryButtonStyle() }
}

extension ButtonStyle where Self == FilmySecondaryButtonStyle {
    static var filmySecondary: FilmySecondaryButtonStyle { FilmySecondaryButtonStyle() }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Typography helpers

/// Small tracked uppercase label used above titles and inside cards. Pass
/// already-uppercased copy so the rendered text and its accessibility label
/// stay identical.
struct Eyebrow: View {
    let text: String
    var color: Color = FilmyTheme.tertiary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

struct FilmyTag: View {
    let text: String
    var tint: Color = FilmyTheme.accent
    var filled = true

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(filled ? FilmyTheme.background : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(filled ? tint : tint.opacity(0.14), in: Capsule())
    }
}

struct MetricLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow, color: FilmyTheme.accent)

                Text(title)
                    .font(.system(.largeTitle, design: .default).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
            }

            Spacer(minLength: 12)

            if let trailing {
                Text(trailing)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(FilmyTheme.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(trailing ?? ""))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cards

struct GlassCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                    .strokeBorder(FilmyTheme.line, lineWidth: 1)
            }
    }
}

struct SettingIcon: View {
    let systemName: String
    var tint: Color = FilmyTheme.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Viewfinder controls

struct FilmyIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isProminent ? FilmyTheme.background : .white)
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .background {
                    if isProminent {
                        Circle().fill(FilmyTheme.accent)
                    } else {
                        ChromeShapeBackground(shape: Circle())
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct CameraActionButton: View {
    let systemName: String
    let title: String
    let accessibilityLabel: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isProminent ? FilmyTheme.background : .white)
                    .frame(width: 54, height: 54)
                    .background {
                        if isProminent {
                            Circle().fill(FilmyTheme.accent)
                        } else {
                            ChromeShapeBackground(shape: Circle())
                        }
                    }

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(minWidth: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FlashControl: View {
    let mode: CameraService.FlashMode
    let availability: CameraService.FlashAvailability
    let action: () -> Void

    private var isTemporarilyUnavailable: Bool {
        availability == .temporarilyUnavailable
    }

    var body: some View {
        Button(action: action) {
            Label(mode.title, systemImage: mode.systemImageName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(mode == .off ? .white : FilmyTheme.accent)
                .padding(.horizontal, 12)
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                .viewfinderCapsule()
        }
        .buttonStyle(.pressable)
        .disabled(isTemporarilyUnavailable)
        .opacity(isTemporarilyUnavailable ? 0.58 : 1)
        .accessibilityIdentifier("flash-control")
        .accessibilityLabel(isTemporarilyUnavailable ? "Flash temporarily unavailable" : "Flash")
        .accessibilityValue(mode.title)
        .accessibilityHint(
            isTemporarilyUnavailable
                ? "The flash is temporarily unavailable. Try again after the camera cools down."
                : "Cycles between flash off, automatic low-light flash, and flash on."
        )
    }
}

struct CameraStatusPill: View {
    let isRunning: Bool
    let availability: CameraService.Availability
    let message: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLive: Bool {
        // `isRunning` can briefly outlive a lifecycle transition. Availability
        // is the source of truth so Simulator and offline states never look
        // or sound like a live camera.
        availability == .running && isRunning
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isLive ? FilmyTheme.mint : FilmyTheme.accent)
                .frame(width: 7, height: 7)
                .shadow(color: (isLive ? FilmyTheme.mint : FilmyTheme.accent).opacity(0.8), radius: 4)

            Text(condensedMessage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.6)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .viewfinderCapsule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera status")
        .accessibilityValue(accessibilityStatus)
    }

    private var condensedMessage: String {
        switch availability {
        case .simulator:
            return "PREVIEW"
        case .permissionDenied:
            return "ACCESS OFF"
        case .requestingPermission:
            return "ACCESS NEEDED"
        case .interrupted, .needsRecovery, .unavailable:
            return "UNAVAILABLE"
        case .paused:
            return "PAUSED"
        case .idle, .starting:
            return "STARTING"
        case .running:
            return isLive ? "LIVE" : "STARTING"
        }
    }

    private var accessibilityStatus: String {
        if isLive {
            return "Live preview"
        }

        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return condensedMessage.capitalized }
        return "\(condensedMessage.capitalized). \(detail)"
    }
}

struct ZoomControl: View {
    let value: CGFloat
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void
    let onSelect: (CGFloat) -> Void

    private let zoomPresets: [CGFloat] = [0.5, 1, 2, 3, 5]

    var body: some View {
        Menu {
            Section("Quick zoom") {
                ForEach(zoomPresets, id: \.self) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        if abs(value - preset) < 0.05 {
                            Label(presetTitle(preset), systemImage: "checkmark")
                        } else {
                            Text(presetTitle(preset))
                        }
                    }
                }
            }

            Divider()

            Button("Zoom out", systemImage: "minus") {
                onAdjust(.decrement)
            }
            Button("Zoom in", systemImage: "plus") {
                onAdjust(.increment)
            }
        } label: {
            Text(Self.zoomTitle(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(FilmyTheme.accent)
                .frame(width: FilmyTheme.minimumHitTarget + 4, height: FilmyTheme.minimumHitTarget)
                .viewfinderCapsule()
        }
        .accessibilityElement()
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(value, specifier: "%.1f") times")
        .accessibilityHint("Choose a quick zoom, swipe up or down to adjust, or pinch the preview.")
        .accessibilityAdjustableAction { direction in
            onAdjust(direction)
        }
    }

    static func zoomTitle(_ value: CGFloat) -> String {
        let tenths = (value * 10).rounded() / 10
        if tenths == tenths.rounded() {
            return String(format: "%.0f×", tenths)
        }
        return String(format: "%.1f×", tenths)
    }

    private func presetTitle(_ preset: CGFloat) -> String {
        Self.zoomTitle(preset)
    }
}

struct ExposureControl: View {
    let value: Float
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    private var valueText: String {
        String(format: "%@%.1f", value >= 0 ? "+" : "−", abs(value))
    }

    private var accessibilityValueText: String {
        String(format: "%@%.1f EV", value >= 0 ? "plus " : "minus ", abs(value))
    }

    var body: some View {
        HStack(spacing: 0) {
            adjustmentButton(systemName: "minus", direction: .decrement)

            VStack(spacing: 1) {
                Text("EV")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.72))
                Text(valueText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? .white : FilmyTheme.accent)
            }
            .frame(minWidth: 40)

            adjustmentButton(systemName: "plus", direction: .increment)
        }
        .viewfinderCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("exposure-control")
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Swipe up or down to adjust exposure compensation.")
        .accessibilityAdjustableAction { direction in
            onAdjust(direction)
        }
    }

    private func adjustmentButton(
        systemName: String,
        direction: AccessibilityAdjustmentDirection
    ) -> some View {
        Button {
            onAdjust(direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

struct FocusLockControl: View {
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                isLocked ? "AE/AF Locked" : "AE/AF Lock",
                systemImage: isLocked ? "lock.fill" : "lock.open"
            )
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isLocked ? FilmyTheme.background : .white)
            .padding(.horizontal, 12)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .background {
                if isLocked {
                    Capsule().fill(FilmyTheme.accent)
                } else {
                    ChromeShapeBackground(shape: Capsule())
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(isLocked ? "Unlock focus and exposure" : "Lock focus and exposure")
        .accessibilityHint("Keeps focus and exposure at the selected point")
    }
}

// MARK: - Recipe visuals

struct RecipeSwatch: View {
    let recipe: FilmRecipe
    var isSelected = false
    var compact = false
    var showsLabel = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var thumbnailData: Data?

    private var cornerRadius: CGFloat {
        compact ? 12 : 16
    }

    var body: some View {
        ZStack {
            if let thumbnailData,
               let image = UIImage(data: thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: recipe.previewColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            if showsLabel {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font((compact ? Font.caption : (dynamicTypeSize.isAccessibilitySize ? Font.body : Font.subheadline)).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(compact ? 1 : (dynamicTypeSize.isAccessibilitySize ? 3 : 2))
                        .minimumScaleFactor(compact ? 0.6 : 0.78)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)

                    if !compact {
                        Text(recipe.descriptor)
                            .font((dynamicTypeSize.isAccessibilitySize ? Font.caption : Font.caption2).weight(.medium))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(compact ? 8 : 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? FilmyTheme.accent : Color.white.opacity(0.12),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .task(id: recipe) {
            thumbnailData = await Task.detached(priority: .utility) {
                FilmRenderer.thumbnail(for: recipe)?.pngData()
            }.value
        }
    }
}

struct RecipeEditorSectionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text(detail)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
            }

            Spacer(minLength: 12)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Shutter

struct CaptureButton: View {
    let isCapturing: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        isCapturing: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.isCapturing = isCapturing
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 3.5)
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Color.white)
                    .frame(width: isCapturing ? 58 : 66, height: isCapturing ? 58 : 66)

                if isCapturing {
                    ProgressView()
                        .tint(FilmyTheme.background)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(ShutterButtonStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .shadow(color: .black.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
        .disabled(isCapturing || !isEnabled)
        .accessibilityLabel(
            isCapturing
                ? "Saving photo"
                : (isEnabled ? "Capture photo" : "Capture unavailable in Preview mode")
        )
        .accessibilityHint(
            isEnabled
                ? "Captures the current frame using the selected recipe"
                : "Capture is available on a physical iPhone"
        )
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}

// MARK: - Viewfinder overlays

struct RuleOfThirdsGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                path.move(to: CGPoint(x: width / 3, y: 0))
                path.addLine(to: CGPoint(x: width / 3, y: height))
                path.move(to: CGPoint(x: width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: width * 2 / 3, y: height))
                path.move(to: CGPoint(x: 0, y: height / 3))
                path.addLine(to: CGPoint(x: width, y: height / 3))
                path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
            }
            .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FocusReticle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(FilmyTheme.accent, lineWidth: 1.5)
            .frame(width: 76, height: 76)
            .overlay {
                Circle()
                    .fill(FilmyTheme.accent)
                    .frame(width: 4, height: 4)
            }
            .shadow(color: .black.opacity(0.4), radius: 2)
            .accessibilityHidden(true)
    }
}

struct ToastView: View {
    let message: String
    let style: CameraViewModel.ToastStyle

    private var symbolName: String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch style {
        case .success: FilmyTheme.mint
        case .error: FilmyTheme.danger
        case .info: FilmyTheme.accent
        }
    }

    private var accessibilityLabel: String {
        "\(style.accessibilityTitle): \(message)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(symbolColor)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .viewfinderChrome(
            RoundedRectangle(cornerRadius: 18, style: .continuous),
            fill: Color.black.opacity(style == .error ? 0.62 : 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Empty and status surfaces

struct EmptyStateCard: View {
    let systemName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        GlassCard(padding: 22) {
            VStack(spacing: 16) {
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(width: 56, height: 56)
                    .background(FilmyTheme.accent.opacity(0.12), in: Circle())

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.filmyPrimary)
                        .accessibilityHint("Opens the relevant permission settings")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct SettingRow<Accessory: View>: View {
    let systemName: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    init(systemName: String, title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.systemName = systemName
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 13) {
            SettingIcon(systemName: systemName)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                Text(detail)
                    .font(.system(.caption, design: .default).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)
            accessory
        }
        .accessibilityElement(children: .contain)
    }
}

struct PermissionBadge: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isEnabled ? FilmyTheme.mint : FilmyTheme.accent)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
        }
        .foregroundStyle(isEnabled ? FilmyTheme.mint : FilmyTheme.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .fixedSize(horizontal: true, vertical: false)
        .background((isEnabled ? FilmyTheme.mint : FilmyTheme.accent).opacity(0.12), in: Capsule())
    }
}

struct PreviewPlaceholder: View {
    let isSimulator: Bool
    let recipe: FilmRecipe
    var message: String? = nil
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: recipe.previewColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Keep the simulator and unavailable-camera states visually useful
                // without presenting a synthetic image as live camera output. This
                // is the same renderer-backed scene used by the recipe rail, so a
                // user can still see how the selected look is meant to feel before
                // moving to a physical iPhone.
                if isSimulator {
                    RecipeSwatch(recipe: recipe, compact: false, showsLabel: false)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityHidden(true)
                }

                Color.black.opacity(isSimulator ? 0.42 : 0.56)

                VStack(spacing: 14) {
                    Image(systemName: isSimulator ? "iphone.gen3" : "camera.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.12), in: Circle())

                    VStack(spacing: 6) {
                        Text(isSimulator ? "Preview mode" : "Camera unavailable")
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(message ?? (isSimulator ? "Shoot this look on an iPhone." : "Check camera access in Settings, then try again."))
                            .font(.system(.subheadline, design: .default).weight(.medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.filmyPrimary)
                            .accessibilityIdentifier(actionTitle == "Open Settings" ? "camera-permission-action" : "camera-recovery-action")
                            .accessibilityHint(actionTitle == "Open Settings" ? "Opens Filmy Camera permissions" : "Attempts to resume the camera")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
                .frame(maxWidth: 340)
                .viewfinderChrome(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, max(proxy.safeAreaInsets.top + 76, 100))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
