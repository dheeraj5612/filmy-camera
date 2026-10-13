import SwiftUI

/// Explicit, labeled opt-in. Fixed width avoids changing viewfinder geometry
/// when the scene label changes. No preference is read or written here.
struct SceneAutoControl: View {
    @ObservedObject var camera: CameraService
    let isBusy: Bool

    private var enabled: Bool { camera.sceneAuto.isEnabled }
    private var held: Bool { camera.sceneAuto.phase == .held }
    private var unavailable: Bool { !camera.isRunning || camera.availability != .running }

    var body: some View {
        Menu {
            Button(enabled ? "Turn Scene Auto Off" : "Enable Scene Auto") {
                camera.setSceneAutoEnabled(!enabled)
            }
            .disabled(unavailable || isBusy || camera.manualControls.isApplying)
            .accessibilityIdentifier("scene-auto-toggle")

            if enabled {
                Button(held ? "Resume Scene Auto" : "Hold Current Settings") {
                    camera.setSceneAutoHeld(!held)
                }
                .disabled(isBusy || camera.manualControls.isApplying)
                .accessibilityIdentifier("scene-auto-hold")
                Text("Scene: \(camera.sceneAuto.scene.title)")
                Text("Exposure, ISO/shutter, color, focus, and subtle tone/noise adjustments. Your film and framing stay yours.")
                if camera.sceneAuto.phase == .limited {
                    Text("This lens uses native auto exposure. Custom ISO/shutter control is unavailable; no lens will be switched automatically.")
                }
                Text("Flash stays off in Scene Auto. Turning Auto off restores your previous controls.")
            } else {
                Text("Optional for this session. Settles before adapting; ignores small fluctuations. Hold freezes the current settings.")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: held ? "lock.fill" : "camera.metering.matrix")
                Text(enabled ? camera.sceneAuto.title.uppercased() : "AUTO OFF")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(enabled ? FilmyTheme.accent : FilmyTheme.secondary)
            .padding(.horizontal, 9)
            .frame(width: 130, height: FilmyTheme.minimumHitTarget)
            .background(Color.black.opacity(0.68), in: Capsule())
            .overlay { Capsule().stroke(FilmyTheme.accent.opacity(enabled ? 0.36 : 0.12), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("scene-auto-control")
        .accessibilityLabel("Scene Auto")
        .accessibilityValue(camera.sceneAuto.title)
        .accessibilityHint("Optional scene-aware controls. Opens enable, hold, and off actions.")
    }
}
