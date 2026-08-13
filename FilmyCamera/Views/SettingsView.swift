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
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeading(eyebrow: "Make it yours", title: "Settings")

                    introCard
                    captureSettings
                    permissions
                    localCache
                    about
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .background(FilmyTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var introCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(FilmyTheme.accent.opacity(0.18))
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(FilmyTheme.accent)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text("A slower way to see")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("Filmy Camera keeps your look, your frame, and your roll close at hand.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var captureSettings: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("CAPTURE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(FilmyTheme.tertiary)

            GlassCard(padding: 15) {
                VStack(spacing: 18) {
                    SettingRow(
                        systemName: "square.grid.3x3",
                        title: "Framing grid",
                        detail: "Keep a quiet rule-of-thirds guide over the preview."
                    ) {
                        Toggle("Framing grid", isOn: $showGrid)
                            .labelsHidden()
                            .tint(FilmyTheme.accent)
                    }

                    Divider().overlay(FilmyTheme.line)

                    SettingRow(
                        systemName: "waveform.path.ecg",
                        title: "Shutter feedback",
                        detail: "Use a subtle haptic when a frame is captured."
                    ) {
                        Toggle("Shutter feedback", isOn: $hapticsEnabled)
                            .labelsHidden()
                            .tint(FilmyTheme.accent)
                    }

                    Divider().overlay(FilmyTheme.line)

                }
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ACCESS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(FilmyTheme.tertiary)

            GlassCard(padding: 15) {
                VStack(spacing: 18) {
                    SettingRow(
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
                        Divider().overlay(FilmyTheme.line)
                        Button("Open System Settings", action: openSystemSettings)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHint("Opens Filmy Camera camera permissions")
                    }

                    Divider().overlay(FilmyTheme.line)

                    SettingRow(
                        systemName: "photo.on.rectangle",
                        title: "Photos",
                        detail: photoStatusDetail
                    ) {
                        PermissionBadge(title: photoStatusTitle, isEnabled: photoLibrary.authorizationStatus == .authorized || photoLibrary.authorizationStatus == .limited)
                    }

                    if photoLibrary.authorizationStatus == .denied || photoLibrary.authorizationStatus == .restricted {
                        Divider().overlay(FilmyTheme.line)
                        Button("Open System Settings", action: openSystemSettings)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHint("Opens Filmy Camera permissions")
                    } else if photoLibrary.authorizationStatus == .notDetermined {
                        Divider().overlay(FilmyTheme.line)
                        Button("Allow Photos access") {
                            Task { _ = await photoLibrary.requestAccessIfNeeded() }
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ABOUT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(FilmyTheme.tertiary)

            GlassCard(padding: 15) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("Filmy Camera")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(FilmyTheme.primary)
                        Spacer()
                        Text("1.0")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(FilmyTheme.accent)
                    }

                    Text("Recipe names are original, camera-inspired descriptions. Filmy Camera is an independent experience; it does not include camera firmware, proprietary LUTs, or calibration data.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(FilmyTheme.line)

                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(FilmyTheme.mint)
                        Text("Your frames save to Photos; local copies are temporary and removable.")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(FilmyTheme.mint)
                    }

                    Divider().overlay(FilmyTheme.line)

                    HStack(spacing: 16) {
                        Link(destination: privacyPolicyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .accessibilityIdentifier("privacy-policy-link")

                        Spacer(minLength: 8)

                        Link(destination: supportURL) {
                            Label("Contact Support", systemImage: "questionmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .accessibilityIdentifier("support-link")
                    }
                    .foregroundStyle(FilmyTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                }
            }
        }
    }

    private var localCache: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ON-DEVICE ROLL")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(FilmyTheme.tertiary)

            GlassCard(padding: 15) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Offline roll cache")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(FilmyTheme.primary)
                            Text("A temporary local copy keeps your roll visible when Photos access is limited. It is private, excluded from backup, and capped at 250 MB.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(FilmyTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().overlay(FilmyTheme.line)

                    Button("Clear local cache") {
                        photoLibrary.clearLocalRollCache()
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(FilmyTheme.accent)
                    .disabled(!photoLibrary.hasLocalCache)
                    .accessibilityIdentifier("clear-local-cache")
                }
            }
        }
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

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
