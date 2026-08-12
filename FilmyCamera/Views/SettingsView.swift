import AVFoundation
import Photos
import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var photoLibrary: PhotoLibraryService

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

                    Text("Recipe names use public Fujifilm-style vocabulary for orientation. Filmy Camera is an independent camera experience; it does not include Fujifilm firmware or proprietary calibration data.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(FilmyTheme.line)

                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(FilmyTheme.mint)
                        Text("Your frames stay in your Photos library.")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(FilmyTheme.mint)
                    }
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

    private var isSimulator: Bool {
        camera.statusMessage.localizedCaseInsensitiveContains("Simulator")
    }

    private var cameraPermissionNeedsSettings: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .denied
            || AVCaptureDevice.authorizationStatus(for: .video) == .restricted
            || camera.statusMessage.localizedCaseInsensitiveContains("access")
    }

    private var cameraStatusTitle: String {
        if isSimulator { return "SIMULATOR" }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized where camera.isRunning: return "LIVE"
        case .authorized: return "ALLOWED"
        case .notDetermined: return "ASK"
        case .denied, .restricted: return "OFF"
        @unknown default: return "CHECK"
        }
    }

    private var cameraStatusIsEnabled: Bool {
        if isSimulator { return false }
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized && camera.isRunning
    }

    private var cameraStatusDetail: String {
        if isSimulator { return "Simulator-safe preview mode" }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized where camera.isRunning: return "Live preview is ready to capture."
        case .authorized: return "Camera access is enabled; preview is paused."
        case .notDetermined: return "Ask when you are ready to capture."
        case .denied, .restricted: return "Enable camera access in Settings to preview and capture."
        @unknown default: return camera.statusMessage
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
