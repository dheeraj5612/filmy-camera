@preconcurrency import CoreImage
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

/// Signal Frame. Neutral surfaces keep photographic judgment independent of
/// the identity. Vivid accents identify actions, never color the photographs.
/// Color is never the only indication of selection or an actionable state.
enum FilmyTheme {
    // Surfaces
    static let background = Color(white: 0.035)
    static let backgroundRaised = Color(white: 0.065)
    static let panel = Color(white: 0.105)
    static let panelRaised = Color(white: 0.155)
    static let line = Color.white.opacity(0.12)
    static let lineStrong = Color.white.opacity(0.24)

    // Ink
    static let primary = Color(white: 0.96)
    static let secondary = Color(white: 0.76)
    // Opaque neutral ink stays legible on all semantic surfaces.
    static let tertiary = Color(white: 0.65)

    // Signal colors
    #if G7_APP
    static let accent = Color(red: 0.388, green: 1.0, blue: 0.604) // #63FF9A
    static let comparison = Color(red: 0.388, green: 1.0, blue: 0.604)
    static let accentWarm = Color(red: 0.388, green: 1.0, blue: 0.604)
    static let filmAccent = Color(red: 0.839, green: 1.0, blue: 0.886) // #D6FFE2
    static let mint = Color(red: 0.839, green: 1.0, blue: 0.886)
    #else
    static let accent = Color(red: 1, green: 0.471, blue: 0.329)
    static let comparison = Color(red: 0.416, green: 0.863, blue: 1)
    static let accentWarm = Color(red: 1, green: 0.471, blue: 0.329)
    static let filmAccent = Color(red: 0.855, green: 0.953, blue: 0.396)
    static let mint = Color(red: 0.54, green: 0.92, blue: 0.69)
    #endif
    static let danger = Color(red: 1, green: 0.43, blue: 0.47)

    // Chrome that floats over the live viewfinder
    static let chromeFill = Color.black.opacity(0.76)
    static let chromeStroke = Color.white.opacity(0.24)
    /// The letterbox bands around the viewfinder. Pure black, like a camera
    /// body, so the frame reads as the only picture on screen.
    static let viewfinderBand = Color.black
    // A restrained radius keeps the live frame camera-like while softening
    // the hard rectangular edge on the main camera screen.
    static let viewfinderCornerRadius: CGFloat = 14

    static let cornerRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
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
        colors: [background, background],
        startPoint: .top,
        endPoint: .bottom
    )

    static let plateGradient = LinearGradient(
        colors: [panel, panel],
        startPoint: .top,
        endPoint: .bottom
    )

    static let chromeGradient = LinearGradient(
        colors: [Color.clear, Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )

    static let navBarGradient = LinearGradient(
        colors: [panel, panel],
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
                .frame(minHeight: FilmyTheme.toolControlHeight)
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
            Spacer(minLength: 12)
            FilmyWordmark(compact: true)
                .accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(white: 0.08), in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1) }
        } else {
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

/// Pure interaction rules shared by camera, editor, and onboarding buttons.
/// Keep feedback outside layout so pressing a control never reflows its neighbors.
enum FilmyInteractionPolicy {
    static func pressScale(isPressed: Bool, isEnabled: Bool, reduceMotion: Bool, requestedScale: CGFloat) -> CGFloat {
        guard isPressed, isEnabled, !reduceMotion, requestedScale.isFinite else { return 1 }
        return min(1, max(0.85, requestedScale))
    }

    static func zoomPresets(minZoom: CGFloat, maxZoom: CGFloat) -> [CGFloat] {
        guard minZoom.isFinite, maxZoom.isFinite, minZoom > 0, maxZoom >= minZoom else { return [1] }
        let available: [CGFloat] = [0.5, 1, 2, 3, 5].filter { $0 >= minZoom && $0 <= maxZoom }
        // Some physical lenses expose a narrow range without a standard preset.
        // Never offer an out-of-range 1x action for those lenses.
        return available.isEmpty ? [minZoom] : available
    }
}

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(FilmyInteractionPolicy.pressScale(
                isPressed: configuration.isPressed, isEnabled: isEnabled, reduceMotion: reduceMotion, requestedScale: scale
            ))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.5)
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
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(FilmyInteractionPolicy.pressScale(
                isPressed: configuration.isPressed, isEnabled: isEnabled, reduceMotion: reduceMotion, requestedScale: 0.98
            ))
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
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(FilmyTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(FilmyInteractionPolicy.pressScale(
                isPressed: configuration.isPressed, isEnabled: isEnabled, reduceMotion: reduceMotion, requestedScale: 0.98
            ))
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
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FilmyTag: View {
    let text: String
    var tint: Color = FilmyTheme.accent
    var filled = true

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(filled ? FilmyTheme.background : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(filled ? tint : tint.opacity(0.14), in: Capsule())
    }
}

struct MetricLabel: View {
    let title: String
    let value: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var trailing: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 12))
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow, color: FilmyTheme.accent)
                Text(title)
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .tracking(-0.6)
                    .foregroundStyle(FilmyTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
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
    @Environment(\.colorSchemeContrast) private var contrast

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
                    .strokeBorder(contrast == .increased ? FilmyTheme.lineStrong : FilmyTheme.line, lineWidth: 1)
                    .allowsHitTesting(false)
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
            HStack(spacing: 4) {
                Image(systemName: mode.systemImageName)
                Text(mode.statusTitle)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .frame(
                minWidth: UIDevice.current.userInterfaceIdiom == .pad ? 64 : FilmyTheme.minimumHitTarget,
                minHeight: UIDevice.current.userInterfaceIdiom == .pad ? 64 : FilmyTheme.minimumHitTarget
            )
            .viewfinderCapsule(interactive: true)
        }
        .buttonStyle(.pressable)
        // Off remains a valid request while the hardware is temporarily
        // unavailable, so the user can always turn flash off. The camera
        // screen omits this control entirely for unsupported hardware.
        .disabled(availability == .unsupported)
        .opacity(isTemporarilyUnavailable ? 0.58 : 1)
        .accessibilityIdentifier("flash-control")
        .accessibilityLabel(isTemporarilyUnavailable ? "Flash temporarily unavailable" : "Flash")
        .accessibilityValue(mode.title)
        .accessibilityHint(
            isTemporarilyUnavailable
                ? "The flash is temporarily unavailable. Tap to turn it off, or try again after the camera cools down."
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

/// Camera-style zoom presets with equal, stable touch targets. The active
/// factor gains an outline and accent, not a different size. The capsule
/// sits over the bottom edge of the viewfinder while the camera is live.
struct ZoomPresetBar: View {
    let value: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let onSelect: (CGFloat) -> Void
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12

    private var targetSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 64 : FilmyTheme.toolControlHeight
    }

    static func presets(minZoom: CGFloat, maxZoom: CGFloat) -> [CGFloat] {
        FilmyInteractionPolicy.zoomPresets(minZoom: minZoom, maxZoom: maxZoom)
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
        ViewThatFits(in: .horizontal) {
            presetButtons.fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                presetButtons
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: targetSize)
        }
        .padding(4)
        .viewfinderCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("zoom-control")
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(value, specifier: "%.1f") times")
        .accessibilityHint("Swipe up or down to adjust, or use the preset actions.")
        .accessibilityAdjustableAction { direction in
            HapticFeedback.play(.controlStep)
            onAdjust(direction)
        }
        .accessibilityActions {
            ForEach(presets, id: \.self) { preset in
                Button("Set zoom to \(Self.zoomTitle(preset))") {
                    HapticFeedback.play(.controlStep)
                    onSelect(preset)
                }
            }
        }
    }

    private var presetButtons: some View {
        HStack(spacing: 0) {
            ForEach(presets, id: \.self) { preset in
                let isActive = preset == activePreset
                Button {
                    HapticFeedback.play(.controlStep)
                    onSelect(preset)
                } label: {
                    Text(isActive ? Self.zoomTitle(value) : Self.presetTitle(preset))
                        .font(.system(size: labelSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? FilmyTheme.accent : FilmyTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: targetSize - 8, height: targetSize - 8)
                        .background(Color.black.opacity(isActive ? 0.7 : 0.28), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(isActive ? FilmyTheme.accent : .clear, lineWidth: 1.5)
                                .allowsHitTesting(false)
                        }
                        .frame(width: targetSize, height: targetSize)
                        .contentShape(Rectangle())
                }
                // No scaling: the whole reserved target remains tappable.
                .buttonStyle(PressableButtonStyle(scale: 1))
                .accessibilityHidden(true)
                .accessibilityIdentifier("zoom-preset-\(Self.presetTitle(preset))")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: activePreset)
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
    let onReset: (() -> Void)?
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    init(value: Float, onReset: (() -> Void)? = nil, onAdjust: @escaping (AccessibilityAdjustmentDirection) -> Void) {
        self.value = value
        self.onReset = onReset
        self.onAdjust = onAdjust
    }

    private var valueText: String {
        String(format: "%@%.1f", value >= 0 ? "+" : "−", abs(value))
    }

    private var accessibilityValueText: String {
        String(format: "%@%.1f EV", value >= 0 ? "plus " : "minus ", abs(value))
    }

    var body: some View {
        HStack(spacing: 0) {
            adjustmentButton(systemName: "minus", direction: .decrement)

            Button {
                HapticFeedback.play(.controlStep)
                onReset?()
            } label: {
                VStack(spacing: 1) {
                    Text("EV")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(FilmyTheme.secondary)
                    Text(valueText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(value == 0 ? FilmyTheme.primary : FilmyTheme.accent)
                }
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onReset == nil)
            .accessibilityLabel("Reset exposure compensation")
            .accessibilityIdentifier("exposure-reset")

            adjustmentButton(systemName: "plus", direction: .increment)
        }
        .viewfinderCapsule(interactive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("exposure-control")
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Swipe up or down to adjust exposure compensation. Tap the value to reset to zero.")
        .accessibilityAction(named: "Reset exposure compensation") {
            HapticFeedback.play(.controlStep)
            onReset?()
        }
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
        .accessibilityValue(isLocked ? "Locked" : "Unlocked")
        .accessibilityAddTraits(isLocked ? .isSelected : [])
        .accessibilityHint(isLocked ? "Releases the focus and exposure lock" : "Keeps focus and exposure at the selected point")
    }
}

// MARK: - Recipe visuals

/// Every look uses the same bundled sample so comparisons stay consistent
/// while the camera's live viewfinder continues to update independently.
struct RecipeSwatch: View {
    let recipe: FilmRecipe
    var isSelected = false
    var compact = false
    var showsLabel = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var thumbnailImage: UIImage?
    @State private var thumbnailRecipe: FilmRecipe?
    @State private var thumbnailFailed = false

    private var cornerRadius: CGFloat {
        2
    }

    var body: some View {
        // Let the caller's tile bounds size the labels and border; an
        // aspect-filled image can otherwise expand them outside the tile.
        Color.clear.overlay {
            if thumbnailRecipe == recipe, let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
            } else {
                FilmyTheme.panel
                    .overlay {
                        if thumbnailFailed && thumbnailRecipe == recipe {
                            Image(systemName: "photo")
                                .foregroundStyle(FilmyTheme.tertiary)
                                .accessibilityLabel("Preview unavailable")
                        } else {
                            ProgressView().tint(FilmyTheme.secondary)
                                .accessibilityLabel("Loading look preview")
                        }
                    }
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
        .task(id: recipe, priority: .utility) {
            thumbnailImage = nil
            thumbnailRecipe = recipe
            thumbnailFailed = false
            // Reopening a cached collection should not blank every photograph
            // for the editor's debounce interval.
            if let cached = await RecipeSwatchRenderer.shared.cachedThumbnail(for: recipe) {
                guard !Task.isCancelled else { return }
                thumbnailImage = cached
                return
            }
            // Only uncached slider revisions wait. Cancellation still prevents
            // obsolete settings from queuing GPU work or replacing a newer tile.
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard !Task.isCancelled else { return }
            let renderedImage = await RecipeSwatchRenderer.shared.render(recipe: recipe)
            guard !Task.isCancelled else { return }
            thumbnailImage = renderedImage
            thumbnailFailed = renderedImage == nil
        }
    }
}

/// One swatch at a time can submit GPU work. Actor calls retain their SwiftUI
/// task's cancellation, so closed drawers and obsolete slider revisions
/// are discarded before they render, instead of launching N detached jobs.
actor RecipeSwatchRenderer {
    static let shared = RecipeSwatchRenderer()

    #if targetEnvironment(simulator)
    // The simulator's Metal/Core Image completion queue can fail under the
    // burst of thumbnail work created by accessibility traversal. Software
    // rendering is deterministic and remains bounded to 384 x 512 here.
    private let context = CIContext(options: FilmRenderer.testContextOptions)
    #else
    private let context = FilmRenderer.makeOutputContext()
    #endif

    private final class SampleKey: NSObject {
        let recipe: FilmRecipe
        init(_ recipe: FilmRecipe) { self.recipe = recipe }
        override var hash: Int { recipe.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            (object as? SampleKey)?.recipe == recipe
        }
    }

    private let sampleCache: NSCache<SampleKey, UIImage> = {
        let cache = NSCache<SampleKey, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    // Original generated demo art already owned by this repository. Prepare
    // one bounded 384 x 512 source off the main actor, then use the exact
    // production recipe pipeline. This never reads the user's Photos library.
    private lazy var sampleScene: CIImage? = {
        guard let original = UIImage(named: "LookPreviewCafe")?.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: 384, height: 512)
        let framed = CameraFrameLayout.aspectFill(CIImage(cgImage: original), in: bounds)
        guard let small = FilmRenderer.outputCGImage(framed, from: bounds, using: context) else { return nil }
        return CIImage(cgImage: small)
    }()

    func purgeCache() {
        sampleCache.removeAllObjects()
    }

    func cachedThumbnail(for recipe: FilmRecipe) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return sampleCache.object(forKey: SampleKey(recipe))
    }
    func render(recipe: FilmRecipe) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            let key = SampleKey(recipe)
            if let cached = sampleCache.object(forKey: key) { return cached }
            guard let sampleScene else { return FilmRenderer.thumbnail(for: recipe) }
            guard let image = FilmRenderer.previewThumbnail(for: recipe, over: sampleScene, using: context),
                  !Task.isCancelled else { return nil }
            let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
            sampleCache.setObject(image, forKey: key, cost: cost)
            return image
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
    let unavailableLabel: String
    let unavailableHint: String
    let action: () -> Void

    init(
        isCapturing: Bool,
        isEnabled: Bool = true,
        unavailableLabel: String = "Capture unavailable in Preview mode",
        unavailableHint: String = "Capture is available on a physical device",
        action: @escaping () -> Void
    ) {
        self.isCapturing = isCapturing
        self.isEnabled = isEnabled
        self.unavailableLabel = unavailableLabel
        self.unavailableHint = unavailableHint
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
                : (isEnabled ? "Capture photo" : unavailableLabel)
        )
        .accessibilityHint(
            isEnabled
                ? (isCapturing ? "Applying the selected recipe" : "Captures the current frame using the selected recipe")
                : unavailableHint
        )
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(FilmyInteractionPolicy.pressScale(
                isPressed: configuration.isPressed, isEnabled: isEnabled, reduceMotion: reduceMotion, requestedScale: 0.94
            ))
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .viewfinderChrome(
            RoundedRectangle(cornerRadius: 18, style: .continuous),
            fill: Color.black.opacity(style == .error ? 0.62 : 0.5)
        )
        .frame(maxWidth: 480)
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
        .padding(.horizontal, 16)
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
    var actionHint: String = ""

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
                        .accessibilityHint(actionHint)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(systemName: String, title: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.systemName = systemName
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    private var contentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            SettingIcon(systemName: systemName)
            contentLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                accessory
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct PermissionBadge: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        Label(title, systemImage: isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.caption2.weight(.bold))
            .foregroundStyle(isEnabled ? FilmyTheme.mint : FilmyTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .fixedSize(horizontal: false, vertical: true)
            .background((isEnabled ? FilmyTheme.mint : FilmyTheme.accent).opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
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
            if isSimulator {
                RecipeSwatch(recipe: recipe, compact: false, showsLabel: false)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityHidden(true)
                    .overlay(alignment: .topLeading) {
                        Label("Sample · not a live camera", systemImage: "photo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FilmyTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black, in: Capsule())
                            .padding(12)
                            .accessibilityHidden(false)
                            .accessibilityIdentifier("camera-demo-label")
                    }
            } else {
                FilmyTheme.background
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(FilmyTheme.secondary)
                        .accessibilityHidden(true)
                    Text(actionTitle == nil ? "Connecting camera" : "Camera unavailable")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                    Text(message ?? "Allow camera access in Settings. You can still import a photo from the top bar.")
                        .font(.subheadline)
                        .foregroundStyle(FilmyTheme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.filmyPrimary)
                            .accessibilityIdentifier(actionTitle == "Open Settings" ? "camera-permission-action" : "camera-recovery-action")
                            .accessibilityHint(actionTitle == "Open Settings" ? "Opens Filmy Camera permissions" : "Attempts to resume the camera")
                    } else {
                        ProgressView().tint(FilmyTheme.accent)
                    }
                }
                .padding(20)
                .frame(maxWidth: 340)
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
