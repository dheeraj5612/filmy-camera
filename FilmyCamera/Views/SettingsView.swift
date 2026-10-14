import AVFoundation
import CoreLocation
import Photos
import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingCacheClear = false
    @AccessibilityFocusState private var cacheFocus: CacheFocus?
    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var locationAuthorizationStatus = CLAuthorizationStatus.notDetermined
    @State private var isConfirmingCameraReset = false
    @State private var didResetCameraSettings = false

    private enum CacheFocus: Hashable { case confirmTitle, clearRow }

    private static let cacheSlotID = "settings-cache-clear-slot"

    // UI-test preview of the clear-cache confirmation. The simulator never has
    // a local cache, so Debug builds can open the panel to check its layout.
    private static let forcesCacheConfirmPreview: Bool = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-ui-testing") && arguments.contains("-ui-testing-cache-confirm")
        #else
        return false
        #endif
    }()

    private var canClearCache: Bool { photoLibrary.hasLocalCache || Self.forcesCacheConfirmPreview }

    private let privacyPolicyURL = URL(string: "https://dheeraj5612.github.io/filmycam-legal/privacy-policy.html")!
    private let supportURL = URL(string: "https://dheeraj5612.github.io/filmycam-legal/support.html")!

    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("locationTaggingEnabled.v1") private var locationTaggingEnabled = true
    @AppStorage("mirrorFrontPhotos.v1") private var mirrorFrontPhotos = true
    @AppStorage("g7x.dateStamp.enabled") private var dateStampEnabled = false
    // Camera-screen keys that Reset camera settings restores. Defaults match CameraScreen and CaptureSetupView.
    @AppStorage("captureDelay") private var captureDelay = CaptureDelay.off
    @AppStorage("captureAspect") private var captureAspect = CaptureAspect.viewfinder
    @AppStorage("captureFinish") private var captureFinish = PhotoFinish.photo
    @AppStorage("compositionGuide") private var compositionGuide = CompositionGuide.thirds
    @AppStorage("showHistogram") private var showHistogram = false
    @AppStorage("showZebras") private var showZebras = false
    @AppStorage("showFocusPeaking") private var showFocusPeaking = false
    @AppStorage("showHorizonLevel") private var showHorizonLevel = false
    @AppStorage(HistogramPlacement.horizontalPreferenceKey) private var histogramPositionX = 0.0
    @AppStorage(HistogramPlacement.verticalPreferenceKey) private var histogramPositionY = 0.0
    @AppStorage("cameraGestureHintSeen.v1") private var gestureHintSeen = false

    var body: some View {
        NavigationStack {
            ZStack {
                FilmyPageBackground()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        settingsContent
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("settings-scroll")
                    .onChange(of: isConfirmingCacheClear) { _, open in
                        guard open else { return }
                        let anchor: UnitPoint = dynamicTypeSize.isAccessibilitySize ? .top : .center
                        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.24)
                        // Wait one turn so the taller panel is laid out first.
                        Task { @MainActor in
                            withAnimation(animation) {
                                proxy.scrollTo(Self.cacheSlotID, anchor: anchor)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CameraReturnBar(accessibilityIdentifier: "settings-back-to-camera", action: onBackToCamera)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog("Reset camera settings?", isPresented: $isConfirmingCameraReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive, action: resetCameraSettings)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Timer, aspect, photo finish, guides, assists, histogram position, grid, haptics, selfie mirroring and date stamp return to defaults. Your photos and looks are not changed.")
        }
        .accessibilityAction(.escape, onBackToCamera)
        .onAppear { refreshPermissionState() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionState()
        }
        .onChange(of: photoLibrary.hasLocalCache) { _, has in
            if !has { isConfirmingCacheClear = false }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            settingsHeader
            if MonetizationConfiguration.isEnabled {
                AccountSettingsSection()
            }

            cameraSettings
            savedPhotoSettings
            permissions
            localCache
            about
            resetSection
        }
        .frame(maxWidth: FilmyLayout.readableMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FilmyTheme.pageMargin)
        .padding(.top, 18)
        .padding(.bottom, 40)
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
            return "Your choice is remembered between launches."
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

    private var cameraSettings: some View {
        settingsSection(title: "CAMERA") {
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

            settingsDivider
            replayGesturesRow

            if #available(iOS 26.0, *) {
                settingsDivider
                SettingRow(
                    systemName: "airpodspro",
                    title: "AirPods camera remote",
                    detail: "With supported AirPods connected, choose Camera Remote in their system settings. Use your chosen stem gesture to take a photo while Filmy Camera is open. The capture timer applies too."
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var savedPhotoSettings: some View {
        settingsSection(
            title: "SAVED PHOTOS",
            footer: "These apply to each new photo you save."
        ) {
            dateStampRow
            settingsDivider
            mirrorFrontRow
            settingsDivider
            locationTaggingRow

            if locationNeedsSettings {
                settingsDivider
                settingsAction(
                    title: "Turn on location in Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "location-permission-settings",
                    hint: "Turn location on for Filmy there, then come back.",
                    subtitle: "Opens the Settings app",
                    action: openSystemSettings
                )
            }
        }
    }

    private var locationTagLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var locationTaggingRow: some View {
        HStack(alignment: .top, spacing: 13) {
            SettingIcon(systemName: "location.fill")
            locationTagLayout {
                locationTagText
                locationTagToggle
            }
        }
        .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var locationTagText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Location tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(locationTagDetail)
                .font(.caption)
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-location-access")
    }

    private var locationTagToggle: some View {
        Toggle("Location tagging", isOn: $locationTaggingEnabled)
            .labelsHidden()
            .tint(FilmyTheme.accent)
            .accessibilityIdentifier("settings-location-tagging")
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }

    private var locationTagDetail: String {
        guard locationTaggingEnabled else {
            return "Off. Photos are not tagged with where you took them."
        }
        switch locationAuthorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "On. Filmy reads location only while the camera is open."
        case .denied, .restricted:
            return "On, but iPhone location is off for Filmy."
        default:
            return "On. iPhone asks the first time you open the camera."
        }
    }

    private var replayGesturesRow: some View {
        Button(action: replayGestureHint) {
            HStack(alignment: .center, spacing: 13) {
                SettingIcon(systemName: "hand.draw")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Replay gestures")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FilmyTheme.accent)
                    Text(replayGesturesDetail)
                        .font(.caption)
                        .foregroundStyle(FilmyTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-replay-gestures")
        .accessibilityLabel("Replay gestures")
        .accessibilityValue(gestureHintSeen ? "Hint already seen" : "Hint turned back on")
        .accessibilityHint("Shows the camera gesture hint again.")
    }

    private var replayGesturesDetail: String {
        gestureHintSeen
            ? "Show the camera gesture hint again."
            : "Turned back on. It shows when the camera is running."
    }

    private func replayGestureHint() {
        HapticFeedback.play(.selection)
        gestureHintSeen = false
        UIAccessibility.post(notification: .announcement, argument: "Gesture hint turned back on.")
    }

    private var mirrorFrontRow: some View {
        SettingRow(
            systemName: "person.crop.square",
            title: "Mirror front camera",
            detail: "Saves selfies as they appear in the preview."
        ) {
            Toggle("Mirror front camera", isOn: $mirrorFrontPhotos)
                .labelsHidden()
                .tint(FilmyTheme.accent)
                .accessibilityIdentifier("settings-mirror-front")
        }
    }

    private var dateStampRow: some View {
        SettingRow(
            systemName: "calendar",
            title: "Date stamp",
            detail: "Prints the capture date in the corner of saved photos, like a compact camera."
        ) {
            Toggle("Date stamp", isOn: $dateStampEnabled)
                .labelsHidden()
                .tint(FilmyTheme.accent)
                .accessibilityIdentifier("settings-date-stamp")
        }
    }

    private var locationNeedsSettings: Bool {
        locationAuthorizationStatus == .denied || locationAuthorizationStatus == .restricted
    }

    private var resetSection: some View {
        settingsSection(title: "RESET") {
            Button {
                HapticFeedback.play(.selection)
                didResetCameraSettings = false
                isConfirmingCameraReset = true
            } label: {
                HStack(alignment: .center, spacing: 13) {
                    SettingIcon(systemName: "arrow.counterclockwise", tint: FilmyTheme.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset camera settings")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FilmyTheme.danger)
                        Text(didResetCameraSettings ? "Camera settings reset." : "Photos and looks are kept")
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
            .accessibilityIdentifier("settings-reset-camera")
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
            title: "PERMISSIONS",
            footer: "Filmy only asks for what it needs to take and save your photos."
        ) {
            SettingRow(
                systemName: "camera.fill",
                title: "Camera",
                detail: cameraStatusDetail
            ) {
                permissionBadge("Camera", title: cameraStatusTitle, isEnabled: cameraStatusIsEnabled)
            }

            if cameraPermissionNeedsSettings {
                settingsDivider
                settingsAction(
                    title: "Turn on camera in Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "camera-permission-settings",
                    hint: "Turn the camera on for Filmy there, then come back.",
                    subtitle: "Opens the Settings app",
                    action: openSystemSettings
                )
            }

            if cameraPermissionNeedsRequest {
                settingsDivider
                settingsAction(
                    title: "Allow camera access",
                    systemName: "camera.badge.ellipsis",
                    identifier: "camera-permission-request",
                    hint: "Shows the camera permission prompt.",
                    action: requestCameraAccess
                )
            }

            settingsDivider

            SettingRow(
                systemName: "photo.on.rectangle",
                title: "Photos",
                detail: photoStatusDetail
            ) {
                permissionBadge("Photos", title: photoStatusTitle, isEnabled: photosBadgeIsEnabled)
            }

            if photoLibrary.authorizationStatus == .denied || photoLibrary.authorizationStatus == .restricted {
                settingsDivider
                settingsAction(
                    title: "Turn on Photos in Settings",
                    systemName: "arrow.up.right.square",
                    identifier: "photos-permission-settings",
                    hint: "Turn Photos on for Filmy there so the Roll can show your photos.",
                    subtitle: "Opens the Settings app",
                    action: openSystemSettings
                )
            } else if photoLibrary.authorizationStatus == .notDetermined {
                settingsDivider
                settingsAction(
                    title: "Allow Photos access",
                    systemName: "photo.badge.plus",
                    identifier: "photos-permission-action",
                    hint: "Shows the Photos permission prompt so the Roll can show your photos.",
                    action: requestPhotoAccess
                )
            }

            if photoLibrary.addOnlyAuthorizationStatus == .denied
                || photoLibrary.addOnlyAuthorizationStatus == .restricted {
                settingsDivider
                settingsAction(
                    title: "Allow saving new photos",
                    systemName: "arrow.up.right.square",
                    identifier: "photos-save-permission-settings",
                    hint: "Allow Filmy to add photos there so new photos can be saved.",
                    subtitle: "Opens the Settings app",
                    action: openSystemSettings
                )
            } else if photoLibrary.addOnlyAuthorizationStatus == .notDetermined {
                settingsDivider
                settingsAction(
                    title: "Allow saving new photos",
                    systemName: "photo.badge.plus",
                    identifier: "photos-save-permission-request",
                    hint: "Shows the permission prompt for saving new photos.",
                    action: requestSaveAccess
                )
            }
        }
    }

    private var localCache: some View {
        settingsSection(
            title: "STORAGE",
            footer: "The local cache keeps your photos close when Photos access is limited or off. It is not backed up, and you can clear it any time."
        ) {
            SettingRow(
                systemName: "externaldrive.fill",
                title: "Local cache",
                detail: photoLibrary.hasLocalCache ? "Temporary copies of your photos are on this device." : "No temporary copies right now."
            ) {
                Text(photoLibrary.hasLocalCache ? "On device" : "Empty")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }

            settingsDivider

            VStack(spacing: 0) {
                if isConfirmingCacheClear && canClearCache {
                    clearCacheConfirmPanel
                } else {
                    clearCacheRow
                }
            }
            .id(Self.cacheSlotID)

            settingsDivider

            storageExplainer
        }
    }

    private var clearCacheRow: some View {
        Button {
            guard canClearCache else { return }
            HapticFeedback.play(.selection)
            setCacheConfirm(true)
        } label: {
            HStack(alignment: .center, spacing: 13) {
                SettingIcon(
                    systemName: "trash",
                    tint: canClearCache ? FilmyTheme.danger : FilmyTheme.tertiary
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear local cache")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canClearCache ? FilmyTheme.danger : FilmyTheme.tertiary)
                    Text(canClearCache ? "Every photo in Photos is kept" : "Nothing to remove")
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
        .disabled(!canClearCache)
        .accessibilityIdentifier("clear-local-cache")
        .accessibilityLabel("Clear local cache")
        .accessibilityValue(canClearCache ? "Available" : "Empty")
        .accessibilityHint(canClearCache ? "Asks before removing temporary copies. Every photo in Photos is kept." : "There are no temporary copies to clear")
        .accessibilityFocused($cacheFocus, equals: .clearRow)
    }

    // Replaces the clear row in place. No identifier on the container: an
    // ancestor id can replace a descendant id on some OS versions.
    private var clearCacheConfirmPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            cacheConfirmTitle
            if dynamicTypeSize.isAccessibilitySize {
                cacheConfirmButtons
                cacheConfirmLines
            } else {
                cacheConfirmLines
                cacheConfirmButtons
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { setCacheConfirm(false) }
    }

    private var cacheConfirmTitle: some View {
        Text("Clear cache?")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($cacheFocus, equals: .confirmTitle)
    }

    private var cacheConfirmLines: some View {
        VStack(alignment: .leading, spacing: 8) {
            cacheConfirmLine("minus.circle", "Removed: temporary copies on this device.")
            cacheConfirmLine("checkmark.circle", "Kept: every photo in Photos.")
            if photoLibrary.authorizationStatus != .authorized {
                cacheConfirmLine("exclamationmark.triangle", cacheRoleWarning)
            }
        }
    }

    private var cacheRoleWarning: String {
        photoLibrary.authorizationStatus == .limited
            ? "Photos access is limited, so some of these photos may leave the Roll."
            : "Until Photos access is on, these photos may leave the Roll."
    }

    private func cacheConfirmLine(_ systemName: String, _ text: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.footnote)
            .foregroundStyle(FilmyTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cacheConfirmButtons: some View {
        VStack(spacing: 12) {
            Button("Keep cache") {
                HapticFeedback.play(.selection)
                setCacheConfirm(false)
            }
            .buttonStyle(.filmySecondary)
            .accessibilityIdentifier("keep-local-cache")
            .accessibilityHint("Closes this panel. Nothing is removed.")

            Button(action: confirmClearCache) {
                Label("Clear cache", systemImage: "trash")
                    .foregroundStyle(FilmyTheme.danger)
            }
            .buttonStyle(.filmySecondary)
            .accessibilityIdentifier("confirm-clear-local-cache")
            .accessibilityHint("Removes the temporary copies now.")
        }
    }

    private func setCacheConfirm(_ open: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            isConfirmingCacheClear = open
        }
        Task { @MainActor in
            cacheFocus = open ? .confirmTitle : .clearRow
        }
    }

    private func confirmClearCache() {
        if photoLibrary.hasLocalCache {
            HapticFeedback.play(.discard)
            photoLibrary.clearLocalRollCache()
        }
        setCacheConfirm(false)
    }

    // Plain text on purpose: these are places, not controls.
    private var storageExplainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your photos are")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            storagePlace(
                "Photos app",
                "Every camera photo saves here by itself. Imported photos save only when you choose.",
                id: "settings-storage-place-photos"
            )
            storagePlace(
                "Roll",
                "Shows your Filmy photos from Photos. Originals you can edit again stay in Filmy.",
                id: "settings-storage-place-roll"
            )
            storagePlace(
                "Captures",
                "Shots from Capture modes stay in Filmy until you export them.",
                id: "settings-storage-place-captures"
            )
            Text("Deleting the app removes what stays in Filmy.")
                .font(.caption)
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func storagePlace(_ title: String, _ detail: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(FilmyTheme.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
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
                    Text(subtitle ?? "Shows the permission prompt")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .multilineTextAlignment(.leading)
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

    private var photosBadgeIsEnabled: Bool {
        PhotoLibraryAuthorizationPolicy.canRead(photoLibrary.authorizationStatus) || photoLibrary.canSaveToPhotos
    }

    // The badge alone reads "Off" with no subject, so name what it describes.
    private func permissionBadge(_ name: String, title: String, isEnabled: Bool) -> some View {
        PermissionBadge(title: title, isEnabled: isEnabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name), \(title)")
    }

    private var photoStatusTitle: String {
        let canRead = PhotoLibraryAuthorizationPolicy.canRead(photoLibrary.authorizationStatus)
        let canAdd = photoLibrary.canSaveToPhotos
        switch (canRead, canAdd, photoLibrary.authorizationStatus, photoLibrary.addOnlyAuthorizationStatus) {
        case (true, true, .authorized, _): return "On"
        case (true, true, .limited, _): return "Limited"
        case (false, true, _, _): return "Save only"
        case (_, false, .notDetermined, _), (_, false, _, .notDetermined): return "Not asked"
        case (false, false, .denied, _), (false, false, .restricted, _): return "Off"
        default: return "Unknown"
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
        if camera.availability == .simulator { return "Simulator" }
        switch cameraAuthorizationStatus {
        case .authorized:
            return "On"
        case .notDetermined:
            return camera.availability == .requestingPermission ? "Asking" : "Not asked"
        case .denied, .restricted:
            return "Off"
        @unknown default:
            return "Unknown"
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
            case .running: return "The camera is on and ready."
            case .paused: return "Camera access is on. The preview is paused."
            case .interrupted, .needsRecovery, .unavailable: return camera.statusMessage
            default: return "Camera access is on. Open the camera to start."
            }
        case .notDetermined:
            return camera.availability == .requestingPermission
                ? "Waiting for your answer to the permission prompt."
                : "Filmy has not asked for the camera yet."
        case .denied, .restricted:
            return "Camera access is off. Filmy cannot take photos until you turn it on."
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
                ? "Filmy can see the photos you picked and can save new ones."
                : "Filmy can show your photos and save new ones."
        case (false, true):
            return "Filmy can save new photos. Allow Photos access to see them in the Roll."
        case (true, false):
            return "The Roll can show your photos. Saving new photos is not on yet."
        default:
            return photoDeniedDetail
        }
    }

    private var photoDeniedDetail: String {
        let read = photoLibrary.authorizationStatus
        let add = photoLibrary.addOnlyAuthorizationStatus
        let readDenied = read == .denied || read == .restricted
        let addDenied = add == .denied || add == .restricted
        if read == .notDetermined && add == .notDetermined { return "Filmy has not asked for Photos yet." }
        if read == .notDetermined && addDenied { return "Filmy has not asked to see your photos. Saving new photos is off." }
        if readDenied && add == .notDetermined {
            return "Filmy cannot see your photos and has not asked to save new ones yet."
        }
        return "Photos access is off for Filmy."
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    private func refreshPermissionState() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        locationAuthorizationStatus = CLLocationManager().authorizationStatus
        photoLibrary.refresh()
    }

    private func resetCameraSettings() {
        showGrid = true
        hapticsEnabled = true
        mirrorFrontPhotos = true
        dateStampEnabled = false
        captureDelay = .off
        captureAspect = .viewfinder
        captureFinish = .photo
        compositionGuide = .thirds
        showHistogram = false
        showZebras = false
        showFocusPeaking = false
        showHorizonLevel = false
        histogramPositionX = 0
        histogramPositionY = 0
        gestureHintSeen = false
        HapticFeedback.play(.discard)
        didResetCameraSettings = true
        UIAccessibility.post(notification: .announcement, argument: "Camera settings reset.")
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
