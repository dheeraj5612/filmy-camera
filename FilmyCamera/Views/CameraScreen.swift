import SwiftUI
import UIKit

struct CameraScreen: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    let isCameraTabActive: Bool
    let onOpenGallery: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var recipeForDetail: FilmRecipe?
    @State private var focusPoint: CGPoint?
    @State private var focusNormalizedPoint: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                FilteredCameraPreview(camera: camera, recipe: viewModel.selectedRecipe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live camera preview")
                    .accessibilityValue(camera.isRunning ? "Showing the \(viewModel.selectedRecipe.name) look" : camera.statusMessage)
                    .accessibilityHint("Tap the preview to focus and expose the frame")
                    .accessibilityAction(named: "Focus and expose at center") {
                        let normalizedPoint = CGPoint(x: 0.5, y: 0.5)
                        camera.focus(at: normalizedPoint)
                        focusNormalizedPoint = normalizedPoint
                        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
                            focusPoint = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        }
                    }
                    .accessibilityIdentifier("camera-preview")
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            let normalizedPoint = normalizedFocusPoint(
                                for: value.location,
                                in: proxy.size
                            )
                            camera.focus(at: normalizedPoint)
                            focusNormalizedPoint = normalizedPoint
                            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
                                focusPoint = value.location
                            }
                        }
                    )
                    .onAppear { camera.updateOrientation(for: proxy.size) }
                    .onChange(of: proxy.size) { _, size in
                        camera.updateOrientation(for: size)
                    }
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
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
                    .task(id: focusPoint) {
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            self.focusPoint = nil
                        }
                    }
            }

            if !shouldShowCameraEmptyState {
                VStack(spacing: 8) {
                    if camera.flashAvailability != .unsupported {
                        FlashControl(
                            mode: camera.flashMode,
                            availability: camera.flashAvailability,
                            action: camera.cycleFlashMode
                        )
                    }

                    ZoomControl(value: camera.zoomFactor) { direction in
                        let delta: CGFloat = direction == .increment ? 0.5 : -0.5
                        camera.setZoom(camera.zoomFactor + delta)
                    }

                    ExposureControl(value: camera.exposureBias) { direction in
                        let delta: Float = direction == .increment ? (1.0 / 3.0) : -(1.0 / 3.0)
                        camera.setExposureBias(camera.exposureBias + delta)
                    }

                    if (focusPoint != nil || camera.isFocusExposureLocked), let focusNormalizedPoint {
                        FocusLockControl(isLocked: camera.isFocusExposureLocked) {
                            camera.toggleFocusExposureLock(at: focusNormalizedPoint)
                        }
                    }
                }
                .padding(.top, 76)
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
                ToastView(message: toastMessage, style: viewModel.toastStyle)
                    .padding(.top, 82)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: viewModel.toastMessage)
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
                    isSaving: viewModel.isSaving,
                    saveErrorMessage: viewModel.saveErrorMessage,
                    onSave: { viewModel.saveReview(photoLibrary: photoLibrary) },
                    onRetake: viewModel.discardReview,
                    onOpenSettings: openSystemSettings
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(viewModel.reviewImage != nil || viewModel.isSaving)
            }
        }
        .onAppear { updateCameraActivity() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, _ in updateCameraActivity() }
        .onChange(of: isCameraTabActive) { _, _ in updateCameraActivity() }
        .onChange(of: viewModel.reviewImage != nil) { _, hasReview in
            if hasReview {
                camera.stop()
            } else {
                updateCameraActivity()
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

            CameraStatusPill(
                isRunning: camera.isRunning,
                availability: camera.availability,
                message: camera.statusMessage
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filmy Camera. \(camera.statusMessage)")
    }

    private var shouldShowCameraEmptyState: Bool {
        !camera.isRunning
    }

    private var reviewPresentation: Binding<Bool> {
        Binding(
            get: { viewModel.reviewImage != nil },
            set: { isPresented in
                guard !viewModel.isSaving else { return }
                if !isPresented {
                    viewModel.discardReview()
                }
            }
        )
    }

    @ViewBuilder
    private var cameraPlaceholder: some View {
        switch camera.availability {
        case .interrupted:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                message: "The camera was interrupted. Resume when you are ready.",
                actionTitle: "Resume Camera",
                action: camera.start
            )
        case .needsRecovery:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                message: "The camera needs to be reopened before it can capture.",
                actionTitle: "Resume Camera",
                action: camera.start
            )
        case .unavailable:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                message: camera.statusMessage,
                actionTitle: "Resume Camera",
                action: camera.start
            )
        case .permissionDenied:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                actionTitle: "Open Settings",
                action: openSystemSettings
            )
        case .simulator:
            PreviewPlaceholder(
                isSimulator: true,
                recipe: viewModel.selectedRecipe
            )
        case .idle, .starting, .requestingPermission, .paused, .running:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                message: "Starting the camera…"
            )
        }
    }

    private func updateCameraActivity() {
        if viewModel.reviewImage != nil {
            camera.stop()
        } else if scenePhase == .active && isCameraTabActive {
            camera.start()
        } else {
            camera.stop()
        }
    }

    private func normalizedFocusPoint(
        for location: CGPoint,
        in viewSize: CGSize
    ) -> CGPoint {
        guard viewSize.width > 0,
              viewSize.height > 0,
              camera.previewFrameSize.width > 0,
              camera.previewFrameSize.height > 0 else {
            return CGPoint(
                x: min(max(location.x / max(viewSize.width, 1), 0), 1),
                y: min(max(location.y / max(viewSize.height, 1), 0), 1)
            )
        }

        let sourceSize = camera.previewFrameSize
        let scale = max(
            viewSize.width / sourceSize.width,
            viewSize.height / sourceSize.height
        )
        let displayedSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let cropOffset = CGPoint(
            x: (viewSize.width - displayedSize.width) / 2,
            y: (viewSize.height - displayedSize.height) / 2
        )

        // The Metal preview uses Core Image's bottom-left coordinate space,
        // while SwiftUI touch locations start at the top-left.
        let imageX = (location.x - cropOffset.x) / scale
        let imageY = (viewSize.height - location.y - cropOffset.y) / scale
        return CGPoint(
            x: min(max(imageX / sourceSize.width, 0), 1),
            y: min(max(1 - imageY / sourceSize.height, 0), 1)
        )
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.selectedRecipe.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                CameraActionButton(
                    systemName: "slider.horizontal.3",
                    title: "Tune",
                    accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                    action: { recipeForDetail = viewModel.selectedRecipe }
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            RecipePickerView(
                recipes: FilmRecipe.builtIns,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: { recipeForDetail = $0 }
            )
            .frame(height: 76)

            HStack(alignment: .center, spacing: 12) {
                CameraActionButton(
                    systemName: "square.grid.2x2",
                    title: "Roll",
                    accessibilityLabel: "Open roll",
                    action: onOpenGallery
                )
                .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .accessibilityHidden(true)

                    Text("Capture on iPhone")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
                .layoutPriority(1)
                .accessibilityElement(children: .ignore)
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
