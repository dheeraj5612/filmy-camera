import AVFoundation
import Photos
import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConfirmingCacheClear = false
    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private let privacyPolicyURL = URL(string: "https://dheeraj5612.github.io/filmycam-legal/privacy-policy.html")!
    private let supportURL = URL(string: "https://dheeraj5612.github.io/filmycam-legal/support.html")!

    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            ZStack {
                FilmyPageBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        settingsHeader
                        if MonetizationConfiguration.isEnabled {
                            AccountSettingsSection()
                        }

                        captureSettings
                        permissions
                        localCache
                        about
                    }
                    .frame(maxWidth: FilmyLayout.readableMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, FilmyTheme.pageMargin)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("settings-scroll")
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CameraReturnBar(accessibilityIdentifier: "settings-back-to-camera", action: onBackToCamera)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog("Clear the local frame cache?", isPresented: $isConfirmingCacheClear, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                guard photoLibrary.hasLocalCache else { return }
                HapticFeedback.play(.discard)
                photoLibrary.clearLocalRollCache()
            }
            .accessibilityIdentifier("confirm-clear-local-cache")
            Button("Keep cache", role: .cancel) { }
        } message: {
            Text("Only temporary copies on this device are removed. Photos originals are not deleted. Cached frames may disappear from the Roll while Photos access is limited or off.")
        }
        .accessibilityAction(.escape, onBackToCamera)
        .onAppear { refreshPermissionState() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionState()
        }
    }

    private var settingsHeader: some View {
        SectionHeading(eyebrow: "FILMY CAMERA \(appVersion)", title: "Settings")
            .accessibilityLabel("\(AppConfiguration.displayName) settings, version \(appVersion)")
    }

    private var flashSettingDetail: String {
        switch camera.flashAvailability {
        case .unsupported:
            return "The active camera has no flash. Switch to a camera with one to change this; the choice is remembered."
        case .temporarilyUnavailable:
            return "The flash is temporarily unavailable, usually while the device cools down."
        case .available:
            return "On by default. Your choice is remembered between launches."
        }
    }

    private var flashModeBinding: Binding<CameraService.FlashMode> {
        Binding(
            get: { camera.flashMode },
            set: { mode in
                HapticFeedback.play(.controlStep)
                camera.setFlashMode(mode)
            }
        )
    }

    // MARK: - Sections

    private var captureSettings: some View {
        settingsSection(title: "CAPTURE") {
            if #available(iOS 26.0, *) {
                SettingRow(
                    systemName: "airpodspro",
                    title: "AirPods camera remote",
                    detail: "With supported AirPods connected, choose Camera Remote in their system settings. Use your chosen stem gesture to take a photo while Filmy Camera is open. The capture timer applies too."
                ) {
                    EmptyView()
                }
                settingsDivider
            }

            VStack(alignment: .leading, spacing: 12) {
                SettingRow(
                    systemName: "bolt.fill",
                    title: "Flash",
                    detail: flashSettingDetail
                ) {
                    EmptyView()
                }
                flashPicker
            }

            settingsDivider

            SettingRow(
                systemName: "grid",
                title: "Framing grid",
                detail: "A quiet rule-of-thirds guide over the preview."
            ) {
                Toggle("Framing grid", isOn: $showGrid)
                    .labelsHidden()
                    .tint(FilmyTheme.accent)
            }

            settingsDivider

            SettingRow(
                systemName: "hand.tap",
                title: "Haptic feedback",
                detail: "Subtle feedback for capture, selections, controls, and outcomes."
            ) {
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    .labelsHidden()
                    .tint(FilmyTheme.accent)
            }
        }
    }

    private var flashPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Flash", selection: flashModeBinding) {
                    ForEach(CameraService.FlashMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Flash", selection: flashModeBinding) {
                    ForEach(CameraService.FlashMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        // Off remains selectable during thermal unavailability. The service
        // owns validation of On/Auto and unsupported cameras.
        .disabled(camera.flashAvailability == .unsupported)
        .accessibilityIdentifier("flash-setting")
    }

    private var permissions: some View {
        settingsSection(
            title: "ACCESS",
            footer: "Filmy Camera only asks for the access needed to make and keep a frame."
        ) {
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
                settingsDivider
                settingsAction(
                    title: "Open System Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "camera-permission-settings",
                    hint: "Opens Filmy Camera camera permissions",
                    subtitle: "Continue in iOS Settings",
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

            SettingRow(
                systemName: "photo.on.rectangle",
                title: "Photos",
                detail: photoStatusDetail
            ) {
                PermissionBadge(
                    title: photoStatusTitle,
                    isEnabled: PhotoLibraryAuthorizationPolicy.canRead(photoLibrary.authorizationStatus)
                        || photoLibrary.canSaveToPhotos
                )
            }

            if photoLibrary.authorizationStatus == .denied || photoLibrary.authorizationStatus == .restricted {
                settingsDivider
                settingsAction(
                    title: "Open System Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "photos-permission-settings",
                    hint: "Opens Filmy Camera permissions",
                    subtitle: "Continue in iOS Settings",
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

            if photoLibrary.addOnlyAuthorizationStatus == .denied
                || photoLibrary.addOnlyAuthorizationStatus == .restricted {
                settingsDivider
                settingsAction(
                    title: "Allow saving frames",
                    systemName: "arrow.up.right.square",
                    identifier: "photos-save-permission-settings",
                    hint: "Opens Filmy Camera Photos permissions for saving frames",
                    subtitle: "Continue in iOS Settings",
                    action: openSystemSettings
                )
            } else if photoLibrary.addOnlyAuthorizationStatus == .notDetermined {
                settingsDivider
                settingsAction(
                    title: "Allow saving frames",
                    systemName: "photo.badge.plus",
                    identifier: "photos-save-permission-request",
                    hint: "Requests Photos access needed to save finished frames",
                    action: requestSaveAccess
                )
            }
        }
    }

    private var localCache: some View {
        settingsSection(
            title: "STORAGE",
            footer: "A private fallback keeps finished frames close when Photos access is limited. It is excluded from backup and removable at any time."
        ) {
            SettingRow(
                systemName: "externaldrive.fill",
                title: "Frame cache",
                detail: photoLibrary.hasLocalCache ? "Temporary frames are stored on this device." : "No temporary frames right now."
            ) {
                Text(photoLibrary.hasLocalCache ? "On device" : "Empty")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }

            settingsDivider

            Button {
                guard photoLibrary.hasLocalCache else { return }
                HapticFeedback.play(.selection)
                isConfirmingCacheClear = true
            } label: {
                HStack(alignment: .center, spacing: 13) {
                    SettingIcon(
                        systemName: "trash",
                        tint: photoLibrary.hasLocalCache ? FilmyTheme.danger : FilmyTheme.tertiary
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear local cache")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(photoLibrary.hasLocalCache ? FilmyTheme.danger : FilmyTheme.tertiary)
                        Text(photoLibrary.hasLocalCache ? "Photos originals are kept" : "Nothing to remove")
                            .font(.caption)
                            .foregroundStyle(FilmyTheme.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!photoLibrary.hasLocalCache)
            .accessibilityIdentifier("clear-local-cache")
            .accessibilityLabel("Clear local cache")
            .accessibilityValue(photoLibrary.hasLocalCache ? "Available" : "Empty")
            .accessibilityHint(photoLibrary.hasLocalCache ? "Asks before removing temporary copies. Photos originals are kept." : "There are no temporary camera frames to clear")
        }
    }

    private var about: some View {
        settingsSection(title: "ABOUT") {
            HStack(alignment: .center, spacing: 13) {
                SettingIcon(systemName: "camera.aperture")

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppConfiguration.displayName)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("Version \(appVersion)")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                }

                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .combine)

            settingsDivider

            Text(AppConfiguration.isG7X ? "G7X Camera is an independent experience. Your frames save to Photos; local copies are temporary and removable." : "Recipe names are original, camera-inspired descriptions. Filmy Camera is an independent experience; it does not include camera firmware, proprietary LUTs, or calibration data. Your frames save to Photos; local copies are temporary and removable.")
                .font(.system(.footnote, design: .default).weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            settingsDivider

            settingsLink(
                title: "Privacy Policy",
                systemName: "hand.raised.fill",
                destination: privacyPolicyURL,
                identifier: "privacy-policy-link"
            )

            settingsDivider

            settingsLink(
                title: "Contact Support",
                systemName: "questionmark.circle.fill",
                destination: supportURL,
                identifier: "support-link"
            )
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            GlassCard(padding: 14) {
                VStack(spacing: 0, content: content)
            }

            if let footer {
                Text(footer)
                    .font(.system(.caption, design: .default).weight(.medium))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(FilmyTheme.line)
            .padding(.leading, 49)
            .padding(.vertical, 10)
    }

    private func settingsAction(
        title: String,
        systemName: String,
        identifier: String,
        hint: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                SettingIcon(systemName: systemName)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(FilmyTheme.accent)
                        .multilineTextAlignment(.leading)
                    Text(subtitle ?? "Show the system permission prompt")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 13) {
                SettingIcon(systemName: systemName)

                Text(title)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Status copy

    private var photoStatusTitle: String {
        let canRead = PhotoLibraryAuthorizationPolicy.canRead(photoLibrary.authorizationStatus)
        let canAdd = photoLibrary.canSaveToPhotos
        switch (canRead, canAdd, photoLibrary.authorizationStatus, photoLibrary.addOnlyAuthorizationStatus) {
        case (true, true, .authorized, _): return "ALLOWED"
        case (true, true, .limited, _): return "LIMITED"
        case (false, true, _, _): return "SAVE ONLY"
        case (_, false, .notDetermined, _), (_, false, _, .notDetermined): return "ASK"
        case (false, false, .denied, _), (false, false, .restricted, _): return "OFF"
        default: return "CHECK"
        }
    }

    private var cameraPermissionNeedsSettings: Bool {
        let status = cameraAuthorizationStatus
        return status == .denied || status == .restricted
    }

    private var cameraPermissionNeedsRequest: Bool {
        cameraAuthorizationStatus == .notDetermined
            && camera.availability != .simulator
            && camera.availability != .requestingPermission
    }

    private var cameraStatusTitle: String {
        if camera.availability == .simulator { return "SIMULATOR" }
        switch cameraAuthorizationStatus {
        case .authorized:
            return camera.availability == .running ? "LIVE" : "ALLOWED"
        case .notDetermined:
            return camera.availability == .requestingPermission ? "ASKING" : "ASK"
        case .denied, .restricted:
            return "OFF"
        @unknown default:
            return "CHECK"
        }
    }

    private var cameraStatusIsEnabled: Bool {
        camera.availability != .simulator && cameraAuthorizationStatus == .authorized
    }

    private var cameraStatusDetail: String {
        if camera.availability == .simulator { return "Simulator-safe preview mode" }
        switch cameraAuthorizationStatus {
        case .authorized:
            switch camera.availability {
            case .running: return "Live preview is ready to capture."
            case .paused: return "Camera access is enabled; preview is paused."
            case .interrupted, .needsRecovery, .unavailable: return camera.statusMessage
            default: return "Camera access is enabled. Open Camera to begin preview."
            }
        case .notDetermined:
            return camera.availability == .requestingPermission
                ? "Waiting for camera permission."
                : "Ask when you are ready to capture."
        case .denied, .restricted:
            return "Enable camera access in Settings to preview and capture."
        @unknown default:
            return "Camera permission status is unavailable."
        }
    }

    private var photoStatusDetail: String {
        let canRead = PhotoLibraryAuthorizationPolicy.canRead(photoLibrary.authorizationStatus)
        let canAdd = photoLibrary.canSaveToPhotos
        switch (canRead, canAdd) {
        case (true, true):
            return photoLibrary.authorizationStatus == .limited
                ? "Limited access is enabled for selected photos; new frames can still be saved."
                : "Read and save access is enabled."
        case (false, true):
            return "Save access is enabled; allow Photos access to view the Roll."
        case (true, false):
            return "The Roll is available; allow add access to save new frames."
        default:
            return "Ask when you are ready to build your roll."
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    private func refreshPermissionState() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        photoLibrary.refresh()
    }

    private func requestPhotoAccess() {
        Task { _ = await photoLibrary.requestAccessIfNeeded() }
    }

    private func requestSaveAccess() {
        Task { _ = await photoLibrary.requestSaveAccessIfNeeded() }
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
                cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                cameraService.stop()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
