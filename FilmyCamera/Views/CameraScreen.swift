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
    @State private var focusPoint: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                FilteredCameraPreview(camera: camera, recipe: viewModel.selectedRecipe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            let normalizedPoint = CGPoint(
                                x: value.location.x / max(proxy.size.width, 1),
                                y: value.location.y / max(proxy.size.height, 1)
                            )
                            camera.focus(at: normalizedPoint)
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                                focusPoint = value.location
                            }
                        }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                if abs(scale - 1) < 0.001 {
                                    pinchStartZoom = camera.zoomFactor
                                }
                                camera.setZoom(pinchStartZoom * scale)
                            }
                            .onEnded { _ in
                                pinchStartZoom = camera.zoomFactor
                            }
                    )
            }
            .ignoresSafeArea()

            if shouldShowCameraEmptyState {
                cameraPlaceholder
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

            if let focusPoint {
                FocusReticle()
                    .position(focusPoint)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }

            if camera.zoomFactor > 1.01 {
                Text("\(camera.zoomFactor, specifier: "%.1f")×")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.46), in: Capsule())
                    .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
                    .padding(.top, 76)
                    .accessibilityLabel("Zoom \(camera.zoomFactor, specifier: "%.1f") times")
            }

            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                if shouldShowCameraEmptyState {
                    offlineControls
                } else {
                    controls
                }
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
                originalRecipe: viewModel.originalRecipe(for: recipe.id),
                isSelected: viewModel.selectedRecipeID == recipe.id,
                onSelect: {
                    viewModel.select(recipe: recipe)
                    recipeForDetail = nil
                },
                onUpdate: viewModel.update,
                onReset: {
                    viewModel.reset(recipeID: recipe.id)
                    recipeForDetail = viewModel.originalRecipe(for: recipe.id)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: reviewPresentation) {
            if let image = viewModel.reviewImage, let recipe = viewModel.reviewRecipe {
                CaptureReviewView(
                    image: image,
                    recipe: recipe,
                    onSave: { viewModel.saveReview(photoLibrary: photoLibrary) },
                    onRetake: viewModel.discardReview
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
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

    private var reviewPresentation: Binding<Bool> {
        Binding(
            get: { viewModel.reviewImage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.discardReview()
                }
            }
        )
    }

    @ViewBuilder
    private var cameraPlaceholder: some View {
        let isSimulator = camera.statusMessage.localizedCaseInsensitiveContains("Simulator")
        let needsSettings = !isSimulator && camera.statusMessage.localizedCaseInsensitiveContains("access")

        if needsSettings {
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                actionTitle: "Open Settings",
                action: openSystemSettings
            )
        } else {
            PreviewPlaceholder(
                isSimulator: isSimulator,
                recipe: viewModel.selectedRecipe
            )
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOOKING THROUGH")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 7) {
                        Text(viewModel.selectedRecipe.name)
                        if viewModel.isCustomized(viewModel.selectedRecipe) {
                            Text("TUNED")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .tracking(0.7)
                                .foregroundStyle(FilmyTheme.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(FilmyTheme.accent, in: Capsule())
                        }
                    }
                    .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                CameraActionButton(
                    systemName: "slider.horizontal.3",
                    title: "Tune",
                    accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                    action: { recipeForDetail = viewModel.selectedRecipe }
                )
            }

            RecipePickerView(
                recipes: FilmRecipe.builtIns,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: { recipeForDetail = $0 }
            )
            .frame(height: 76)

            HStack {
                CameraActionButton(
                    systemName: "square.grid.2x2",
                    title: "Roll",
                    accessibilityLabel: "Open roll",
                    action: onOpenGallery
                )

                Spacer()

                CaptureButton(isCapturing: viewModel.isCapturing) {
                    if hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    viewModel.capture(camera: camera)
                }

                Spacer()

                CameraActionButton(
                    systemName: "camera.aperture",
                    title: "Look",
                    accessibilityLabel: "View \(viewModel.selectedRecipe.name) look details",
                    action: { recipeForDetail = viewModel.selectedRecipe }
                )
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var offlineControls: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PREVIEW MODE")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(viewModel.selectedRecipe.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                CameraActionButton(
                    systemName: "slider.horizontal.3",
                    title: "Tune",
                    accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                    action: { recipeForDetail = viewModel.selectedRecipe }
                )
            }

            RecipePickerView(
                recipes: FilmRecipe.builtIns,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: { recipeForDetail = $0 }
            )
            .frame(height: 76)

            HStack(spacing: 12) {
                CameraActionButton(
                    systemName: "square.grid.2x2",
                    title: "Roll",
                    accessibilityLabel: "Open roll",
                    action: onOpenGallery
                )

                Spacer(minLength: 8)

                Label("Capture on iPhone", systemImage: "iphone")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
                    .accessibilityLabel("Capture is available on a physical iPhone")
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }
}
