import SwiftUI

/// Explicit, labeled opt-in. Fixed width avoids changing viewfinder geometry
/// when the scene label changes. No preference is read or written here.
struct SceneAutoControl: View {
    @ObservedObject var camera: CameraService
    let isBusy: Bool

    private var enabled: Bool { camera.sceneAuto.isEnabled }
    private var held: Bool { camera.sceneAuto.phase == .held }
    private var unavailable: Bool { !camera.isRunning || camera.availability != .running }

    private var toggleTitle: String { enabled ? "Turn Scene Auto off" : "Enable Scene Auto" }
    private var toggleDetail: String {
        enabled ? "Restores your previous controls and flash." : "Adapts exposure, color and focus for this session. Your look stays."
    }
    private var holdTitle: String { held ? "Resume Scene Auto" : "Hold current settings" }
    private var holdDetail: String {
        held ? "Starts adapting to the scene again." : "Freezes the current settings until you resume or tap to focus."
    }

    var body: some View {
        Menu {
            Button {
                camera.setSceneAutoEnabled(!enabled)
            } label: {
                Text(toggleTitle)
                Text(toggleDetail)
            }
            .disabled(unavailable || isBusy || camera.manualControls.isApplying)
            .accessibilityIdentifier("scene-auto-toggle")

            if enabled {
                Button {
                    camera.setSceneAutoHeld(!held)
                } label: {
                    Text(holdTitle)
                    Text(holdDetail)
                }
                .disabled(isBusy || camera.manualControls.isApplying)
                .accessibilityIdentifier("scene-auto-hold")
                Text("Scene: \(camera.sceneAuto.scene.title)")
                if camera.sceneAuto.phase == .limited {
                    Text("This lens sets its own exposure. Scene Auto never switches lenses.")
                }
                Text("Flash stays off while Scene Auto is on.")
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
