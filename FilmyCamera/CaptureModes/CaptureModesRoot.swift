import SwiftUI

/// Mount only one camera workspace. The legacy service acknowledges release on
/// its own serial queue before the new session may start, and vice versa on exit.
struct CaptureModesRoot: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var cameraViewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingModes = CaptureModesLaunch.peek() != nil
    @State private var initialMode = CaptureModesLaunch.peek() ?? .photo

    private var busy: Bool {
        cameraViewModel.isCapturing || cameraViewModel.isSaving || cameraViewModel.isImporting
            || cameraViewModel.reviewImage != nil
    }

    var body: some View {
        Group {
            if showingModes {
                CaptureModesScreen(camera: camera, recipe: cameraViewModel.selectedRecipe,
                                   recipes: cameraViewModel.recipes, mode: initialMode) {
                    showingModes = false
                }
            } else {
                ContentView(camera: camera, cameraViewModel: cameraViewModel, photoLibrary: photoLibrary)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Button {
                            guard !busy else { return }
                            initialMode = .photo
                            showingModes = true
                        } label: {
                            Label("Capture modes", systemImage: "camera.aperture")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(.black)
                        .disabled(busy)
                        .accessibilityIdentifier("open-capture-modes")
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CaptureModesLaunch.notification)) { _ in consumeLaunch() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { consumeLaunch() } }
        .onChange(of: busy) { _, value in if !value { consumeLaunch() } }
    }

    private func consumeLaunch() {
        // An active workspace consumes its own route, while an existing photo
        // operation is allowed to finish before a queued Siri request takes over.
        guard !showingModes, !busy, let requested = CaptureModesLaunch.take() else { return }
        initialMode = requested
        showingModes = true
    }
}
