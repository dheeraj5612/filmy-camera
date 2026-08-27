import Foundation
import SwiftUI
import UIKit

enum CameraActivityAction: Equatable {
    case start
    case stop
    case hold
}

enum CameraActivityPolicy {
    static func action(
        hasReview: Bool,
        sceneIsActive: Bool,
        isCameraTabActive: Bool,
        availability: CameraService.Availability
    ) -> CameraActivityAction {
        if hasReview || !sceneIsActive || !isCameraTabActive {
            return .stop
        }
        if availability == .interrupted {
            return .hold
        }
        return .start
    }
}

/// The viewfinder. Chrome is anchored to the edges and never boxed into
/// panels: a slim status bar on top, an optional tools strip, the film-strip
/// recipe rail, and a capture row with the Roll thumbnail, shutter, and Tune.
struct CameraScreen: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    let isCameraTabActive: Bool
    let onOpenGallery: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showGrid") private var showGrid = true
    @State private var recipeForDetail: FilmRecipe?
    @State private var isShowingTools: Bool
    @State private var focusPoint: CGPoint?
    @State private var focusNormalizedPoint: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isPinching = false

    init(
        camera: CameraService,
        viewModel: CameraViewModel,
        photoLibrary: PhotoLibraryService,
        isCameraTabActive: Bool,
        onOpenGallery: @escaping () -> Void
    ) {
        _camera = ObservedObject(wrappedValue: camera)
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _photoLibrary = ObservedObject(wrappedValue: photoLibrary)
        self.isCameraTabActive = isCameraTabActive
        self.onOpenGallery = onOpenGallery

        // The tools strip stays hidden until asked for so the viewfinder
        // opens quiet. UI tests that exercise exposure and zoom launch with
        // it open; the viewfinder-chrome preview launches with it closed so
        // the toggle itself can be verified.
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let isViewfinderPreview = arguments.contains("-ui-testing-viewfinder-chrome")
        _isShowingTools = State(initialValue: isUITesting && !isViewfinderPreview)
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                FilteredCameraPreview(camera: camera, recipe: viewModel.selectedRecipe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live camera preview")
                    .accessibilityValue(camera.isRunning ? "Showing the \(viewModel.selectedRecipe.name) look" : camera.statusMessage)
                    .accessibilityHint("Tap the preview to focus at that point. VoiceOver users can use the Focus and expose at center action.")
                    .accessibilityAction(named: "Focus and expose at center") {
                        HapticFeedback.play(.focus)
                        let normalizedPoint = CGPoint(x: 0.5, y: 0.5)
                        camera.focus(at: normalizedPoint)
                        focusNormalizedPoint = normalizedPoint
                        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
                            focusPoint = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        }
                    }
                    .accessibilityIdentifier(
                        shouldShowCameraEmptyState ? "camera-preview-unavailable" : "camera-preview"
                    )
                    .accessibilityHidden(shouldShowCameraEmptyState)
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            HapticFeedback.play(.focus)
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
                                if !isPinching {
                                    isPinching = true
                                    pinchStartZoom = camera.zoomFactor
                                }
                                camera.setZoom(pinchStartZoom * scale)
                            }
                            .onEnded { _ in
                                isPinching = false
                                pinchStartZoom = camera.zoomFactor
                            }
                    )
            }
            .ignoresSafeArea()

            if shouldShowCameraEmptyState {
                cameraPlaceholder
                    .ignoresSafeArea()
            }

            viewfinderScrim

            if showGrid && camera.isRunning {
                RuleOfThirdsGrid()
                    .ignoresSafeArea()
            }

            if let focusPoint {
                // The tap gesture reports locations in the full-screen
                // preview space (the GeometryReader ignores safe areas).
                // Expand the reticle into that same space so the ring lands
                // exactly where the user touched on every device and
                // orientation, and keep it hit-test transparent so a visible
                // reticle cannot swallow the next focus tap.
                FocusReticle()
                    .position(focusPoint)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.15).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .task(id: focusPoint) {
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            self.focusPoint = nil
                        }
                    }
            }

            GeometryReader { proxy in
                chrome(for: proxy.size)
                    .disabled(viewModel.isCapturing || viewModel.isImporting)
            }

            if let toastMessage = viewModel.toastMessage {
                ToastView(message: toastMessage, style: viewModel.toastStyle)
                    .padding(.top, 64)
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
            .presentationBackground(FilmyTheme.background)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: reviewPresentation) {
            if let image = viewModel.reviewImage, let recipe = viewModel.reviewRecipe {
                CaptureReviewView(
                    image: image,
                    recipe: recipe,
                    source: viewModel.reviewSource,
                    isSaving: viewModel.isSaving,
                    saveErrorMessage: viewModel.saveErrorMessage,
                    onSave: { viewModel.saveReview(photoLibrary: photoLibrary) },
                    onRetake: viewModel.discardReview,
                    onOpenSettings: openSystemSettings
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(FilmyTheme.background)
                .interactiveDismissDisabled(viewModel.reviewImage != nil || viewModel.isSaving)
            }
        }
        .onAppear {
            updateCameraActivity()
            // Keeps the Roll thumbnail in the capture row current without
            // prompting: refresh only reads when access was already granted.
            photoLibrary.refresh()
        }
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
        .onChange(of: viewModel.isCapturing) { _, isCapturing in
            guard !isCapturing, viewModel.reviewImage == nil else { return }
            updateCameraActivity()
        }
        // The simulator placeholder contains a renderer-backed swatch with a
        // non-zero ideal size. Keep that child from expanding the camera shell
        // beyond the window proposal and shifting the chrome offscreen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout

    private var isCompactChrome: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    /// The G7 X profile is a camera mode rather than a film stock: its
    /// header reads "camera profile" and its capture controls stay one tap
    /// away in the capture path instead of behind the tools toggle.
    private var isCompactDigitalMode: Bool {
        viewModel.selectedRecipe.filmBase == .compactDigital
    }

    private var recipeEyebrow: String {
        isCompactDigitalMode ? "CAMERA PROFILE" : "RECIPE"
    }

    private func chrome(for size: CGSize) -> some View {
        let isLandscape = size.width > size.height

        return VStack(spacing: 0) {
            topBar

            Spacer(minLength: 8)

            bottomStack(isLandscape: isLandscape, width: size.width)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // The chrome is a constrained overlay rather than a scrolling document.
        // Cap its visual scale one step below the largest Dynamic Type sizes
        // so every capture, Roll, and Tune action remains reachable.
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    private var viewfinderScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: 150)

            Spacer(minLength: 0)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.42), location: 0.42),
                    .init(color: Color.black.opacity(0.9), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: 360)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: 10) {
                if camera.isRunning && camera.flashAvailability != .unsupported {
                    FlashControl(
                        mode: camera.flashMode,
                        availability: camera.flashAvailability,
                        action: camera.cycleFlashMode
                    )
                }

                Spacer(minLength: 0)

                if camera.isRunning || isViewfinderChromePreview {
                    toolsToggle
                }
            }

            CameraStatusPill(
                isRunning: camera.isRunning,
                availability: camera.availability,
                message: camera.statusMessage
            )
        }
    }

    private var toolsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                isShowingTools.toggle()
            }
        } label: {
            Image(systemName: isShowingTools ? "chevron.down" : "slider.horizontal.3")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isShowingTools ? FilmyTheme.accent : .white)
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("camera-chrome-toggle")
        .accessibilityLabel(isShowingTools ? "Hide camera controls" : "Show camera controls")
        .accessibilityHint(
            isShowingTools
                ? "Return to the viewfinder-first camera layout"
                : "Reveal exposure, zoom, and camera controls"
        )
    }

    @ViewBuilder
    private func bottomStack(isLandscape: Bool, width: CGFloat) -> some View {
        if isLandscape {
            VStack(spacing: 10) {
                if isShowingTools {
                    toolStrip(minWidth: width - 32)
                } else if isCompactDigitalMode, !shouldShowCameraEmptyState {
                    compactDigitalQuickRail
                }

                HStack(alignment: .center, spacing: 14) {
                    recipeMenu
                        .frame(maxWidth: 320)

                    Spacer(minLength: 8)

                    captureRow
                }
            }
        } else {
            VStack(spacing: 10) {
                if isShowingTools {
                    toolStrip(minWidth: width - 32)
                } else if isCompactDigitalMode, !shouldShowCameraEmptyState || isViewfinderChromePreview {
                    compactDigitalQuickRail
                }

                recipeHeader

                RecipePickerView(
                    recipes: viewModel.recipes,
                    selectedRecipeID: $viewModel.selectedRecipeID,
                    onOpenDetail: { recipeForDetail = viewModel.recipe(for: $0.id) },
                    compact: isCompactChrome
                )

                captureRow
                    .frame(maxWidth: FilmyLayout.dockMaxWidth)
                    .padding(.top, 2)
            }
        }
    }

    private var recipeHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Eyebrow(text: recipeEyebrow, color: FilmyTheme.accent)

            Text(viewModel.selectedRecipe.name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if viewModel.isCustomized(viewModel.selectedRecipe) {
                FilmyTag(text: "EDITED", filled: false)
            }

            Spacer(minLength: 8)

            if !isCompactChrome {
                Text(viewModel.selectedRecipe.descriptor)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }

    private var captureRow: some View {
        HStack(alignment: .center, spacing: 12) {
            rollButton

            Spacer(minLength: 0)

            captureControl

            Spacer(minLength: 0)

            CameraActionButton(
                systemName: "slider.horizontal.3",
                title: "Tune",
                accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                action: { recipeForDetail = viewModel.selectedRecipe }
            )
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var captureControl: some View {
        if isViewfinderChromePreview {
            CaptureButton(isCapturing: viewModel.isCapturing, isEnabled: false) {}
        } else if shouldShowCameraEmptyState {
            captureNotice
        } else {
            CaptureButton(isCapturing: viewModel.isCapturing, action: capture)
        }
    }

    private var captureNotice: some View {
        Label("Capture is available on a physical device", systemImage: "iphone")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
            .accessibilityElement(children: .combine)
    }

    private var rollButton: some View {
        Button(action: onOpenGallery) {
            VStack(spacing: 6) {
                RollThumbnail(asset: photoLibrary.galleryAssets.first, photoLibrary: photoLibrary)
                    .frame(width: 54, height: 54)

                Text("Roll")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(minWidth: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Open roll")
        .accessibilityHint("Shows the frames you have kept")
    }

    private func toolStrip(minWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ZoomControl(
                    value: camera.zoomFactor,
                    onAdjust: { direction in
                        let delta: CGFloat = direction == .increment ? 0.5 : -0.5
                        camera.setZoom(camera.zoomFactor + delta)
                    },
                    onSelect: camera.setZoom
                )

                ExposureControl(value: camera.exposureBias) { direction in
                    let delta: Float = direction == .increment ? (1.0 / 3.0) : -(1.0 / 3.0)
                    camera.setExposureBias(camera.exposureBias + delta)
                }

                if (focusPoint != nil || camera.isFocusExposureLocked), let focusNormalizedPoint {
                    FocusLockControl(isLocked: camera.isFocusExposureLocked) {
                        camera.toggleFocusExposureLock(at: focusNormalizedPoint)
                    }
                }

                if hasHardwareSelection {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 22)
                        .accessibilityHidden(true)

                    CameraHardwareControls(camera: camera)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(minWidth: max(minWidth, 0))
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera-utility-rail")
        .accessibilityHint("Swipe horizontally for additional camera controls")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Compact-camera mode keeps its most useful controls in the capture
    /// path. The viewfinder stays dominant while zoom, exposure, the grid,
    /// and camera switching remain one tap away.
    private var compactDigitalQuickRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ZoomControl(
                    value: camera.zoomFactor,
                    onAdjust: { direction in
                        let delta: CGFloat = direction == .increment ? 0.5 : -0.5
                        camera.setZoom(camera.zoomFactor + delta)
                    },
                    onSelect: camera.setZoom
                )

                ExposureControl(value: camera.exposureBias) { direction in
                    let delta: Float = direction == .increment ? (1.0 / 3.0) : -(1.0 / 3.0)
                    camera.setExposureBias(camera.exposureBias + delta)
                }

                Button {
                    HapticFeedback.play(.selection)
                    showGrid.toggle()
                } label: {
                    Image(systemName: showGrid ? "grid" : "grid.circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(showGrid ? FilmyTheme.background : .white)
                        .frame(width: FilmyTheme.toolControlHeight, height: FilmyTheme.toolControlHeight)
                        .background {
                            if showGrid {
                                Circle().fill(FilmyTheme.accent)
                            } else {
                                ChromeShapeBackground(shape: Circle())
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("g7x-grid-control")
                .accessibilityLabel(showGrid ? "Hide composition grid" : "Show composition grid")
                .accessibilityValue(showGrid ? "On" : "Off")

                if hasHardwareSelection {
                    CameraHardwareControls(camera: camera)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("g7x-capture-controls")
        .accessibilityLabel("G7 X quick capture controls")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var recipeMenu: some View {
        Menu {
            Section(isCompactDigitalMode ? "Camera profile" : "Recipe") {
                ForEach(viewModel.recipes) { recipe in
                    Button {
                        viewModel.select(recipe: recipe)
                    } label: {
                        if recipe.id == viewModel.selectedRecipeID {
                            Label(recipe.name, systemImage: "checkmark")
                        } else {
                            Text(recipe.name)
                        }
                    }
                }
            }

            Divider()

            Button("Tune \(viewModel.selectedRecipe.name)") {
                recipeForDetail = viewModel.selectedRecipe
            }
        } label: {
            HStack(spacing: 10) {
                RecipeSwatch(
                    recipe: viewModel.selectedRecipe,
                    isSelected: true,
                    compact: true,
                    showsLabel: false
                )
                .frame(width: 46, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: recipeEyebrow, color: FilmyTheme.accent)

                    Text(viewModel.selectedRecipe.name)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .viewfinderChrome(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recipe-menu")
        .accessibilityLabel("Choose film recipe")
        .accessibilityValue(viewModel.selectedRecipe.name)
    }

    // MARK: - State

    private var shouldShowCameraEmptyState: Bool {
        !camera.isRunning
    }

    private var isViewfinderChromePreview: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-viewfinder-chrome")
    }

    private var hasHardwareSelection: Bool {
        camera.availableCameraPositions.count > 1 || camera.availableLenses.count > 1
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

    // MARK: - Actions

    private func capture() {
        viewModel.capture(camera: camera)
    }

    private func updateCameraActivity() {
        let action = CameraActivityPolicy.action(
            hasReview: viewModel.reviewImage != nil,
            sceneIsActive: scenePhase == .active,
            isCameraTabActive: isCameraTabActive,
            availability: camera.availability
        )

        switch action {
        case .start:
            camera.start()
        case .stop:
            camera.stop()
        case .hold:
            break
        }
    }

    private func normalizedFocusPoint(
        for location: CGPoint,
        in viewSize: CGSize
    ) -> CGPoint {
        let rotatedPreviewPoint: CGPoint
        if viewSize.width > 0,
           viewSize.height > 0,
           camera.previewFrameSize.width > 0,
           camera.previewFrameSize.height > 0 {
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

            // Core Image uses bottom-left coordinates while SwiftUI touch
            // locations start at the top-left. Resolve aspect-fill first in
            // the rotated preview buffer, then undo rotation and mirroring.
            let imageX = (location.x - cropOffset.x) / scale
            let imageY = (viewSize.height - location.y - cropOffset.y) / scale
            rotatedPreviewPoint = CGPoint(
                x: min(max(imageX / sourceSize.width, 0), 1),
                y: min(max(1 - imageY / sourceSize.height, 0), 1)
            )
        } else {
            rotatedPreviewPoint = CGPoint(
                x: min(max(location.x / max(viewSize.width, 1), 0), 1),
                y: min(max(location.y / max(viewSize.height, 1), 0), 1)
            )
        }

        return CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: rotatedPreviewPoint,
            rotationAngle: camera.previewRotationAngle,
            mirrored: camera.previewMirrored
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// The most recent kept frame, shown inside the Roll button the way a camera
/// shows its last exposure. Falls back to a grid glyph until a frame exists
/// or while Photos access is unavailable.
private struct RollThumbnail: View {
    let asset: PhotoLibraryGalleryAsset?
    @ObservedObject var photoLibrary: PhotoLibraryService

    @State private var image: UIImage?

    private var requestKey: PhotoLibraryImageRequestKey? {
        guard let asset else { return nil }
        return PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: asset.assetIdentifier,
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        )
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ChromeShapeBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(image == nil ? 0 : 0.55), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
        .task(id: requestKey) {
            image = nil
            guard let asset,
                  PhotoLibraryGalleryImagePolicy.canLoad(
                      isPhotosAsset: asset.isPhotosAsset,
                      authorizationStatus: photoLibrary.authorizationStatus
                  ) else {
                return
            }

            let loadedImage = await photoLibrary.image(
                for: asset,
                targetSize: CGSize(width: 180, height: 180)
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}

private struct CameraHardwareControls: View {
    @ObservedObject var camera: CameraService

    private var showsCameraSwitch: Bool {
        camera.availableCameraPositions.count > 1
    }

    private var showsLensMenu: Bool {
        camera.availableLenses.count > 1
    }

    var body: some View {
        if showsCameraSwitch || showsLensMenu {
            HStack(spacing: 8) {
                if showsCameraSwitch {
                    Button {
                        HapticFeedback.play(.selection)
                        camera.toggleCameraPosition()
                    } label: {
                        Label(camera.cameraPosition.title, systemImage: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: FilmyTheme.toolControlHeight)
                            .viewfinderCapsule()
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("camera-switch-control")
                    .accessibilityLabel("Switch camera")
                    .accessibilityValue(camera.cameraPosition.title)
                    .accessibilityHint("Switches between the front and back cameras.")
                }

                if showsLensMenu {
                    Menu {
                        ForEach(camera.availableLenses) { lens in
                            Button {
                                HapticFeedback.play(.selection)
                                camera.setLens(id: lens.id)
                            } label: {
                                if lens.id == camera.selectedLensID {
                                    Label("\(lens.title) · \(lens.detail)", systemImage: "checkmark")
                                } else {
                                    Text("\(lens.title) · \(lens.detail)")
                                }
                            }
                        }
                    } label: {
                        Label(selectedLensTitle, systemImage: "camera.aperture")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: FilmyTheme.toolControlHeight)
                            .viewfinderCapsule()
                    }
                    .accessibilityIdentifier("lens-menu-control")
                    .accessibilityLabel("Choose lens")
                    .accessibilityValue(selectedLensTitle)
                    .accessibilityHint("Choose a lens on the active camera.")
                }
            }
        }
    }

    private var selectedLensTitle: String {
        camera.availableLenses.first(where: { $0.id == camera.selectedLensID })?.title ?? "Lens"
    }
}
