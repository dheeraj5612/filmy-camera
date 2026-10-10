#if G7_APP
import Foundation
import SwiftUI

/// The G7X shooting deck keeps the physical camera metaphor in the chrome,
/// while every action still goes through CameraService's real controls.
struct G7CameraControlDeck: View {
    @ObservedObject var camera: CameraService
    @Binding var captureDelay: CaptureDelay
    @Binding var captureAspect: CaptureAspect
    @Binding var showGrid: Bool
    @Binding var showHistogram: Bool
    let isEnabled: Bool
    let onCapture: () -> Void
    let onOpenGallery: () -> Void
    let onOpenSettings: () -> Void

    @AppStorage("g7xDisplayMode") private var displayMode = 1
    @AppStorage(G7DateStampPreferences.enabledKey) private var dateStampEnabled = false
    @State private var isShowingQuickSettings = false

    private let green = FilmyTheme.accent
    private let ink = Color(red: 0.035, green: 0.035, blue: 0.035)

    var body: some View {
        VStack(spacing: 10) {
            statusStrip
            if isShowingQuickSettings {
                quickSettings
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            controlRow
        }
        .padding(12)
        .background(ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(green.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .animation(.easeOut(duration: 0.18), value: isShowingQuickSettings)
        .disabled(!isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("g7x-camera-control-deck")
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            Text("G7X")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(green)
                .accessibilityLabel("G7X Camera")
            Text(camera.availability == .running ? "READY" : camera.availability.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 4)
            statusValue("ISO", isoText)
            statusValue("SS", shutterText)
            statusValue("EV", String(format: "%+.1f", camera.exposureBias))
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("G7X camera status")
        .accessibilityValue("ISO \(isoText), shutter \(shutterText), exposure \(String(format: "%+.1f", camera.exposureBias)) EV")
    }

    private func statusValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 42, alignment: .trailing)
    }

    private var controlRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                deckButton("Q/SET", systemImage: "slider.horizontal.3", accent: isShowingQuickSettings) {
                    isShowingQuickSettings.toggle()
                }
                deckButton("DISP", systemImage: "rectangle.inset.filled", accent: false, action: cycleDisplay)
                exposureStepper
                deckButton("SET", systemImage: "gearshape", accent: false, action: onOpenSettings)
            }
            HStack(spacing: 8) {
                zoomButton("W", factor: camera.zoomFactor - 0.5)
                shutterButton
                zoomButton("T", factor: camera.zoomFactor + 0.5)
                deckButton("ROLL", systemImage: "photo.on.rectangle", accent: false, action: onOpenGallery)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var exposureStepper: some View {
        HStack(spacing: 3) {
            Button { setExposure(camera.exposureBias - (1.0 / 3.0)) } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Decrease exposure")
            Text("EV")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(green)
            Button { setExposure(camera.exposureBias + (1.0 / 3.0)) } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Increase exposure")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("g7x-exposure-dial")
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(String(format: "%+.1f EV", camera.exposureBias))
    }

    private var shutterButton: some View {
        Button(action: onCapture) {
            Circle()
                .stroke(green, lineWidth: 3)
                .frame(width: 42, height: 42)
                .overlay(Circle().fill(green.opacity(0.14)).padding(5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("g7x-shutter")
        .accessibilityLabel("Take photo")
    }

    private func deckButton(_ title: String, systemImage: String, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(accent ? ink : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(accent ? green : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func zoomButton(_ label: String, factor: CGFloat) -> some View {
        Button {
            camera.setZoom(min(max(factor, camera.minZoomFactor), camera.maxZoomFactor))
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 30, height: 44)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityIdentifier("g7x-zoom-\(label.lowercased())")
        .accessibilityLabel(label == "W" ? "Wider zoom" : "Tighter zoom")
        .accessibilityValue(String(format: "%.1fx", camera.zoomFactor))
    }

    private var quickSettings: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                settingButton("FLASH", value: camera.flashMode.title, systemImage: camera.flashMode.systemImageName) {
                    camera.cycleFlashMode()
                }
                settingButton("TIMER", value: captureDelay.title, systemImage: "timer") {
                    let all = CaptureDelay.allCases
                    captureDelay = all[(all.firstIndex(of: captureDelay)! + 1) % all.count]
                }
                settingButton("ASPECT", value: captureAspect.title, systemImage: "aspectratio") {
                    let all = CaptureAspect.allCases
                    captureAspect = all[(all.firstIndex(of: captureAspect)! + 1) % all.count]
                }
            }
            HStack(spacing: 8) {
                settingButton("GRID", value: showGrid ? "ON" : "OFF", systemImage: "grid") { showGrid.toggle() }
                settingButton("HISTOGRAM", value: showHistogram ? "ON" : "OFF", systemImage: "chart.bar.xaxis") { showHistogram.toggle() }
                settingButton("EXPOSURE", value: camera.manualControls.exposureMode == .manual ? "MANUAL" : "AUTO", systemImage: "camera.metering.center.weighted") {
                    camera.manualControls.exposureMode == .manual ? camera.setAutoExposure() : camera.lockCurrentExposure()
                }
            }
            settingButton("DATE STAMP", value: dateStampEnabled ? "ON" : "OFF", systemImage: "calendar.badge.clock") {
                dateStampEnabled.toggle()
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("g7x-quick-settings")
    }

    private func settingButton(_ label: String, value: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 8, weight: .black, design: .monospaced))
                Text(value).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(green)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var isoText: String {
        let controls = camera.manualControls
        guard controls.activeDeviceID != nil, controls.iso > 0 else { return "--" }
        return controls.exposureMode == .manual ? String(format: "%.0f", controls.iso) : "AUTO"
    }

    private var shutterText: String {
        let controls = camera.manualControls
        guard controls.activeDeviceID != nil, controls.exposureDurationSeconds > 0 else { return "--" }
        guard controls.exposureMode == .manual else { return "AUTO" }
        let seconds = controls.exposureDurationSeconds
        return seconds < 1 ? "1/\(Int((1 / seconds).rounded()))" : String(format: "%.1fs", seconds)
    }

    private func setExposure(_ value: Float) {
        camera.setExposureBias(CameraService.quantizedExposureBias(value))
    }

    private func cycleDisplay() {
        displayMode = (displayMode + 1) % 3
        switch displayMode {
        case 0:
            showGrid = false
            showHistogram = false
        case 1:
            showGrid = true
            showHistogram = false
        default:
            showGrid = true
            showHistogram = true
        }
    }
}

/// The landscape grip keeps the same controls in a narrow physical-camera
/// rail. It intentionally exposes the same real CameraService operations as
/// the portrait deck without squeezing a horizontal row into the rail.
struct G7CameraSideDeck: View {
    @ObservedObject var camera: CameraService
    @Binding var captureDelay: CaptureDelay
    @Binding var captureAspect: CaptureAspect
    @Binding var showGrid: Bool
    @Binding var showHistogram: Bool
    let isEnabled: Bool
    let onCapture: () -> Void
    let onOpenGallery: () -> Void
    let onOpenSettings: () -> Void

    @AppStorage("g7xDisplayMode") private var displayMode = 1
    @AppStorage(G7DateStampPreferences.enabledKey) private var dateStampEnabled = false
    @State private var isShowingQuickSettings = false

    private let green = FilmyTheme.accent
    private let ink = Color(red: 0.035, green: 0.035, blue: 0.035)

    var body: some View {
        VStack(spacing: 10) {
            Text("G7X")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(green)
                .accessibilityLabel("G7X Camera")
            Text(camera.availability == .running ? "READY" : camera.availability.rawValue.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            sideButton("Q/SET", active: isShowingQuickSettings, systemImage: "slider.horizontal.3") {
                isShowingQuickSettings.toggle()
            }
            if isShowingQuickSettings {
                VStack(spacing: 6) {
                    sideButton("FLASH", active: false, systemImage: "bolt.fill") { camera.cycleFlashMode() }
                    sideButton("TIMER", active: false, systemImage: "timer") { cycleDelay() }
                    sideButton("ASPECT", active: false, systemImage: "aspectratio") { cycleAspect() }
                    sideButton("GRID", active: showGrid, systemImage: "grid") { showGrid.toggle() }
                    sideButton("HIST", active: showHistogram, systemImage: "chart.bar.xaxis") { showHistogram.toggle() }
                    sideButton("EXPOSURE", active: camera.manualControls.exposureMode == .manual, systemImage: "camera.metering.center.weighted") {
                        camera.manualControls.exposureMode == .manual ? camera.setAutoExposure() : camera.lockCurrentExposure()
                    }
                    sideButton("DATE", active: dateStampEnabled, systemImage: "calendar.badge.clock") { dateStampEnabled.toggle() }
                }
                .transition(.opacity)
            }
            sideButton("DISP", active: displayMode > 0, systemImage: "rectangle.inset.filled") { cycleDisplay() }
            HStack(spacing: 5) {
                sideButton("EV−", active: false, systemImage: "minus") { setExposure(camera.exposureBias - (1.0 / 3.0)) }
                sideButton("EV+", active: false, systemImage: "plus") { setExposure(camera.exposureBias + (1.0 / 3.0)) }
            }
            HStack(spacing: 5) {
                sideButton("W", active: false, systemImage: "chevron.left") { zoom(by: -0.5) }
                sideButton("T", active: false, systemImage: "chevron.right") { zoom(by: 0.5) }
            }
            Button(action: onCapture) {
                Circle()
                    .stroke(green, lineWidth: 3)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().fill(green.opacity(0.14)).padding(6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("g7x-shutter")
            .accessibilityLabel("Take photo")
            sideButton("ROLL", active: false, systemImage: "photo.on.rectangle", action: onOpenGallery)
            sideButton("SET", active: false, systemImage: "gearshape", action: onOpenSettings)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(green.opacity(0.42), lineWidth: 1) }
        .disabled(!isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("g7x-camera-control-deck")
    }

    private func sideButton(_ title: String, active: Bool, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(active ? ink : .white)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(active ? green : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func cycleDelay() {
        let all = CaptureDelay.allCases
        guard let index = all.firstIndex(of: captureDelay) else { return }
        captureDelay = all[(index + 1) % all.count]
    }

    private func cycleAspect() {
        let all = CaptureAspect.allCases
        guard let index = all.firstIndex(of: captureAspect) else { return }
        captureAspect = all[(index + 1) % all.count]
    }

    private func cycleDisplay() {
        displayMode = (displayMode + 1) % 3
        showGrid = displayMode > 0
        showHistogram = displayMode > 1
    }

    private func setExposure(_ value: Float) {
        camera.setExposureBias(CameraService.quantizedExposureBias(value))
    }

    private func zoom(by delta: CGFloat) {
        camera.setZoom(min(max(camera.zoomFactor + delta, camera.minZoomFactor), camera.maxZoomFactor))
    }
}
#endif
