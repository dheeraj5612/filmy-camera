import SwiftUI
import UIKit

/// Semantic haptics. Every call site names an intent rather than a pattern so
/// the Settings toggle can silence all of them at once.
enum HapticFeedback {
    enum Event: Equatable, Sendable {
        case capture
        case selection
        case controlStep
        case focus
        case discard
        case success
        case warning
        case error
    }

    enum Pattern: Equatable, Sendable {
        case selection
        case lightImpact
        case mediumImpact
        case softImpact
        case success
        case warning
        case error
    }

    static func pattern(for event: Event) -> Pattern {
        switch event {
        case .capture: .mediumImpact
        case .selection, .controlStep: .selection
        case .focus: .lightImpact
        case .discard: .softImpact
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    @MainActor private static let selectionGenerator = UISelectionFeedbackGenerator()
    @MainActor private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    @MainActor private static let softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    @MainActor private static let notificationGenerator = UINotificationFeedbackGenerator()

    @MainActor
    static func play(_ event: Event) {
        guard isEnabled() else { return }

        switch pattern(for: event) {
        case .selection:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        case .lightImpact:
            lightImpactGenerator.prepare()
            lightImpactGenerator.impactOccurred(intensity: 0.72)
        case .mediumImpact:
            mediumImpactGenerator.prepare()
            mediumImpactGenerator.impactOccurred(intensity: 0.9)
        case .softImpact:
            softImpactGenerator.prepare()
            softImpactGenerator.impactOccurred(intensity: 0.7)
        case .success:
            notify(.success)
        case .warning:
            notify(.warning)
        case .error:
            notify(.error)
        }
    }

    @MainActor
    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }
}

// MARK: - Design tokens

/// A quiet camera body: neutral surfaces keep attention on the image.
/// Amber identifies compact digital looks; muted green identifies film.
enum FilmyTheme {
    // Surfaces
    static let background = Color(white: 0.035)
    static let backgroundRaised = Color(white: 0.065)
    static let panel = Color(white: 0.10)
    static let panelRaised = Color(white: 0.15)
    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.14)

    // Ink
    static let primary = Color(white: 0.96)
    static let secondary = Color(white: 0.96).opacity(0.64)
    // 0.56 keeps 10-11pt supporting text above 4.5:1 on both background and panel.
    static let tertiary = Color(white: 0.96).opacity(0.56)

    // Signal colors
    static let accent = Color(red: 0.96, green: 0.73, blue: 0.30)
    static let accentWarm = Color(red: 0.95, green: 0.49, blue: 0.36)
    static let filmAccent = Color(red: 0.64, green: 0.79, blue: 0.66)
    static let mint = Color(red: 0.47, green: 0.86, blue: 0.66)
    static let danger = Color(red: 1.0, green: 0.44, blue: 0.40)

    // Chrome that floats over the live viewfinder
    static let chromeFill = Color.black.opacity(0.42)
    static let chromeStroke = Color.white.opacity(0.13)
    /// The letterbox bands around the viewfinder. Pure black, like a camera
    /// body, so the frame reads as the only picture on screen.
    static let viewfinderBand = Color.black
    static let viewfinderCornerRadius: CGFloat = 10

    static let cornerRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let actionPlateRadius: CGFloat = 20
    static let minimumHitTarget: CGFloat = 44
    /// Tool-strip controls sit behind a presented sheet at times, where iOS
    /// scales the presenting view to about 92%. 48pt keeps their measured
    /// frame at or above the 44pt minimum in that state.
    static let toolControlHeight: CGFloat = 48
    static let pageMargin: CGFloat = 20

    static let titleFont = Font.system(.title2, design: .default).weight(.bold)
    static let bodyFont = Font.system(.body, design: .default)
    static let metadataFont = Font.system(.caption, design: .default).weight(.medium)

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

/// Width limits that keep pages readable on iPad without changing the
/// compact-width layouts.
enum FilmyLayout {
    static let readableMaxWidth: CGFloat = 760
    static let editorMaxWidth: CGFloat = 1_080
    static let dockMaxWidth: CGFloat = 620
    static let compactHorizontalMargin: CGFloat = 16
    static let regularHorizontalMargin: CGFloat = 28
}

struct BackToCameraButton: View {
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.play(.selection)
            action()
        } label: {
            Label("Camera", systemImage: "chevron.left")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .background(FilmyTheme.panel.opacity(0.94), in: Capsule())
                .overlay {
                    Capsule().stroke(FilmyTheme.lineStrong, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to camera")
        .accessibilityHint("Returns to the main camera")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Secondary destinations keep a one-tap return to shooting while scrolling.
struct CameraReturnBar: View {
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        HStack {
            BackToCameraButton(accessibilityIdentifier: accessibilityIdentifier, action: action)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FilmyTheme.pageMargin)
        .padding(.vertical, 6)
        .background(FilmyTheme.background)
    }
}

struct FilmyPageBackground: View {
    var body: some View {
        FilmyTheme.pageGradient
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Frosted, darkened chrome for controls that sit over the live preview.
/// On iOS 26 this is Liquid Glass; earlier systems get an ultra-thin material
/// with the same tint so both read as the same surface.
struct ViewfinderChromeModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    var interactive = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass: Glass {
        let tinted = Glass.regular.tint(fill)
        return interactive ? tinted.interactive() : tinted
    }
    #endif

    private func legacy(_ content: Content) -> some View {
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
        fill: Color = FilmyTheme.chromeFill,
        interactive: Bool = false
    ) -> some View {
        modifier(ViewfinderChromeModifier(shape: shape, fill: fill, interactive: interactive))
    }

    func viewfinderCapsule(fill: Color = FilmyTheme.chromeFill, interactive: Bool = false) -> some View {
        viewfinderChrome(Capsule(), fill: fill, interactive: interactive)
    }
}

/// Frosted circle or capsule used behind icon-only viewfinder buttons.
struct ChromeShapeBackground<S: InsettableShape>: View {
    let shape: S
    var fillColor: Color = FilmyTheme.chromeFill

    var body: some View {
        Color.clear
            .viewfinderChrome(shape, fill: fillColor, interactive: true)
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
            .font(.system(.headline, design: .default).weight(.semibold))
            .foregroundStyle(FilmyTheme.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .font(.system(.headline, design: .default).weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(FilmyTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .font(.system(size: 11, weight: .semibold, design: .default))
            .tracking(1.2)
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
            .font(.system(size: 10, weight: .bold, design: .default))
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

/// Icon-only circular action beside the shutter (Tune). Captions are left
/// off, as on every iPhone camera; the accessibility label carries the name.
struct CameraActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isProminent ? FilmyTheme.background : .white)
                .frame(width: 52, height: 52)
                .background {
                    if isProminent {
                        Circle().fill(FilmyTheme.accent)
                    } else {
                        ChromeShapeBackground(shape: Circle())
                    }
                }
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FlashControl: View {
    let mode: CameraService.FlashMode
    let availability: CameraService.FlashAvailability
    /// Icon-only in the top bar (the way every iPhone camera shows flash);
    /// labelled inside a control strip.
    var iconOnly = false
    let action: () -> Void

    private var isTemporarilyUnavailable: Bool {
        availability == .temporarilyUnavailable
    }

    private var tint: Color {
        mode == .off ? .white : FilmyTheme.accent
    }

    var body: some View {
        Button {
            HapticFeedback.play(.controlStep)
            action()
        } label: {
            if iconOnly {
                Image(systemName: mode.systemImageName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .background { ChromeShapeBackground(shape: Circle()) }
                    .contentShape(Circle())
            } else {
                Label(mode.title, systemImage: mode.systemImageName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.toolControlHeight)
                    .viewfinderCapsule(interactive: true)
            }
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
                .font(.system(size: 11, weight: .semibold, design: .default))
                .tracking(0.6)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 30)
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

/// Apple Camera-style zoom presets: a glass capsule of small circles, with
/// the active factor drawn larger and in the accent. It sits over the bottom
/// edge of the viewfinder while the camera is live.
struct ZoomPresetBar: View {
    let value: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let onSelect: (CGFloat) -> Void
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let candidates: [CGFloat] = [0.5, 1, 2, 3, 5]

    static func presets(minZoom: CGFloat, maxZoom: CGFloat) -> [CGFloat] {
        let available = candidates.filter { $0 >= minZoom - 0.01 && $0 <= maxZoom + 0.01 }
        return available.isEmpty ? [1] : available
    }

    private var presets: [CGFloat] {
        Self.presets(minZoom: minZoom, maxZoom: maxZoom)
    }

    /// The preset whose bubble shows the live factor: the nearest one at or
    /// below the current zoom, the way the system camera assigns a lens.
    private var activePreset: CGFloat? {
        presets.last(where: { $0 <= value + 0.02 }) ?? presets.first
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.self) { preset in
                let isActive = preset == activePreset
                Button {
                    HapticFeedback.play(.controlStep)
                    onSelect(preset)
                } label: {
                    Text(isActive ? Self.zoomTitle(value) : Self.presetTitle(preset))
                        .font(.system(size: isActive ? 12 : 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? FilmyTheme.accent : .white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: isActive ? 40 : 32, height: isActive ? 40 : 32)
                        .background {
                            Circle().fill(Color.black.opacity(isActive ? 0.62 : 0.28))
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityHidden(true)
            }
        }
        .padding(4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: activePreset)
        .viewfinderCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("zoom-control")
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(value, specifier: "%.1f") times")
        .accessibilityHint("Swipe up or down to adjust, or pinch the preview.")
        .accessibilityAdjustableAction { direction in
            HapticFeedback.play(.controlStep)
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

    static func presetTitle(_ preset: CGFloat) -> String {
        preset == preset.rounded() ? String(format: "%.0f", preset) : String(format: "%.1f", preset)
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
        .viewfinderCapsule(interactive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("exposure-control")
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Swipe up or down to adjust exposure compensation.")
        .accessibilityAdjustableAction { direction in
            HapticFeedback.play(.controlStep)
            onAdjust(direction)
        }
    }

    private func adjustmentButton(
        systemName: String,
        direction: AccessibilityAdjustmentDirection
    ) -> some View {
        Button {
            HapticFeedback.play(.controlStep)
            onAdjust(direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.toolControlHeight)
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
        Button {
            HapticFeedback.play(.selection)
            action()
        } label: {
            Label(
                isLocked ? "AE/AF Locked" : "AE/AF Lock",
                systemImage: isLocked ? "lock.fill" : "lock.open"
            )
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(isLocked ? FilmyTheme.background : .white)
            .padding(.horizontal, 12)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.toolControlHeight)
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
    @Environment(\.recipePreviewScene) private var previewScene
    @State private var thumbnailImage: UIImage?
    @State private var liveThumbnail: UIImage?

    private var cornerRadius: CGFloat {
        compact ? 12 : 12
    }

    private struct LiveKey: Equatable {
        let recipe: FilmRecipe
        let sceneVersion: Int?
    }

    private struct ThumbnailKey: Equatable {
        let recipe: FilmRecipe
        let hasLiveScene: Bool
    }

    var body: some View {
        ZStack {
            if let liveThumbnail {
                Image(uiImage: liveThumbnail)
                    .resizable()
                    .scaledToFill()
            } else if let thumbnailImage {
                Image(uiImage: thumbnailImage)
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
        .task(id: ThumbnailKey(recipe: recipe, hasLiveScene: previewScene != nil)) {
            // Clear a prior recipe's image immediately, so a slider change
            // never presents stale settings while the replacement is rendered.
            thumbnailImage = nil
            // A live scene is the useful source for swatches in the camera
            // rail. Skip the second synthetic render while it is available;
            // this keeps a recipe change from doing two full thumbnail passes.
            guard previewScene == nil else { return }
            // Editor sliders mutate the draft many times per second, and each
            // change re-runs this task. Debounce first so a drag cannot queue
            // one full renderer pass per tick; .task(id:) cancels the sleeping
            // predecessor whenever the recipe changes again.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let renderedImage = await Task.detached(priority: .utility) {
                FilmRenderer.thumbnail(for: recipe)
            }.value
            guard !Task.isCancelled else { return }
            thumbnailImage = renderedImage
        }
        // When the viewfinder is live, show this recipe applied to the actual
        // scene, refreshed at the snapshot store's cadence.
        .task(id: LiveKey(recipe: recipe, sceneVersion: previewScene?.version)) {
            guard let previewScene else {
                liveThumbnail = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let sceneBox = SceneBox(previewScene.image)
            let rendered = await Task.detached(priority: .utility) {
                FilmRenderer.previewThumbnail(for: recipe, over: sceneBox.image)
            }.value
            guard !Task.isCancelled else { return }
            if let rendered {
                liveThumbnail = rendered
            }
        }
    }
}

private final class SceneBox: @unchecked Sendable {
    let image: CIImage

    init(_ image: CIImage) {
        self.image = image
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
        Button {
            HapticFeedback.play(.capture)
            action()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 4)
                    .frame(width: 74, height: 74)

                Circle()
                    .fill(Color.white)
                    .frame(width: isCapturing ? 50 : 60, height: isCapturing ? 50 : 60)

                if isCapturing {
                    ProgressView()
                        .tint(FilmyTheme.background)
                }
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
        }
        .buttonStyle(ShutterButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(isCapturing || !isEnabled)
        .accessibilityLabel(
            isCapturing
                ? "Processing photo"
                : (isEnabled ? "Capture photo" : "Capture unavailable in Preview mode")
        )
        .accessibilityHint(
            isEnabled
                ? (isCapturing ? "Applying the selected recipe" : "Captures the current frame using the selected recipe")
                : "Capture is available on a physical device"
        )
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
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
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FocusReticle: View {
    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(FilmyTheme.accent, lineWidth: 1.2)
                .frame(width: 72, height: 72)

            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(FilmyTheme.accent)
                    .frame(width: 1.2, height: 7)
                    .offset(y: -36)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 2)
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
        HStack(alignment: .top, spacing: 13) {
            SettingIcon(systemName: systemName)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // Permission guidance can run several lines at accessibility
                // sizes; the screen scrolls, so let the detail wrap fully.
                Text(detail)
                    .font(.system(.caption, design: .default).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

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
            ZStack {
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
                        Text(message ?? (isSimulator ? "Shoot this look on an iPhone or iPad." : "Check camera access in Settings, then try again."))
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
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                // Centered inside the viewfinder; on short displays and at
                // accessibility text sizes the card scrolls instead of
                // pushing its recovery action out of reach.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .scrollableWhenTaller()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    /// Wraps the view in a vertical scroll view that only scrolls (and only
    /// bounces) once the content is taller than the space it is given.
    func scrollableWhenTaller() -> some View {
        ScrollView(showsIndicators: false) {
            self
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
