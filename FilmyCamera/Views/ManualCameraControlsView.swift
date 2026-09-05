import SwiftUI

/// A compact, camera-first surface for sensor controls. Slider drags stay local
/// until the gesture ends so AVFoundation receives one bounded request instead
/// of a request for every touch sample.
struct ManualCameraControlsView: View {
    @ObservedObject var camera: CameraService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isoDraft: Double = 0
    @State private var shutterPosition: Double = 0
    @State private var kelvinDraft: Double = 0
    @State private var tintDraft: Double = 0
    @State private var focusDraft: Double = 0
    @State private var editingISO = false
    @State private var editingShutter = false
    @State private var editingKelvin = false
    @State private var editingTint = false
    @State private var editingFocus = false

    private var controls: CameraManualControls { camera.manualControls }
    private var hasManualCapability: Bool {
        controls.manualExposureSupported
            || controls.manualWhiteBalanceSupported
            || controls.manualFocusSupported
            || controls.physicalLensOptions.contains(where: \.supportsAnyManualControl)
    }
    private var isApplying: Bool { controls.isApplying }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if hasManualCapability { statusHeader }

                    if !controls.physicalLensOptions.isEmpty {
                        physicalLensSection
                    }

                    if hasManualCapability {
                        exposureSection
                        whiteBalanceSection
                        focusSection
                    } else {
                        unavailableCard
                    }

                    resetButton
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 20)
                .padding(.vertical, 20)
            }
            .background(FilmyTheme.background.ignoresSafeArea())
            .navigationTitle("Pro controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minHeight: FilmyTheme.minimumHitTarget)
                        .accessibilityIdentifier("manual-controls-done")
                }
            }
        }
        .accessibilityIdentifier("manual-controls-screen")
        .onAppear {
            camera.refreshManualControls()
            syncDrafts()
        }
        .onChange(of: controls) { _, _ in syncDraftsIfIdle() }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "CAMERA", color: FilmyTheme.filmAccent)
            Text(controls.activeDeviceName)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(statusDescription)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual-controls-status")
        }
    }

    private var statusDescription: String {
        if camera.availability == .simulator {
            return "Manual sensor controls appear on a physical camera. This preview cannot change ISO, shutter, white balance, or focus."
        }
        if camera.availability == .permissionDenied {
            return "Allow Camera access in Settings to use manual controls."
        }
        if controls.activeDeviceID == nil {
            return "Camera controls will appear when the camera is ready."
        }
        if isApplying { return "Applying your settings…" }
        if controls.requiresPhysicalLensSelection {
            return "Automatic lens switching is active. Choose a lens below to access more manual controls."
        }
        if controls.isAnyManualModeEnabled {
            return "Manual settings are applied to the next capture."
        }
        return "Auto settings meter each frame."
    }

    private var physicalLensSection: some View {
        controlSection(title: "Lens", subtitle: "Choose a lens for manual control. Availability varies by camera.") {
            VStack(spacing: 8) {
                ForEach(controls.physicalLensOptions) { lens in
                    Button {
                        camera.setManualControlLens(id: lens.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: lens.isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(lens.isActive ? FilmyTheme.filmAccent : FilmyTheme.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lens.title)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(FilmyTheme.primary)
                                Text(lens.detail)
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundStyle(FilmyTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(lens.isActive ? FilmyTheme.filmAccent : FilmyTheme.line, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                    .accessibilityIdentifier("manual-lens-\(lens.id)")
                    .accessibilityLabel("Use \(lens.title)")
                    .accessibilityValue(lens.isActive ? "Selected" : "Available")
                }
            }
        }
    }

    private var exposureSection: some View {
        controlSection(title: "Exposure", subtitle: "Set sensitivity and shutter speed, or let the camera meter automatically.") {
            modePicker(
                title: "Exposure mode",
                mode: controls.exposureMode,
                supported: controls.manualExposureSupported,
                autoID: "manual-exposure-auto",
                manualID: "manual-exposure-manual",
                autoAction: camera.setAutoExposure,
                manualAction: camera.lockCurrentExposure
            )

            if controls.manualExposureSupported && controls.exposureMode == .manual {
                sliderRow(
                    title: "ISO",
                    displayValue: "ISO \(Int(isoDraft.rounded()))",
                    id: "manual-iso-slider",
                    value: $isoDraft,
                    range: Double(controls.minimumISO)...Double(controls.maximumISO),
                    step: 1,
                    editing: $editingISO,
                    onEnded: { camera.setManualExposure(iso: Float(isoDraft), durationSeconds: duration(for: shutterPosition)) }
                )
                sliderRow(
                    title: "Shutter",
                    displayValue: shutterLabel(duration(for: shutterPosition)),
                    id: "manual-shutter-slider",
                    value: $shutterPosition,
                    range: 0...1,
                    step: 0.01,
                    editing: $editingShutter,
                    onEnded: { camera.setManualExposure(iso: Float(isoDraft), durationSeconds: duration(for: shutterPosition)) }
                )
                if controls.exposureDurationSeconds > (1.0 / 30.0) {
                    Text("Slower shutter speeds reduce live preview smoothness. Hold steady.")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if controls.flashRequiresAutoExposure {
                    Text("Flash is off while Manual exposure is active. Return to Auto to restore it.")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(FilmyTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !controls.manualExposureSupported {
                unsupportedText("Manual ISO and shutter are unavailable on this camera.")
            }
        }
        .accessibilityIdentifier("manual-exposure-section")
    }

    private var whiteBalanceSection: some View {
        controlSection(title: "White balance", subtitle: "Sensor color temperature is separate from the selected film recipe.") {
            modePicker(
                title: "White balance mode",
                mode: controls.whiteBalanceMode,
                supported: controls.manualWhiteBalanceSupported,
                autoID: "manual-white-balance-auto",
                manualID: "manual-white-balance-manual",
                autoAction: camera.setAutoWhiteBalance,
                manualAction: camera.lockCurrentWhiteBalance
            )

            if controls.manualWhiteBalanceSupported && controls.whiteBalanceMode == .manual {
                sliderRow(
                    title: "Temperature",
                    displayValue: "\(Int(kelvinDraft.rounded()))K",
                    id: "manual-kelvin-slider",
                    value: $kelvinDraft,
                    range: Double(controls.minimumKelvin)...Double(controls.maximumKelvin),
                    step: 50,
                    editing: $editingKelvin,
                    onEnded: { camera.setManualWhiteBalance(kelvin: Float(kelvinDraft), tint: Float(tintDraft)) }
                )
                sliderRow(
                    title: "Tint",
                    displayValue: String(format: "%+.0f", tintDraft),
                    id: "manual-tint-slider",
                    value: $tintDraft,
                    range: Double(controls.minimumTint)...Double(controls.maximumTint),
                    step: 1,
                    editing: $editingTint,
                    onEnded: { camera.setManualWhiteBalance(kelvin: Float(kelvinDraft), tint: Float(tintDraft)) }
                )
            } else if !controls.manualWhiteBalanceSupported {
                unsupportedText("Manual white balance is unavailable on this camera.")
            }
        }
        .accessibilityIdentifier("manual-white-balance-section")
    }

    private var focusSection: some View {
        controlSection(title: "Focus", subtitle: "Adjust focus manually. Return to Auto for moving subjects.") {
            modePicker(
                title: "Focus mode",
                mode: controls.focusMode,
                supported: controls.manualFocusSupported,
                autoID: "manual-focus-auto",
                manualID: "manual-focus-manual",
                autoAction: camera.setAutoFocus,
                manualAction: camera.lockCurrentFocus
            )

            if controls.manualFocusSupported && controls.focusMode == .manual {
                sliderRow(
                    title: "Lens position",
                    displayValue: String(format: "%.2f", focusDraft),
                    id: "manual-focus-slider",
                    value: $focusDraft,
                    range: Double(controls.minimumLensPosition)...Double(controls.maximumLensPosition),
                    step: 0.01,
                    editing: $editingFocus,
                    onEnded: { camera.setManualFocus(lensPosition: Float(focusDraft)) }
                )
            } else if !controls.manualFocusSupported {
                unsupportedText("Manual focus is unavailable on this camera.")
            }
        }
        .accessibilityIdentifier("manual-focus-section")
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Manual controls unavailable", systemImage: camera.availability == .simulator ? "iphone.slash" : "camera.metering.unknown")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
            Text(statusDescription)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityIdentifier("manual-controls-unavailable")
    }

    private var resetButton: some View {
        Button {
            HapticFeedback.play(.selection)
            camera.resetManualControlsToAuto()
        } label: {
            Label("Reset to Auto", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
        }
        .buttonStyle(.filmySecondary)
        .disabled(isApplying || !controls.isAnyManualModeEnabled)
        .accessibilityIdentifier("manual-controls-reset")
        .accessibilityHint("Restores automatic exposure, white balance, and focus")
    }

    private func controlSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text(subtitle)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    private func modePicker(
        title: String,
        mode: CameraManualControls.Mode,
        supported: Bool,
        autoID: String,
        manualID: String,
        autoAction: @escaping () -> Void,
        manualAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            modeButton(title: "Auto", selected: mode == .auto, enabled: true, id: autoID, action: autoAction)
            modeButton(title: "Manual", selected: mode == .manual, enabled: supported, id: manualID, action: manualAction)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func modeButton(
        title: String,
        selected: Bool,
        enabled: Bool,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticFeedback.play(.selection)
            action()
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
                .foregroundStyle(selected ? FilmyTheme.background : FilmyTheme.primary)
                .background(selected ? FilmyTheme.filmAccent : FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? FilmyTheme.filmAccent : FilmyTheme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isApplying)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func sliderRow(
        title: String,
        displayValue: String,
        id: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        editing: Binding<Bool>,
        onEnded: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(displayValue).monospacedDigit()
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)

            Slider(value: value, in: range, step: step, onEditingChanged: { active in
                editing.wrappedValue = active
                if !active { onEnded() }
            })
            .disabled(isApplying)
            .tint(FilmyTheme.filmAccent)
            .accessibilityIdentifier(id)
            .accessibilityLabel(title)
            .accessibilityValue(displayValue)
            .accessibilityAdjustableAction { direction in
                guard !isApplying else { return }
                let delta = max(step, (range.upperBound - range.lowerBound) / 100)
                switch direction {
                case .increment: value.wrappedValue = min(range.upperBound, value.wrappedValue + delta)
                case .decrement: value.wrappedValue = max(range.lowerBound, value.wrappedValue - delta)
                @unknown default: return
                }
                onEnded()
            }
        }
        .frame(minHeight: 58)
    }

    private func unsupportedText(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundStyle(FilmyTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func syncDraftsIfIdle() {
        guard !isApplying, !editingISO, !editingShutter, !editingKelvin, !editingTint, !editingFocus else { return }
        syncDrafts()
    }

    private func syncDrafts() {
        isoDraft = Double(controls.iso)
        shutterPosition = position(for: controls.exposureDurationSeconds)
        kelvinDraft = Double(controls.kelvin)
        tintDraft = Double(controls.tint)
        focusDraft = Double(controls.lensPosition)
    }

    private func duration(for position: Double) -> Double {
        let minimum = max(controls.minimumExposureDurationSeconds, Double.leastNormalMagnitude)
        let maximum = max(controls.maximumExposureDurationSeconds, minimum)
        let normalized = min(max(position, 0), 1)
        return exp(log(minimum) + ((log(maximum) - log(minimum)) * normalized))
    }

    private func position(for duration: Double) -> Double {
        let minimum = max(controls.minimumExposureDurationSeconds, Double.leastNormalMagnitude)
        let maximum = max(controls.maximumExposureDurationSeconds, minimum)
        guard maximum > minimum, duration.isFinite, duration > 0 else { return 0 }
        return min(max((log(duration) - log(minimum)) / (log(maximum) - log(minimum)), 0), 1)
    }

    private func shutterLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Auto" }
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(max(Int((1 / seconds).rounded()), 1))s"
    }
}
