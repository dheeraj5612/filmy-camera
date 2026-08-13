import AVFoundation
import Photos
import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var photoLibrary: PhotoLibraryService

    private let privacyPolicyURL = URL(string: "https://dheeraj5612.github.io/filmycam-legal/privacy-policy.html")!
    private let supportURL = URL(string: "https://dheeraj5612.github.io/filmycam-legal/support.html")!

    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                    SectionHeading(eyebrow: "Control room", title: "Settings")

                    introCard
                    captureSettings
                    permissions
                    localCache
                    about
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(FilmyTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var introCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FilmyTheme.accent.opacity(0.16))
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(FilmyTheme.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("A slower way to see")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(FilmyTheme.primary)
                        Text("Tune the camera, keep the mood, and let every frame land exactly where you left it.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().overlay(FilmyTheme.line)

                HStack(spacing: 8) {
                    settingsBadge(systemName: "slider.horizontal.3", title: "CAPTURE")
                    settingsBadge(systemName: "lock.fill", title: "PRIVATE")
                    settingsBadge(systemName: "sparkles", title: "FILMY")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Capture, private, and film-inspired controls")
            }
        }
    }

    private func settingsBadge(systemName: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
        }
        .foregroundStyle(FilmyTheme.tertiary)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private var captureSettings: some View {
        settingsSection(
            eyebrow: "Camera feel",
            title: "Capture",
            systemName: "slider.horizontal.3",
            detail: "Small choices that stay out of your way while you shoot."
        ) {
            ControlRoomRow(
                systemName: "square.grid.3x3",
                title: "Framing grid",
                detail: "Keep a quiet rule-of-thirds guide over the preview."
            ) {
                Toggle("Framing grid", isOn: $showGrid)
                    .labelsHidden()
                    .tint(FilmyTheme.accent)
            }

            settingsDivider

            ControlRoomRow(
                systemName: "waveform.path.ecg",
                title: "Shutter feedback",
                detail: "Use a subtle haptic when a frame is captured."
            ) {
                Toggle("Shutter feedback", isOn: $hapticsEnabled)
                    .labelsHidden()
                    .tint(FilmyTheme.accent)
            }
        }
    }

    private var permissions: some View {
        settingsSection(
            eyebrow: "Permissions",
            title: "Access",
            systemName: "checkmark.shield",
            detail: "Filmy Camera only asks for the access needed to make and keep a frame."
        ) {
            ControlRoomRow(
                systemName: "camera.fill",
                title: "Camera",
                detail: cameraStatusDetail
            ) {
                PermissionBadge(
                    title: cameraStatusTitle,
                    isEnabled: cameraStatusIsEnabled
                )
            }

            if cameraPermissionNeedsSettings {
                settingsDivider
                settingsAction(
                    title: "Open System Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "camera-permission-settings",
                    hint: "Opens Filmy Camera camera permissions",
                    action: openSystemSettings
                )
            }

            if cameraPermissionNeedsRequest {
                settingsDivider
                settingsAction(
                    title: "Request Camera Access",
                    systemName: "camera.badge.ellipsis",
                    identifier: "camera-permission-request",
                    hint: "Shows the system camera permission prompt",
                    action: requestCameraAccess
                )
            }

            settingsDivider

            ControlRoomRow(
                systemName: "photo.on.rectangle",
                title: "Photos",
                detail: photoStatusDetail
            ) {
                PermissionBadge(
                    title: photoStatusTitle,
                    isEnabled: photoLibrary.authorizationStatus == .authorized || photoLibrary.authorizationStatus == .limited
                )
            }

            if photoLibrary.authorizationStatus == .denied || photoLibrary.authorizationStatus == .restricted {
                settingsDivider
                settingsAction(
                    title: "Open System Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "photos-permission-settings",
                    hint: "Opens Filmy Camera permissions",
                    action: openSystemSettings
                )
            } else if photoLibrary.authorizationStatus == .notDetermined {
                settingsDivider
                settingsAction(
                    title: "Allow Photos access",
                    systemName: "photo.badge.plus",
                    identifier: "photos-permission-action",
                    hint: "Requests Photos access for the Roll",
                    action: requestPhotoAccess
                )
            }
        }
    }

    private var localCache: some View {
        settingsSection(
            eyebrow: "On-device roll",
            title: "Offline cache",
            systemName: "externaldrive.fill",
            detail: "A private fallback keeps your finished frames close when Photos access is limited."
        ) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FilmyTheme.accent)
                        .accessibilityHidden(true)
                        .frame(width: 34, height: 34)
                        .background(FilmyTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Temporary frame cache")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(FilmyTheme.primary)
                            Spacer(minLength: 4)
                            Text("250 MB max")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(FilmyTheme.tertiary)
                        }

                        Text("Private, excluded from backup, and removable at any time.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsDivider

                Button {
                    guard photoLibrary.hasLocalCache else { return }
                    photoLibrary.clearLocalRollCache()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.bold))
                        Text("Clear local cache")
                            .font(.subheadline.weight(.bold))
                        Spacer(minLength: 8)
                        Text(photoLibrary.hasLocalCache ? "Available" : "Empty")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FilmyTheme.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .foregroundStyle(photoLibrary.hasLocalCache ? FilmyTheme.accent : FilmyTheme.tertiary)
                .buttonStyle(.plain)
                .disabled(!photoLibrary.hasLocalCache)
                .contentShape(Rectangle())
                .accessibilityIdentifier("clear-local-cache")
                .accessibilityValue(photoLibrary.hasLocalCache ? "Available" : "Empty")
                .accessibilityHint(photoLibrary.hasLocalCache ? "Removes temporary camera frames" : "There are no temporary camera frames to clear")
            }
        }
    }

    private var about: some View {
        settingsSection(
            eyebrow: "The fine print",
            title: "About",
            systemName: "info.circle",
            detail: "A little context about the camera and your frames."
        ) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Filmy Camera")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                    Spacer(minLength: 8)
                    Text("VERSION 1.0")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(FilmyTheme.accent)
                }

                Text("Recipe names are original, camera-inspired descriptions. Filmy Camera is an independent experience; it does not include camera firmware, proprietary LUTs, or calibration data.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FilmyTheme.mint)
                    Text("Your frames save to Photos; local copies are temporary and removable.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FilmyTheme.mint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .background(FilmyTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                settingsDivider

                VStack(spacing: 8) {
                    settingsLink(
                        title: "Privacy Policy",
                        systemName: "hand.raised.fill",
                        destination: privacyPolicyURL,
                        identifier: "privacy-policy-link"
                    )
                    settingsLink(
                        title: "Contact Support",
                        systemName: "questionmark.circle.fill",
                        destination: supportURL,
                        identifier: "support-link"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        eyebrow: String,
        title: String,
        systemName: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(FilmyTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(FilmyTheme.tertiary)
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassCard(padding: 15) {
                VStack(spacing: 0, content: content)
            }
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(FilmyTheme.line)
            .padding(.vertical, 12)
    }

    private func settingsAction(
        title: String,
        systemName: String,
        identifier: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .foregroundStyle(FilmyTheme.accent)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
        .accessibilityHint(hint)
    }

    private func settingsLink(
        title: String,
        systemName: String,
        destination: URL,
        identifier: String
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .foregroundStyle(FilmyTheme.accent)
        .accessibilityIdentifier(identifier)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var photoStatusTitle: String {
        switch photoLibrary.authorizationStatus {
        case .authorized: return "ALLOWED"
        case .limited: return "LIMITED"
        case .denied, .restricted: return "OFF"
        case .notDetermined: return "ASK"
        @unknown default: return "CHECK"
        }
    }

    private var cameraPermissionNeedsSettings: Bool {
        camera.availability == .permissionDenied
    }

    private var cameraPermissionNeedsRequest: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
            && camera.availability != .simulator
            && camera.availability != .requestingPermission
    }

    private var cameraStatusTitle: String {
        switch camera.availability {
        case .running: return "LIVE"
        case .simulator: return "SIMULATOR"
        case .permissionDenied: return "OFF"
        case .requestingPermission: return "ASKING"
        case .starting, .idle: return "ASK"
        case .paused: return "ALLOWED"
        case .interrupted, .needsRecovery, .unavailable: return "CHECK"
        }
    }

    private var cameraStatusIsEnabled: Bool {
        camera.availability == .running
    }

    private var cameraStatusDetail: String {
        switch camera.availability {
        case .running: return "Live preview is ready to capture."
        case .simulator: return "Simulator-safe preview mode"
        case .permissionDenied: return "Enable camera access in Settings to preview and capture."
        case .requestingPermission: return "Waiting for camera permission."
        case .starting, .idle: return "Ask when you are ready to capture."
        case .paused: return "Camera access is enabled; preview is paused."
        case .interrupted, .needsRecovery, .unavailable: return camera.statusMessage
        }
    }

    private var photoStatusDetail: String {
        switch photoLibrary.authorizationStatus {
        case .authorized: return "Read and save access is enabled."
        case .limited: return "Limited access is enabled for selected photos."
        case .denied, .restricted: return "Enable Photos access to save and view your roll."
        case .notDetermined: return "Ask when you are ready to build your roll."
        @unknown default: return "Photo access status is unavailable."
        }
    }

    private func requestPhotoAccess() {
        Task { _ = await photoLibrary.requestAccessIfNeeded() }
    }

    private func requestCameraAccess() {
        guard camera.availability != .simulator,
              AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            return
        }

        let cameraService = camera

        // Settings owns no camera preview. Request the authorization directly
        // so approving this action cannot leave an off-screen capture session
        // running after the user stays on Settings or moves to another tab.
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor [cameraService] in
                cameraService.stop()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct ControlRoomRow<Accessory: View>: View {
    let systemName: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    init(
        systemName: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemName = systemName
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(width: 34, height: 34)
                .background(FilmyTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
