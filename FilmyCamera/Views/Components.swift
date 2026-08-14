import SwiftUI
import UIKit

enum FilmyTheme {
    static let background = Color(red: 0.027, green: 0.031, blue: 0.039)
    static let backgroundRaised = Color(red: 0.055, green: 0.062, blue: 0.075)
    static let panel = Color(red: 0.075, green: 0.083, blue: 0.098)
    static let panelRaised = Color(red: 0.13, green: 0.143, blue: 0.165)
    static let line = Color.white.opacity(0.12)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.62)
    // Keep small section labels above contrast-safe opacity on dark surfaces.
    static let tertiary = Color.white.opacity(0.56)
    static let accent = Color(red: 0.98, green: 0.73, blue: 0.28)
    static let accentWarm = Color(red: 1.0, green: 0.55, blue: 0.32)
    static let mint = Color(red: 0.47, green: 0.83, blue: 0.73)
    static let cornerRadius: CGFloat = 24
    static let controlRadius: CGFloat = 14
    static let actionPlateRadius: CGFloat = 28
    static let minimumHitTarget: CGFloat = 44

    static let titleFont = Font.system(.title2, design: .rounded).weight(.bold)
    static let bodyFont = Font.system(.body, design: .rounded)
    static let metadataFont = Font.system(.caption, design: .monospaced).weight(.semibold)

    static let pageGradient = LinearGradient(
        colors: [backgroundRaised.opacity(0.84), background, background],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let plateGradient = LinearGradient(
        colors: [Color.white.opacity(0.13), Color.white.opacity(0.045)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct FilmyPageBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                FilmyTheme.pageGradient

                Circle()
                    .fill(FilmyTheme.accentWarm.opacity(0.075))
                    .frame(width: min(proxy.size.width * 0.9, 380))
                    .blur(radius: 70)
                    .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.38)

                Circle()
                    .fill(FilmyTheme.accent.opacity(0.045))
                    .frame(width: min(proxy.size.width * 0.76, 320))
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.48, y: proxy.size.height * 0.35)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(FilmyTheme.accent)

                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(FilmyTheme.primary)
            }

            Spacer(minLength: 12)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(FilmyTheme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(trailing ?? ""))
        .accessibilityAddTraits(.isHeader)
    }
}

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
            .background(
                FilmyTheme.plateGradient,
                in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
            )
            .background(FilmyTheme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                    .stroke(FilmyTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
    }
}

struct FilmyIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isProminent ? FilmyTheme.background : FilmyTheme.primary)
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .background(
                    isProminent ? FilmyTheme.accent : Color.black.opacity(0.38),
                    in: Circle()
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(isProminent ? 0 : 0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isProminent ? FilmyTheme.background : FilmyTheme.primary)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .padding(.horizontal, 6)
            .background(
                isProminent ? FilmyTheme.accent : Color.black.opacity(0.32),
                in: RoundedRectangle(cornerRadius: FilmyTheme.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FilmyTheme.controlRadius, style: .continuous)
                    .stroke(Color.white.opacity(isProminent ? 0 : 0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                .background(Color.black.opacity(0.46), in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
        }
        .buttonStyle(.plain)
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

            Text(condensedMessage)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(FilmyTheme.primary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: FilmyTheme.minimumHitTarget)
        .background(Color.black.opacity(0.42), in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera status")
        .accessibilityValue(accessibilityStatus)
    }

    private var condensedMessage: String {
        switch availability {
        case .simulator:
            return "Preview only"
        case .permissionDenied:
            return "Access off"
        case .requestingPermission:
            return "Access needed"
        case .interrupted, .needsRecovery, .unavailable:
            return "Unavailable"
        case .paused:
            return "Paused"
        case .idle, .starting:
            return "Starting"
        case .running:
            return isLive ? "Live" : "Starting"
        }
    }

    private var accessibilityStatus: String {
        if isLive {
            return "Live preview"
        }

        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return condensedMessage }
        return "\(condensedMessage). \(detail)"
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
            HStack(spacing: 5) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .black))
                Text("\(value, specifier: "%.1f")×")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .background(Color.black.opacity(0.46), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
        }
        .accessibilityElement()
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(value, specifier: "%.1f") times")
        .accessibilityHint("Choose a quick zoom, swipe up or down to adjust, or pinch the preview.")
        .accessibilityAdjustableAction { direction in
            onAdjust(direction)
        }
    }

    private func presetTitle(_ preset: CGFloat) -> String {
        String(format: "%.1f×", preset)
    }
}

struct ExposureControl: View {
    let value: Float
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    private var valueText: String {
        String(format: "EV %@%.1f", value >= 0 ? "+" : "−", abs(value))
    }

    private var accessibilityValueText: String {
        String(format: "%@%.1f EV", value >= 0 ? "plus " : "minus ", abs(value))
    }

    var body: some View {
        HStack(spacing: 2) {
            adjustmentButton(
                systemName: "minus",
                direction: .decrement
            )

            Text(valueText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 46)

            adjustmentButton(
                systemName: "plus",
                direction: .increment
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.46), in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
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
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.86))
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
                isLocked ? "Locked" : "Lock",
                systemImage: isLocked ? "lock.fill" : "lock.open"
            )
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(isLocked ? FilmyTheme.background : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .background(isLocked ? FilmyTheme.accent : Color.black.opacity(0.46), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(isLocked ? 0 : 0.16), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? "Unlock focus and exposure" : "Lock focus and exposure")
        .accessibilityHint("Keeps focus and exposure at the selected point")
    }
}

struct RecipeSwatch: View {
    let recipe: FilmRecipe
    var isSelected = false
    var compact = false
    var showsLabel = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var thumbnailData: Data?

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
            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottomLeading) {
            if showsLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font((compact ? Font.caption : Font.subheadline).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.72 : 0.84)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)

                    if !compact {
                        Text(recipe.descriptor)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                    }
                }
                .padding(compact ? 10 : 12)
                .background(
                    Color.black.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                .stroke(isSelected ? FilmyTheme.accent : Color.white.opacity(0.14), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: isSelected ? FilmyTheme.accent.opacity(0.22) : .clear, radius: 12, y: 5)
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

struct CaptureButton: View {
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(FilmyTheme.accent.opacity(0.72), lineWidth: 1)
                    .frame(width: 92, height: 92)

                Circle()
                    .fill(.white)
                    .frame(width: 78, height: 78)

                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: 2)
                    .frame(width: 66, height: 66)

                if isCapturing {
                    ProgressView()
                        .tint(FilmyTheme.background)
                } else {
                    Circle()
                        .fill(FilmyTheme.background)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .accessibilityLabel(isCapturing ? "Saving photo" : "Capture photo")
        .accessibilityHint("Captures the current frame using the selected recipe")
    }
}

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
            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.7, dash: [4, 6]))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FocusReticle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(0.62), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .frame(width: 72, height: 72)
            .overlay(alignment: .topLeading) {
                Circle().fill(FilmyTheme.accent).frame(width: 5, height: 5).offset(x: -2, y: -2)
            }
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
        case .error: Color(red: 1, green: 0.45, blue: 0.4)
        case .info: FilmyTheme.accent
        }
    }

    private var tintOpacity: Double {
        style == .error ? 0.16 : 0.08
    }

    private var borderOpacity: Double {
        style == .error ? 0.72 : 0.42
    }

    private var borderWidth: CGFloat {
        style == .error ? 1.5 : 1
    }

    private var accessibilityLabel: String {
        "\(style.accessibilityTitle): \(message)"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FilmyTheme.primary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().fill(symbolColor.opacity(tintOpacity)) }
        .overlay { Capsule().stroke(symbolColor.opacity(borderOpacity), lineWidth: borderWidth) }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct EmptyStateCard: View {
    let systemName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(FilmyTheme.accent.opacity(0.12), in: Circle())

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)

                    Text(message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(FilmyTheme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.accent, in: Capsule())
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
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(width: 34, height: 34)
                .background(FilmyTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FilmyTheme.primary)
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
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
        ZStack {
            LinearGradient(
                colors: recipe.previewColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.black.opacity(0.46))

            VStack(spacing: 14) {
                Image(systemName: isSimulator ? "iphone.gen3" : "camera.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 58, height: 58)
                    .background(.white.opacity(0.12), in: Circle())

                VStack(spacing: 5) {
                    Text(isSimulator ? "Preview mode" : "Camera unavailable")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(message ?? (isSimulator ? "Shoot this look on an iPhone." : "Check camera access in Settings, then try again."))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.accent, in: Capsule())
                        .accessibilityIdentifier(actionTitle == "Open Settings" ? "camera-permission-action" : "camera-recovery-action")
                        .accessibilityHint(actionTitle == "Open Settings" ? "Opens Filmy Camera permissions" : "Attempts to resume the camera")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            // Keep the explanation above the camera action plate so the
            // unavailable state remains readable on short iPhone displays.
            .offset(y: -128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
