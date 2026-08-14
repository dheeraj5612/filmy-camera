import Foundation
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var recipeForDetail: FilmRecipe?
    @State private var isShowingCameraControls = false
    @State private var focusPoint: CGPoint?
    @State private var focusNormalizedPoint: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isPinching = false

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

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.76), location: 0),
                    .init(color: Color.black.opacity(0.08), location: 0.23),
                    .init(color: Color.black.opacity(0.18), location: 0.58),
                    .init(color: Color.black.opacity(0.9), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if showGrid {
                RuleOfThirdsGrid()
                    .ignoresSafeArea()
            }

            ViewfinderFrame()
                .ignoresSafeArea()

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

            GeometryReader { proxy in
                cameraChrome(for: proxy.size)
            }

            if let toastMessage = viewModel.toastMessage {
                ToastView(message: toastMessage, style: viewModel.toastStyle)
                    .padding(.top, 88)
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
        .sheet(isPresented: $isShowingCameraControls) {
            cameraControlsSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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

    @ViewBuilder
    private func cameraChrome(for size: CGSize) -> some View {
        if size.width > size.height {
            landscapeCameraChrome
        } else {
            portraitCameraChrome
        }
    }

    private var portraitCameraChrome: some View {
        VStack(spacing: 0) {
            header

            if !shouldShowCameraEmptyState || isUITesting {
                cameraUtilityRail
            }

            Spacer(minLength: 12)

            if shouldShowCameraEmptyState {
                offlineControls
            } else {
                controls
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var landscapeCameraChrome: some View {
        VStack(spacing: 8) {
            header

            if !shouldShowCameraEmptyState || isUITesting {
                landscapeUtilityRail
            }

            Spacer(minLength: 4)
            landscapeBottomControls
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(FilmyTheme.accent.opacity(0.15))
                    Circle()
                        .stroke(FilmyTheme.accent.opacity(0.35), lineWidth: 1)
                        .padding(4)
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FilmyTheme.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("FILMY CAMERA")
                            .font(.system(.caption, design: .rounded).weight(.black))
                            .tracking(2.0)

                        Text(sessionLabel)
                            .font(.system(.caption2, design: .rounded).weight(.black))
                            .tracking(0.8)
                            .foregroundStyle(camera.isRunning ? FilmyTheme.mint : FilmyTheme.accent)
                    }
                        .foregroundStyle(.white)

                    Text(viewModel.selectedRecipe.name + "  ·  " + viewModel.selectedRecipe.descriptor)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            CameraStatusPill(
                isRunning: camera.isRunning,
                availability: camera.availability,
                message: camera.statusMessage
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Filmy Camera. \(viewModel.selectedRecipe.name). \(camera.statusMessage)"
        )
    }

    private var cameraUtilityRail: some View {
        cameraControlRail
    }

    private var landscapeUtilityRail: some View {
        cameraControlRail
    }

    private var cameraControlRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
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

                if camera.flashAvailability != .unsupported || hasHardwareSelection {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 1, height: 22)
                        .accessibilityHidden(true)
                }

                if camera.flashAvailability != .unsupported || hasHardwareSelection {
                    Button {
                        isShowingCameraControls = true
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                            .background(Color.black.opacity(0.46), in: Capsule())
                            .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("more-camera-controls")
                    .accessibilityLabel("More camera controls")
                    .accessibilityHint("Opens flash, camera, and lens controls")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera-utility-rail")
        .accessibilityHint("Swipe horizontally for additional camera controls")
    }

    private var shouldShowCameraEmptyState: Bool {
        !camera.isRunning
    }

    private var sessionLabel: String {
        switch camera.availability {
        case .running:
            return "LIVE"
        case .simulator:
            return "PREVIEW"
        case .permissionDenied:
            return "ACCESS OFF"
        case .requestingPermission:
            return "ACCESS NEEDED"
        case .paused:
            return "PAUSED"
        case .interrupted, .needsRecovery, .unavailable, .idle, .starting:
            return "STARTING"
        }
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private var hasHardwareSelection: Bool {
        camera.availableCameraPositions.count > 1 || camera.availableLenses.count > 1
    }

    @ViewBuilder
    private var hardwareSelectionControls: some View {
        VStack(spacing: 6) {
            if camera.availableCameraPositions.count > 1 {
                HStack(spacing: 2) {
                    ForEach(camera.availableCameraPositions, id: \.self) { position in
                        Button {
                            camera.setCameraPosition(position)
                        } label: {
                            Label(position.title, systemImage: position.systemImageName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    camera.cameraPosition == position
                                        ? FilmyTheme.background
                                        : FilmyTheme.primary
                                )
                                .frame(minWidth: 64, minHeight: FilmyTheme.minimumHitTarget)
                                .background(
                                    camera.cameraPosition == position
                                        ? FilmyTheme.accent
                                        : Color.black.opacity(0.46),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("camera-position-\(position.rawValue)")
                        .accessibilityLabel("Use \(position.title.lowercased()) camera")
                        .accessibilityValue(camera.cameraPosition == position ? "Selected" : "")
                        .accessibilityHint("Switches the active camera without changing your film recipe")
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.34), in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("camera-position-picker")
            }

            if camera.availableLenses.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(camera.availableLenses) { lens in
                            Button {
                                camera.setLens(id: lens.id)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(lens.title)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                    Text(lens.detail)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(
                                    camera.selectedLensID == lens.id
                                        ? FilmyTheme.background
                                        : FilmyTheme.primary
                                )
                                .frame(minWidth: 62, minHeight: FilmyTheme.minimumHitTarget)
                                .background(
                                    camera.selectedLensID == lens.id
                                        ? FilmyTheme.accent
                                        : Color.black.opacity(0.46),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("camera-lens-\(lens.id)")
                            .accessibilityLabel("Use \(lens.title) lens")
                            .accessibilityValue(
                                camera.selectedLensID == lens.id
                                    ? "Selected, \(lens.detail)"
                                    : lens.detail
                            )
                            .accessibilityHint("Selects the hardware lens and updates zoom")
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("camera-lens-picker")
            }
        }
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

    private var cameraControlsSheet: some View {
        NavigationStack {
            ZStack {
                FilmyTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeading(
                            eyebrow: "Camera controls",
                            title: "More ways to frame",
                            trailing: camera.cameraPosition.title
                        )

                        Text("Keep the viewfinder quiet. The controls you reach for less often live here.")
                            .font(FilmyTheme.bodyFont)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        GlassCard(padding: 15) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LIGHT")
                                    .font(.system(.caption2, design: .rounded).weight(.black))
                                    .tracking(1.2)
                                    .foregroundStyle(FilmyTheme.tertiary)

                                if camera.flashAvailability != .unsupported {
                                    FlashControl(
                                        mode: camera.flashMode,
                                        availability: camera.flashAvailability,
                                        action: camera.cycleFlashMode
                                    )
                                } else {
                                    Text("Flash is not available on this camera")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(FilmyTheme.secondary)
                                        .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                                }
                            }
                        }

                        if hasHardwareSelection {
                            GlassCard(padding: 15) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("HARDWARE")
                                        .font(.system(.caption2, design: .rounded).weight(.black))
                                        .tracking(1.2)
                                        .foregroundStyle(FilmyTheme.tertiary)

                                    hardwareSelectionControls
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 26)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingCameraControls = false
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                }
            }
            .toolbarBackground(FilmyTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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
        VStack(spacing: 14) {
            recipeHeader

            RecipePickerView(
                recipes: FilmRecipe.builtIns,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: { recipeForDetail = $0 }
            )
            // The rail cards are 86pt tall with 5pt vertical scroll padding;
            // reserve the full footprint so labels stay clear of the action plate.
            .frame(minHeight: 96)

            HStack(alignment: .center, spacing: 16) {
                CameraActionButton(
                    systemName: "square.grid.2x2",
                    title: "Roll",
                    accessibilityLabel: "Open roll",
                    action: onOpenGallery
                )

                Spacer(minLength: 0)

                CaptureButton(isCapturing: viewModel.isCapturing) {
                    if hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    viewModel.capture(camera: camera)
                }

                Spacer(minLength: 0)

                CameraActionButton(
                    systemName: "slider.horizontal.3",
                    title: "Tune",
                    accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                    action: { recipeForDetail = viewModel.selectedRecipe }
                )
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous))
        .background(FilmyTheme.plateGradient, in: RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.actionPlateRadius, style: .continuous)
                .stroke(Color.white.opacity(0.17), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 30, y: 14)
    }

    private var landscapeBottomControls: some View {
        Group {
            if shouldShowCameraEmptyState {
                HStack(spacing: 10) {
                    CameraActionButton(
                        systemName: "square.grid.2x2",
                        title: "Roll",
                        accessibilityLabel: "Open roll",
                        action: onOpenGallery
                    )

                    landscapeRecipeMenu

                    CameraActionButton(
                        systemName: "slider.horizontal.3",
                        title: "Tune",
                        accessibilityLabel: "Tune " + viewModel.selectedRecipe.name,
                        action: { recipeForDetail = viewModel.selectedRecipe }
                    )
                }
            } else {
                HStack(spacing: 10) {
                    CameraActionButton(
                        systemName: "square.grid.2x2",
                        title: "Roll",
                        accessibilityLabel: "Open roll",
                        action: onOpenGallery
                    )

                    landscapeRecipeMenu

                    CaptureButton(isCapturing: viewModel.isCapturing) {
                        if hapticsEnabled {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        viewModel.capture(camera: camera)
                    }

                    CameraActionButton(
                        systemName: "slider.horizontal.3",
                        title: "Tune",
                        accessibilityLabel: "Tune " + viewModel.selectedRecipe.name,
                        action: { recipeForDetail = viewModel.selectedRecipe }
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(FilmyTheme.plateGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 20, y: 8)
    }

    private var landscapeRecipeMenu: some View {
        Menu {
            ForEach(FilmRecipe.builtIns) { recipe in
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
        } label: {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOOK")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(FilmyTheme.accent)
                    Text(viewModel.selectedRecipe.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("landscape-recipe-picker")
        .accessibilityLabel("Choose film recipe")
        .accessibilityValue(viewModel.selectedRecipe.name)
        .layoutPriority(1)
    }

    private var recipeHeader: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(FilmyTheme.accent.opacity(0.13))
                Circle()
                    .stroke(FilmyTheme.accent.opacity(0.38), lineWidth: 1)
                    .padding(4)
                Image(systemName: "film.stack")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FilmyTheme.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 7 : 3) {
                Text("FILM STOCK")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(FilmyTheme.accent)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(viewModel.selectedRecipe.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    if viewModel.isCustomized(viewModel.selectedRecipe) {
                        Text("CUSTOM")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(FilmyTheme.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        .background(FilmyTheme.accent, in: Capsule())
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    Text(viewModel.selectedRecipe.base.uppercased())
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(viewModel.selectedRecipe.descriptor.uppercased())
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(viewModel.selectedRecipe.base.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(viewModel.selectedRecipe.descriptor.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
            }
        }
    }

    private var offlineControls: some View {
        VStack(spacing: 12) {
            recipeHeader

            RecipePickerView(
                recipes: FilmRecipe.builtIns,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: { recipeForDetail = $0 }
            )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        CameraActionButton(
                            systemName: "square.grid.2x2",
                            title: "Roll",
                            accessibilityLabel: "Open roll",
                            action: onOpenGallery
                        )
                        .frame(maxWidth: .infinity)

                        CameraActionButton(
                            systemName: "slider.horizontal.3",
                            title: "Tune",
                            accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                            action: { recipeForDetail = viewModel.selectedRecipe }
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Label("Capture is available on a physical iPhone", systemImage: "iphone")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                }
            } else {
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
                            .font(.system(size: 15, weight: .semibold))
                            .accessibilityHidden(true)

                        Text("Capture on iPhone")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
                    .layoutPriority(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Capture is available on a physical iPhone")

                    CameraActionButton(
                        systemName: "slider.horizontal.3",
                        title: "Tune",
                        accessibilityLabel: "Tune \(viewModel.selectedRecipe.name)",
                        action: { recipeForDetail = viewModel.selectedRecipe }
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, y: 12)
        // The camera chrome is a constrained overlay rather than a scrolling
        // document. Cap its visual scale one step below the largest Dynamic
        // Type sizes so every capture, Roll, and Tune action remains reachable.
        .dynamicTypeSize(.large ... .accessibility1)
    }
}

private struct ViewfinderFrame: View {
    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 22
            let length: CGFloat = 22
            let width = proxy.size.width
            let height = proxy.size.height

            Path { path in
                path.move(to: CGPoint(x: inset, y: inset + length))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset + length, y: inset))

                path.move(to: CGPoint(x: width - inset - length, y: inset))
                path.addLine(to: CGPoint(x: width - inset, y: inset))
                path.addLine(to: CGPoint(x: width - inset, y: inset + length))

                path.move(to: CGPoint(x: inset, y: height - inset - length))
                path.addLine(to: CGPoint(x: inset, y: height - inset))
                path.addLine(to: CGPoint(x: inset + length, y: height - inset))

                path.move(to: CGPoint(x: width - inset - length, y: height - inset))
                path.addLine(to: CGPoint(x: width - inset, y: height - inset))
                path.addLine(to: CGPoint(x: width - inset, y: height - inset - length))
            }
            .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                        camera.toggleCameraPosition()
                    } label: {
                        Label(camera.cameraPosition.title, systemImage: camera.cameraPosition.systemImageName)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(minHeight: FilmyTheme.minimumHitTarget)
                            .background(Color.black.opacity(0.46), in: Capsule())
                            .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("camera-switch-control")
                    .accessibilityLabel("Switch camera")
                    .accessibilityValue(camera.cameraPosition.title)
                    .accessibilityHint("Switches between the front and back cameras.")
                }

                if showsLensMenu {
                    Menu {
                        ForEach(camera.availableLenses) { lens in
                            Button {
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(minHeight: FilmyTheme.minimumHitTarget)
                            .background(Color.black.opacity(0.46), in: Capsule())
                            .overlay { Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1) }
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
