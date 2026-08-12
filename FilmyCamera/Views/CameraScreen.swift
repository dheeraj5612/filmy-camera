import SwiftUI
import UIKit

struct CameraScreen: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onOpenGallery: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var recipeForDetail: FilmRecipe?

    var body: some View {
        ZStack {
            FilteredCameraPreview(camera: camera, recipe: viewModel.selectedRecipe)
                .ignoresSafeArea()

            if shouldShowCameraEmptyState {
                PreviewPlaceholder(
                    isSimulator: camera.statusMessage.localizedCaseInsensitiveContains("Simulator"),
                    recipe: viewModel.selectedRecipe
                )
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [Color.black.opacity(0.64), .clear, Color.black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if showGrid {
                RuleOfThirdsGrid()
                    .ignoresSafeArea()
            }

            FocusReticle()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                controls
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if let toastMessage = viewModel.toastMessage {
                ToastView(message: toastMessage)
                    .padding(.top, 82)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.toastMessage)
        .sheet(item: $recipeForDetail) { recipe in
            RecipeDetailView(
                recipe: recipe,
                isSelected: viewModel.selectedRecipeID == recipe.id,
                onSelect: {
                    viewModel.select(recipe: recipe)
                    recipeForDetail = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                camera.start()
            case .background, .inactive:
                camera.stop()
            @unknown default:
                break
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FILMY CAMERA")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white)

                Text("Choose a feeling. Make a frame.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 8)

            CameraStatusPill(isRunning: camera.isRunning, message: camera.statusMessage)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filmy Camera. \(camera.statusMessage)")
    }

    private var shouldShowCameraEmptyState: Bool {
        guard !camera.isRunning else { return false }
        let message = camera.statusMessage.lowercased()
        return message.contains("simulator")
            || message.contains("disabled")
            || message.contains("required")
            || message.contains("unavailable")
            || message.contains("could not")
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOOKING THROUGH")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(viewModel.selectedRecipe.name)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    recipeForDetail = viewModel.selectedRecipe
                } label: {
                    HStack(spacing: 5) {
                        Text("Details")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View details for \(viewModel.selectedRecipe.name)")
            }

            RecipePickerView(
                recipes: FilmRecipe.builtIns,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: { recipeForDetail = $0 }
            )
            .frame(height: 80)

            HStack {
                FilmyIconButton(systemName: "square.grid.2x2", accessibilityLabel: "Open gallery", action: onOpenGallery)

                Spacer()

                CaptureButton(isCapturing: viewModel.isCapturing) {
                    if hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    viewModel.capture(camera: camera, photoLibrary: photoLibrary)
                }

                Spacer()

                FilmyIconButton(
                    systemName: "info",
                    accessibilityLabel: "About the selected recipe",
                    action: { recipeForDetail = viewModel.selectedRecipe }
                )
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 15)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }
}
