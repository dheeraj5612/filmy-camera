import Foundation
import AVKit
import SwiftUI
import UIKit

enum CameraActivityAction: Equatable {
    case start
    case stop
    /// Keep the session warm for a short grace period so a quick return
    /// (Retake, back from the Roll or Settings) shows a live viewfinder at
    /// once; the session is released if the user stays away.
    case stopAfterGrace
    case hold
}

enum CameraActivityPolicy {
    /// How long the session stays warm while a captured frame is under review,
    /// so Retake can return to the finder without a session restart.
    static let reviewGracePeriod: TimeInterval = 45

    /// A short return window for Roll, Settings, and other inactive camera
    /// destinations. The viewfinder is no longer consuming frames there, so
    /// keeping the capture session warm for the review window wastes power.
    static let inactiveGracePeriod: TimeInterval = 8

    /// Kept as the review grace alias for existing policy clients and tests.
    static let gracePeriod = reviewGracePeriod

    static func deferredStopDelay(hasReview: Bool) -> TimeInterval {
        hasReview ? reviewGracePeriod : inactiveGracePeriod
    }

    /// Unit tests run inside this app as their host. They must own the camera
    /// themselves (hardware tests start their own session), so the host UI
    /// leaves the device alone. UI tests launch the app as a separate
    /// process without this variable and are unaffected.
    static let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func action(
        hasReview: Bool,
        sceneIsActive: Bool,
        isCameraTabActive: Bool,
        availability: CameraService.Availability
    ) -> CameraActivityAction {
        if !sceneIsActive {
            return .stop
        }
        if hasReview || !isCameraTabActive {
            return .stopAfterGrace
        }
        if availability == .interrupted {
            return .hold
        }
        return .start
    }
}

/// Geometry of the letterboxed viewfinder.
///
/// The frame is a 4:3 picture on a black camera body, the way the system
/// Camera, Halide, and most iPhone photography apps present it. Controls live
/// on the bands above and below, never on top of the image, except the zoom
/// presets and the optional tool strip along its bottom edge.
enum ViewfinderLayout {
    /// Width divided by height.
    static let portraitAspect: CGFloat = 3.0 / 4.0
    static let landscapeAspect: CGFloat = 4.0 / 3.0

    /// When a strict 4:3 frame would fall below this share of the available
    /// width, it keeps its side bands (iPad). Otherwise it stretches to the
    /// full width and accepts a slight crop so iPhone keeps an edge-to-edge
    /// frame. The saved still follows the same crop, so what is framed here
    /// is what is kept.
    static let fullWidthThreshold: CGFloat = 0.82

    static func size(available: CGSize, isLandscape: Bool, aspect: CaptureAspect = .viewfinder) -> CGSize {
        guard available.width.isFinite, available.height.isFinite else { return .zero }
        if let ratio = aspect.ratio(isLandscape: isLandscape), available.width > 0, available.height > 0 {
            let width = min(available.width, available.height * CGFloat(ratio))
            return CGSize(width: width, height: width / CGFloat(ratio))
        }
        guard available.width > 0, available.height > 0 else { return .zero }
        let aspect = isLandscape ? landscapeAspect : portraitAspect
        let idealHeight = available.width / aspect
        if idealHeight <= available.height {
            return CGSize(width: available.width, height: idealHeight)
        }
        let fittedWidth = available.height * aspect
        if fittedWidth >= available.width * fullWidthThreshold {
            return CGSize(width: available.width, height: available.height)
        }
        return CGSize(width: fittedWidth, height: available.height)
    }
}

/// The viewfinder and its capture controls. The picture keeps a stable frame
/// while look and camera-tool drawers float above it. Wide layouts put the
/// primary controls in an edge column; compact layouts keep them below the
/// frame within thumb reach.
struct CameraScreen: View {
    @ObservedObject var camera: CameraService
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    let isCameraTabActive: Bool
    let onOpenGallery: () -> Void
    let onOpenSettings: () -> Void
    let onImportPhoto: () -> Void
    let isImportInProgress: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showGrid") private var showGrid = true
    @StateObject private var livePreviews = LiveRecipePreviewStore()
    @StateObject private var countdown = CaptureCountdown()
    @StateObject private var assists = CompositionAssistStore()
    @State private var isShowingCaptureSetup = false
    @AppStorage("captureDelay") private var captureDelay = CaptureDelay.off
    @AppStorage("captureAspect") private var captureAspect = CaptureAspect.viewfinder
    @AppStorage("compositionGuide") private var compositionGuide = CompositionGuide.thirds
    @AppStorage("showHistogram") private var showHistogram = false
    @AppStorage("showZebras") private var showZebras = false
    @AppStorage("showFocusPeaking") private var showFocusPeaking = false
    @AppStorage("showHorizonLevel") private var showHorizonLevel = false
    @State private var recipeForDetail: FilmRecipe?
    @State private var isShowingTools: Bool
    @State private var isShowingManualControls = false
    @State private var isShowingLookDrawer = false
    @State private var isShowingLookLibrary = false
    @State private var focusPoint: CGPoint?
    @State private var focusNormalizedPoint: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isPinching = false
    @State private var isShutterBlinking = false

    init(
        camera: CameraService,
        viewModel: CameraViewModel,
        photoLibrary: PhotoLibraryService,
        isCameraTabActive: Bool,
        onOpenGallery: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onImportPhoto: @escaping () -> Void,
        isImportInProgress: Bool = false
    ) {
        _camera = ObservedObject(wrappedValue: camera)
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _photoLibrary = ObservedObject(wrappedValue: photoLibrary)
        self.isCameraTabActive = isCameraTabActive
        self.onOpenGallery = onOpenGallery
        self.onOpenSettings = onOpenSettings
        self.onImportPhoto = onImportPhoto
        self.isImportInProgress = isImportInProgress

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
        ZStack {
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height
                let usesEdgeControlColumn = isLandscape || proxy.size.width >= 720

                Group {
                    if usesEdgeControlColumn {
                        edgeControlShell(
                            isLandscape: isLandscape,
                            availableHeight: proxy.size.height
                        )
                    } else {
                        portraitShell(availableHeight: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The chrome is a constrained shell rather than a scrolling
                // document. Cap its visual scale one step below the largest
                // Dynamic Type sizes so every capture, Roll, and Tune action
                // remains reachable.
                .dynamicTypeSize(.xSmall ... .accessibility1)
            }
            .background(FilmyTheme.viewfinderBand.ignoresSafeArea())
            .overlay(alignment: .top) {
                if let toastMessage = viewModel.toastMessage {
                    ToastView(message: toastMessage, style: viewModel.toastStyle)
                        .padding(.top, 56)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: viewModel.toastMessage)
            .allowsHitTesting(!isReviewing && !countdown.state.isActive)
            .disabled(isReviewing || countdown.state.isActive)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(isReviewing || countdown.state.isActive)

            if countdown.state.isActive { countdownOverlay.zIndex(2) }

            if let image = viewModel.reviewImage, let recipe = viewModel.reviewRecipe {
                CaptureReviewView(
                    image: image,
                    recipe: recipe,
                    source: viewModel.reviewSource,
                    isFullResolution: viewModel.reviewIsFullResolution,
                    flashFired: viewModel.reviewFlashFired,
                    isSaving: viewModel.isSaving,
                    saveErrorMessage: viewModel.saveErrorMessage,
                    saveErrorRequiresSettings: viewModel.saveErrorRequiresSettings,
                    availableRecipes: viewModel.recipes,
                    pendingReviewRecipeID: viewModel.pendingReviewRecipeID,
                    finish: viewModel.reviewFinish,
                    pendingReviewFinish: viewModel.pendingReviewFinish,
                    isRenderingReview: viewModel.isRenderingReview,
                    reviewRenderErrorMessage: viewModel.reviewRenderErrorMessage,
                    reviewOriginalImage: viewModel.reviewOriginalImage,
                    isPreparingReviewOriginal: viewModel.isPreparingReviewOriginal,
                    onSave: { viewModel.saveReview(photoLibrary: photoLibrary) },
                    onRetake: viewModel.discardReview,
                    onOpenSettings: openSystemSettings,
                    onApplyReviewRecipe: viewModel.applyReviewRecipe,
                    onPrepareReviewOriginal: viewModel.prepareReviewOriginal,
                    onApplyReviewFinish: viewModel.applyReviewFinish
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
            }
        }
        .modifier(CameraHardwareShutterModifier(enabled: canTriggerShutter, action: capture))
        .onChange(of: assistOptions, initial: true) { _, _ in updateCompositionAssists() }
        .onChange(of: isCameraVisibleForAssists, initial: true) { _, visible in
            if !visible { countdown.cancel() }
            updateCompositionAssists()
        }
        .onChange(of: captureAspect) { _, _ in countdown.cancel(); assists.stop(); updateCompositionAssists() }
        .sheet(isPresented: $isShowingCaptureSetup) {
            CaptureSetupView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FilmyTheme.background)
        }
        // Visible recipe choices render over the live scene. When the drawer
        // and detail are both closed, their frame consumer is detached so the
        // renderer does no hidden thumbnail work.
        .environment(\.recipePreviewScene, livePreviews.scene)
        .onChange(of: camera.isRunning, initial: true) { _, _ in
            updateLiveRecipePreviews()
        }
        .onChange(of: isShowingLookDrawer) { _, _ in
            updateLiveRecipePreviews()
        }
        .onChange(of: recipeForDetail?.id) { _, _ in
            updateLiveRecipePreviews()
        }
        .onChange(of: isShowingLookLibrary) { _, _ in
            updateLiveRecipePreviews()
        }
        .sheet(isPresented: $isShowingLookLibrary) {
            LookLibraryView(
                recipes: viewModel.recipes,
                selectedRecipeID: viewModel.selectedRecipeID,
                onSelect: { recipe in
                    viewModel.select(recipe: recipe)
                    isShowingLookLibrary = false
                    isShowingLookDrawer = false
                },
                onClose: { isShowingLookLibrary = false }
            )
            // Full-library thumbnails use the cached sample, not a second
            // continuously rendered live viewfinder behind a modal sheet.
            .environment(\.recipePreviewScene, nil)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(FilmyTheme.background)
            .presentationCornerRadius(28)
        }
        .sheet(item: $recipeForDetail) { recipe in
            RecipeDetailView(
                recipe: recipe,
                originalRecipe: viewModel.originalRecipe(for: recipe.id),
                isSelected: viewModel.selectedRecipeID == recipe.id,
                onSelect: {
                    viewModel.select(recipe: recipe)
                    recipeForDetail = nil
                },
                // The presenter owns closing the editor. Cancelling never
                // commits its local draft or selects a different recipe.
                onCancel: { recipeForDetail = nil },
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
        .sheet(isPresented: $isShowingManualControls) {
            ManualCameraControlsView(camera: camera)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FilmyTheme.background)
        }
        .onAppear {
            updateCameraActivity()
            updateIdleTimer()
            // Keeps the Roll thumbnail in the capture row current without
            // prompting: refresh only reads when access was already granted.
            photoLibrary.refresh()
        }
        // Leaving the tab keeps the session warm briefly so coming back is
        // instant; the scene phase handler still stops it when the app leaves
        // the foreground.
        .onDisappear {
            // The session may stay warm, but nothing here consumes frames any
            // more: unregister the swatch handler before this view is released.
            countdown.cancel()
            assists.stop()
            livePreviews.detach()
            livePreviews.clear()
            camera.stop(after: CameraActivityPolicy.inactiveGracePeriod)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, _ in
            updateCameraActivity()
            updateIdleTimer()
        }
        .onChange(of: isCameraTabActive) { _, _ in
            updateCameraActivity()
            updateIdleTimer()
        }
        .onChange(of: viewModel.reviewImage != nil) { _, hasReview in
            if hasReview {
                camera.setFrameDeliveryPaused(true)
                livePreviews.detach()
                livePreviews.clear()
            }
            updateCameraActivity()
            updateIdleTimer()
            updateLiveRecipePreviews()
        }
        .onChange(of: viewModel.isCapturing) { _, isCapturing in
            if isCapturing {
                blinkShutter()
            }
            guard !isCapturing, viewModel.reviewImage == nil else { return }
            updateCameraActivity()
        }
        .onChange(of: viewModel.isImporting) { _, _ in
            updateCameraActivity()
            updateIdleTimer()
        }
        .onChange(of: isImportInProgress) { _, _ in
            updateCameraActivity()
            updateIdleTimer()
        }
        // The simulator placeholder contains a renderer-backed swatch with a
        // non-zero ideal size. Keep that child from expanding the camera shell
        // beyond the window proposal and shifting the chrome offscreen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shells

    private func portraitShell(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .frame(minHeight: 50)
                .disabled(isChromeDisabled)

            viewfinderStage(isLandscape: false, overlaysTopBar: false)
                .padding(.top, 4)

            primaryBottomBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .disabled(isChromeDisabled)
        }
        .overlay(alignment: .bottom) {
            if isShowingLookDrawer {
                lookDrawer(
                    maxHeight: max(
                        160,
                        min(410, availableHeight - portraitControlClearance - 60)
                    )
                )
                    .padding(.horizontal, 12)
                    .padding(.bottom, portraitControlClearance)
                    .disabled(isChromeDisabled)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func edgeControlShell(isLandscape: Bool, availableHeight: CGFloat) -> some View {
        HStack(spacing: 12) {
            viewfinderStage(isLandscape: isLandscape, overlaysTopBar: true)

            edgeControlColumn
                .frame(width: 136)
                .disabled(isChromeDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottomLeading) {
            if isShowingLookDrawer {
                lookDrawer(
                    maxHeight: isLandscape
                        ? max(160, min(240, availableHeight - 130))
                        : max(180, min(360, availableHeight - 190))
                )
                    .padding(.leading, 12)
                    .padding(.trailing, 160)
                    .padding(.bottom, 78)
                    .disabled(isChromeDisabled)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var isChromeDisabled: Bool {
        viewModel.isCapturing || isImporting
    }

    private var portraitControlClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 176 : 150
    }

    // MARK: - Viewfinder

    private func viewfinderStage(isLandscape: Bool, overlaysTopBar: Bool) -> some View {
        GeometryReader { proxy in
            let size = ViewfinderLayout.size(available: proxy.size, isLandscape: isLandscape, aspect: captureAspect)

            viewfinder(size: size, overlaysTopBar: overlaysTopBar)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func viewfinder(size: CGSize, overlaysTopBar: Bool) -> some View {
        ZStack(alignment: .top) {
            previewSurface

            // The session is intentionally stopped while a frame is under
            // review. Keep the paused frame quiet behind the full-screen
            // review instead of announcing "Camera unavailable".
            if shouldShowCameraEmptyState, !isReviewing {
                cameraPlaceholder
            } else if isReviewing {
                Color.black.opacity(0.55)
                    .allowsHitTesting(false)
            }

            if showGrid && camera.isRunning {
                CompositionGrid(guide: compositionGuide)
            }

            if camera.isRunning && !isReviewing {
                CompositionAssistOverlay(store: assists, showHistogram: showHistogram, showLevel: showHorizonLevel)
                    .allowsHitTesting(false)
            }

            if let focusPoint {
                // The tap gesture reports locations in the frame's own space,
                // so the reticle lands exactly where the user touched. It stays
                // hit-test transparent so a visible reticle cannot swallow the
                // next focus tap.
                FocusReticle()
                    .position(focusPoint)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.15).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .task(id: focusPoint) {
                        try? await Task.sleep(for: .seconds(1.2))
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            self.focusPoint = nil
                        }
                    }
            }

            // The shutter blink: the frame goes dark for an instant on
            // capture, the way a mechanical shutter interrupts the finder.
            Color.black
                .opacity(isShutterBlinking ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            if overlaysTopBar {
                topBar
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .disabled(isChromeDisabled)
            }
        }
        .overlay(alignment: .bottom) {
            viewfinderFooter(width: size.width)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .disabled(isChromeDisabled)
        }
        .clipShape(RoundedRectangle(cornerRadius: FilmyTheme.viewfinderCornerRadius, style: .continuous))
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            FilteredCameraPreview(camera: camera, recipe: viewModel.selectedRecipe)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityElement(
                    children: FilteredCameraPreview.exposesRenderStatusForUITesting
                        ? .contain
                        : .ignore
                )
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
    }

    /// Controls that float along the bottom edge of the frame. Zoom stays
    /// immediately available; the broader camera tools appear on demand.
    @ViewBuilder
    private func viewfinderFooter(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            if isShowingTools {
                toolStrip(minWidth: width - 24)
            }

            // The presets need a live camera; the chrome preview shows them
            // so the full capture layout can be verified without hardware.
            if !isShowingLookDrawer,
               camera.isRunning || isViewfinderChromePreview,
               !isReviewing {
                ZoomPresetBar(
                    value: camera.zoomFactor,
                    minZoom: camera.minZoomFactor,
                    maxZoom: camera.maxZoomFactor,
                    onSelect: camera.setZoom,
                    onAdjust: { direction in
                        let delta: CGFloat = direction == .increment ? 0.5 : -0.5
                        camera.setZoom(camera.zoomFactor + delta)
                    }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Top bar

    /// The G7 X profile is a camera mode rather than a film stock, so its
    /// drawer names it as a camera profile.
    private var isCompactDigitalMode: Bool {
        viewModel.selectedRecipe.filmBase == .compactDigital
    }

    private var recipeEyebrow: String {
        isCompactDigitalMode ? "CAMERA PROFILE" : "RECIPE"
    }

    private var isLive: Bool {
        camera.availability == .running && camera.isRunning
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            flashControl

            if camera.availableCameraPositions.count > 1 {
                cameraSwitchButton
            }

            Spacer(minLength: 4)

            ViewThatFits(in: .horizontal) {
                Text("filmy")
                    .font(.system(.title3, design: .serif).italic())
                    .foregroundStyle(FilmyTheme.primary)
                    .accessibilityHidden(true)
                Color.clear.frame(width: 0, height: 0)
            }
            .layoutPriority(-1)

            Spacer(minLength: 4)

            captureSetupButton

            activeCaptureIndicators

            if !isLive {
                CameraStatusPill(
                    isRunning: camera.isRunning,
                    availability: camera.availability,
                    message: camera.statusMessage
                )
            }

            settingsButton

            if camera.isRunning || isViewfinderChromePreview {
                toolsToggle
            }
        }
    }

    @ViewBuilder
    private var activeCaptureIndicators: some View {
        if (abs(camera.exposureBias) >= 0.05 && camera.manualControls.exposureMode == .auto)
            || camera.isFocusExposureLocked
            || camera.manualControls.isAnyManualModeEnabled {
            Button {
                if camera.manualControls.isAnyManualModeEnabled {
                    isShowingManualControls = true
                    return
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                    isShowingLookDrawer = false
                    isShowingTools = true
                }
            } label: {
                HStack(spacing: 5) {
                    if abs(camera.exposureBias) >= 0.05 && camera.manualControls.exposureMode == .auto {
                        Text(String(format: "%+.1f EV", camera.exposureBias))
                    }
                    if camera.isFocusExposureLocked {
                        Label("AE/AF", systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    if camera.manualControls.isAnyManualModeEnabled {
                        Text("MANUAL")
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(FilmyTheme.accent)
                .padding(.horizontal, 9)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .background(Color.black.opacity(0.68), in: Capsule())
                .overlay { Capsule().stroke(FilmyTheme.accent.opacity(0.36), lineWidth: 1) }
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("camera-active-adjustments")
            .accessibilityLabel("Active camera adjustments")
            .accessibilityValue(activeCaptureIndicatorValue)
            .accessibilityHint("Shows the camera controls")
        }
    }

    private var activeCaptureIndicatorValue: String {
        var values: [String] = []
        if abs(camera.exposureBias) >= 0.05 && camera.manualControls.exposureMode == .auto {
            values.append(String(format: "%+.1f EV", camera.exposureBias))
        }
        if camera.isFocusExposureLocked {
            values.append("Focus and exposure locked")
        }
        if camera.manualControls.exposureMode == .manual {
            values.append("Manual exposure")
        }
        if camera.manualControls.whiteBalanceMode == .manual {
            values.append("Manual white balance")
        }
        if camera.manualControls.focusMode == .manual {
            values.append("Manual focus")
        }
        return values.joined(separator: ", ")
    }

    /// Flash sits in the top corner, icon-only, where every iPhone camera
    /// keeps it. It is a capture decision the G7 X flash treatment depends
    /// on, so it is never hidden behind the tools toggle.
    @ViewBuilder
    private var flashControl: some View {
        if camera.flashAvailability != .unsupported {
            FlashControl(
                mode: camera.flashMode,
                availability: camera.flashAvailability,
                iconOnly: true,
                action: camera.cycleFlashMode
            )
        }
    }

    private var cameraSwitchButton: some View {
        Button {
            HapticFeedback.play(.selection)
            camera.toggleCameraPosition()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("camera-switch-control")
        .accessibilityLabel("Switch camera")
        .accessibilityValue(camera.cameraPosition.title)
        .accessibilityHint("Switches between the front and back cameras.")
    }

    private var settingsButton: some View {
        Button {
            HapticFeedback.play(.selection)
            closeControlDrawers()
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("settings-tab")
        .accessibilityLabel("Open camera settings")
        .accessibilityHint("Shows camera preferences")
    }

    private var toolsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                if !isShowingTools {
                    isShowingLookDrawer = false
                }
                isShowingTools.toggle()
            }
        } label: {
            Image(systemName: isShowingTools ? "chevron.up" : "chevron.down")
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

    // MARK: - Primary controls and look drawer

    private var primaryBottomBar: some View {
        VStack(spacing: 4) {
            currentRecipeButton()

            ZStack {
                HStack {
                    rollButton
                    Spacer(minLength: 0)
                    importButton
                }

                captureControl
            }
            .frame(minHeight: 80)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: FilmyLayout.dockMaxWidth)
        .frame(maxWidth: .infinity)
    }

    /// Wide iPad layouts use the edge column even in portrait so the picture
    /// remains visually centered and the primary controls read like a camera
    /// grip. It also fits an iPhone's compact landscape height.
    private var edgeControlColumn: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            currentRecipeButton(compact: true)
            captureControl

            HStack(spacing: 8) {
                rollButton
                importButton
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func currentRecipeButton(compact: Bool = false) -> some View {
        CurrentRecipeButton(
            recipe: viewModel.selectedRecipe,
            isCustomized: viewModel.isCustomized(viewModel.selectedRecipe),
            compactLayout: compact,
            action: toggleLookDrawer
        )
    }

    private func lookDrawer(maxHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow(
                        text: recipeEyebrow,
                        color: isCompactDigitalMode ? FilmyTheme.accent : FilmyTheme.filmAccent
                    )
                    Text("Choose a look")
                        .font(.system(.title3, design: .serif).weight(.medium))
                        .foregroundStyle(FilmyTheme.primary)
                }

                Spacer(minLength: 8)

                Button {
                    openRecipeDetail(viewModel.selectedRecipe)
                } label: {
                    Label("Tune", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.panel, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Tune \(viewModel.selectedRecipe.name)")

                Button(action: toggleLookDrawer) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FilmyTheme.secondary)
                        .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.panel, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("recipe-drawer-close")
                .accessibilityLabel("Close look picker")
            }
            .padding(.horizontal, 8)
            .layoutPriority(1)

            RecipePickerView(
                recipes: viewModel.recipes,
                selectedRecipeID: $viewModel.selectedRecipeID,
                onOpenDetail: openRecipeDetail,
                compact: true
            )
            .frame(maxHeight: max(maxHeight - 122, 70))

            Button {
                HapticFeedback.play(.selection)
                isShowingLookLibrary = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                    Text("Explore all \(viewModel.recipes.count) looks")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(.subheadline).weight(.semibold))
                .foregroundStyle(FilmyTheme.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(FilmyTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("look-library-open")
            .accessibilityHint("Browse larger previews, search looks, and save favorites")
        }
        .padding(10)
        .frame(maxWidth: 640)
        .frame(maxHeight: maxHeight)
        .background(FilmyTheme.backgroundRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe-drawer")
    }

    @ViewBuilder
    private var captureControl: some View {
        if isViewfinderChromePreview {
            CaptureButton(isCapturing: viewModel.isCapturing, isEnabled: false) {}
        } else if isReviewing {
            CaptureButton(isCapturing: false, isEnabled: false) {}
        } else if shouldShowCameraEmptyState {
            captureNotice
        } else {
            CaptureButton(
                isCapturing: viewModel.isCapturing,
                isEnabled: !camera.manualControls.isApplying && framingIsReady,
                unavailableLabel: framingIsReady ? "Applying camera settings" : "Updating framing",
                unavailableHint: "Wait for the camera to finish applying your settings",
                action: capture
            )
        }
    }

    private var captureNotice: some View {
        Label(captureNoticeTitle, systemImage: captureNoticeIcon)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 104, height: 80)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(captureNoticeTitle)
            .accessibilityHint(captureNoticeHint)
    }

    /// Keep the capture row honest about why the shutter is unavailable. A
    /// stopped session is also used for permission denial, interruptions, and
    /// recovery, so a simulator-only message here would send device users in
    /// the wrong direction.
    private var captureNoticeTitle: String {
        switch camera.availability {
        case .simulator:
            return "Capture on iPhone or iPad"
        case .permissionDenied:
            return "Camera access needed"
        case .interrupted, .needsRecovery:
            return "Resume camera"
        case .unavailable:
            return "Camera unavailable"
        case .paused:
            return "Camera paused"
        case .idle, .starting, .requestingPermission, .running:
            return "Starting camera…"
        }
    }

    private var captureNoticeIcon: String {
        switch camera.availability {
        case .simulator:
            return "iphone"
        case .permissionDenied:
            return "lock.slash"
        case .interrupted:
            return "pause.circle"
        case .needsRecovery:
            return "arrow.clockwise.circle"
        case .unavailable:
            return "camera.fill"
        case .paused:
            return "pause.circle"
        case .idle, .starting, .requestingPermission, .running:
            return "clock"
        }
    }

    private var captureNoticeHint: String {
        switch camera.availability {
        case .simulator:
            return "Connect a physical iPhone or iPad to capture photos."
        case .permissionDenied:
            return "Open Settings above to allow camera access."
        case .interrupted, .needsRecovery:
            return "Tap Resume Camera above the preview to try again."
        case .unavailable:
            return "The camera is unavailable. Check the camera and try again."
        case .paused:
            return "Return to the Camera tab to resume the preview."
        case .idle, .starting, .requestingPermission, .running:
            return "Wait for the camera preview to become ready."
        }
    }

    private var rollButton: some View {
        Button {
            closeControlDrawers()
            onOpenGallery()
        } label: {
            RollThumbnail(asset: photoLibrary.galleryAssets.first, photoLibrary: photoLibrary)
                .frame(width: 52, height: 52)
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("roll-tab")
        .accessibilityLabel("Open roll")
        .accessibilityHint("Shows the frames you have kept")
    }

    private var importButton: some View {
        Button {
            HapticFeedback.play(.selection)
            closeControlDrawers()
            onImportPhoto()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }

                if isImporting {
                    ProgressView()
                        .tint(FilmyTheme.accent)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FilmyTheme.primary)
                }
            }
            .frame(width: 52, height: 52)
            .frame(width: 60, height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isImporting)
        .accessibilityLabel(isImporting ? "Importing photo" : "Import photo")
        .accessibilityHint("Choose a photo and apply the current film recipe")
        .accessibilityIdentifier("import-photo")
    }

    // MARK: - Tool strips

    private func toolStrip(minWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ExposureControl(value: camera.exposureBias) { direction in
                    let delta: Float = direction == .increment ? (1.0 / 3.0) : -(1.0 / 3.0)
                    camera.setExposureBias(camera.exposureBias + delta)
                }
                .opacity(camera.manualControls.exposureMode == .manual ? 0.45 : 1)
                .disabled(camera.manualControls.exposureMode == .manual || camera.manualControls.isApplying)

                if (focusPoint != nil || camera.isFocusExposureLocked),
                   let focusNormalizedPoint,
                   camera.manualControls.exposureMode != .manual,
                   camera.manualControls.focusMode != .manual {
                    FocusLockControl(isLocked: camera.isFocusExposureLocked) {
                        camera.toggleFocusExposureLock(at: focusNormalizedPoint)
                    }
                }

                gridToggle(
                    accessibilityIdentifier: isCompactDigitalMode
                        ? "g7x-grid-control"
                        : "grid-control"
                )

                if camera.availableLenses.count > 1 {
                    CameraLensMenu(camera: camera)
                }

                proControlsButton
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(minWidth: max(minWidth, 0))
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isCompactDigitalMode ? "g7x-capture-controls" : "camera-utility-rail"
        )
        .accessibilityHint("Swipe horizontally for additional camera controls")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var proControlsButton: some View {
        Button {
            HapticFeedback.play(.selection)
            isShowingManualControls = true
        } label: {
            Label("Pro", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(camera.manualControls.isAnyManualModeEnabled ? FilmyTheme.background : .white)
                .padding(.horizontal, 12)
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.toolControlHeight)
                .background {
                    if camera.manualControls.isAnyManualModeEnabled {
                        Capsule().fill(FilmyTheme.filmAccent)
                    } else {
                        ChromeShapeBackground(shape: Capsule())
                    }
                }
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("pro-controls-button")
        .accessibilityLabel("Pro controls")
        .accessibilityValue(
            camera.manualControls.isApplying
                ? "Applying camera settings"
                : (camera.manualControls.isAnyManualModeEnabled ? "Manual settings active" : "Auto settings")
        )
        .accessibilityHint("Adjust ISO, shutter speed, white balance, and focus")
    }

    private func gridToggle(accessibilityIdentifier: String) -> some View {
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
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(showGrid ? "Hide composition grid" : "Show composition grid")
        .accessibilityValue(showGrid ? "On" : "Off")
    }

    // MARK: - State

    private var shouldShowCameraEmptyState: Bool {
        !camera.isRunning
    }

    private var isImporting: Bool {
        viewModel.isImporting || isImportInProgress
    }

    private var isReviewing: Bool {
        viewModel.reviewImage != nil
    }

    private var isViewfinderChromePreview: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-viewfinder-chrome")
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
                message: camera.statusMessage,
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
        guard canTriggerShutter else { return }
        closeControlDrawers()
        if captureDelay == .off {
            viewModel.capture(camera: camera)
        } else {
            countdown.start(seconds: captureDelay.rawValue) {
                guard canTriggerShutter else { return }
                viewModel.capture(camera: camera)
            }
        }
    }

    private func closeControlDrawers() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isShowingLookDrawer = false
            isShowingTools = false
        }
    }

    private func openRecipeDetail(_ recipe: FilmRecipe) {
        closeControlDrawers()
        recipeForDetail = viewModel.recipe(for: recipe.id)
    }

    private func toggleLookDrawer() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
            if !isShowingLookDrawer {
                isShowingTools = false
            }
            isShowingLookDrawer.toggle()
        }
    }

    private func updateLiveRecipePreviews() {
        if camera.isRunning,
           !isReviewing,
           !isShowingLookLibrary,
           isShowingLookDrawer || recipeForDetail != nil {
            livePreviews.attach(to: camera)
        } else {
            livePreviews.detach()
            livePreviews.clear()
        }
    }

    private func blinkShutter() {
        guard !reduceMotion else { return }
        isShutterBlinking = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeOut(duration: 0.14)) {
                isShutterBlinking = false
            }
        }
    }

    private func updateCameraActivity() {
        guard !CameraActivityPolicy.isUnitTestHost else { return }

        // Imports pause frame delivery while the renderer works. Keep that
        // pause authoritative across scene and tab changes so a foreground
        // callback cannot resume the live GPU path halfway through an import.
        if isImporting {
            if scenePhase == .active, isCameraTabActive {
                camera.setFrameDeliveryPaused(true)
                camera.stop(after: CameraActivityPolicy.inactiveGracePeriod)
            } else {
                camera.stop()
            }
            return
        }

        let action = CameraActivityPolicy.action(
            hasReview: viewModel.reviewImage != nil,
            sceneIsActive: scenePhase == .active,
            isCameraTabActive: isCameraTabActive,
            availability: camera.availability
        )

        switch action {
        case .start:
            camera.setFrameDeliveryPaused(false)
            camera.start()
        case .stop:
            camera.stop()
        case .stopAfterGrace:
            camera.stop(after: CameraActivityPolicy.deferredStopDelay(
                hasReview: viewModel.reviewImage != nil
            ))
        case .hold:
            break
        }
    }

    /// Framing is an active camera session: prevent the device from locking
    /// while the Camera tab is foregrounded, but restore the system default
    /// when the user leaves framing, opens review, imports, or backgrounds.
    /// This policy is intentionally scoped to this view rather than global.
    @MainActor
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            scenePhase == .active
            && isCameraTabActive
            && !isReviewing
            && !isImporting
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
                ChromeShapeBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(image == nil ? 0 : 0.5), lineWidth: 1.5)
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

private struct CameraLensMenu: View {
    @ObservedObject var camera: CameraService

    var body: some View {
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
                .viewfinderCapsule(interactive: true)
        }
        .accessibilityIdentifier("lens-menu-control")
        .accessibilityLabel("Choose lens")
        .accessibilityValue(selectedLensTitle)
        .accessibilityHint("Choose a lens on the active camera.")
    }

    private var selectedLensTitle: String {
        camera.availableLenses.first(where: { $0.id == camera.selectedLensID })?.title ?? "Lens"
    }
}


// MARK: - Capture setup and assist presentation

extension CameraScreen {
    private var isCameraVisibleForAssists: Bool {
        scenePhase == .active && isCameraTabActive && camera.isRunning && camera.availability == .running && !isReviewing && !isImporting
            && !viewModel.isCapturing && recipeForDetail == nil && !isShowingLookLibrary
            && !isShowingManualControls && !isShowingCaptureSetup
    }
    private var canTriggerShutter: Bool {
        isCameraVisibleForAssists && !viewModel.isSaving && !camera.manualControls.isApplying && !countdown.state.isActive && framingIsReady
    }
    private var framingIsReady: Bool {
        guard captureAspect != .viewfinder else { return true }
        let viewport = camera.previewViewportSize
        guard viewport.width > 0, viewport.height > 0,
              let ratio = captureAspect.ratio(isLandscape: viewport.width > viewport.height) else { return false }
        return abs(Double(viewport.width / viewport.height) - ratio) < 0.015
    }
    private var assistOptions: CompositionAssistStore.Options {
        .init(histogram: showHistogram, zebras: showZebras, peaking: showFocusPeaking, level: showHorizonLevel)
    }
    private func updateCompositionAssists() {
        assists.configure(camera: camera, options: assistOptions, active: isCameraVisibleForAssists)
    }
    private var captureSetupButton: some View {
        Button {
            closeControlDrawers()
            isShowingCaptureSetup = true
        } label: {
            Image(systemName: captureDelay == .off ? "viewfinder" : "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(captureDelay == .off ? FilmyTheme.primary : FilmyTheme.accent)
                .frame(width: 44, height: 44)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("capture-setup-open")
        .accessibilityLabel("Capture setup")
        .accessibilityValue("Timer \(captureDelay.title), \(captureAspect.title)")
        .accessibilityHint("Choose a timer, aspect ratio, grid, histogram, zebras, focus peaking, or level")
    }
    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("\(countdown.state.remaining)")
                    .font(.system(size: 84, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("Photo in \(countdown.state.remaining) seconds")
                    .accessibilityIdentifier("capture-countdown-value")
                Button { countdown.cancel() } label: {
                    Label("Cancel timer", systemImage: "xmark")
                        .padding(.horizontal, 22).frame(minHeight: 52)
                        .background(FilmyTheme.panel, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture-countdown-cancel")
            }
            .foregroundStyle(FilmyTheme.primary)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-countdown")
    }
}

private struct CameraHardwareShutterModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onCameraCaptureEvent(isEnabled: enabled) { event in
                if event.phase == .ended { action() }
            }
        } else {
            content
        }
    }
}

struct CaptureSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("captureDelay") private var delay = CaptureDelay.off
    @AppStorage("captureAspect") private var aspect = CaptureAspect.viewfinder
    @AppStorage("compositionGuide") private var guide = CompositionGuide.thirds
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("showHistogram") private var histogram = false
    @AppStorage("showZebras") private var zebras = false
    @AppStorage("showFocusPeaking") private var peaking = false
    @AppStorage("showHorizonLevel") private var level = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Self-timer", selection: $delay) {
                        ForEach(CaptureDelay.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("capture-delay-picker")
                    Picker("Photo aspect", selection: $aspect) {
                        ForEach(CaptureAspect.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("capture-aspect-picker")
                } header: { Text("Capture") } footer: {
                    Text("The viewfinder and saved photo use the same crop. Timer cancellation, leaving the camera, or an interruption prevents the shot. Imports keep their original aspect.")
                }
                Section("Composition") {
                    Toggle("Show grid", isOn: $showGrid).accessibilityIdentifier("capture-grid-toggle")
                    Picker("Grid style", selection: $guide) {
                        ForEach(CompositionGuide.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("capture-guide-picker")
                    Toggle("Horizon level", isOn: $level).accessibilityIdentifier("capture-level-toggle")
                }
                Section {
                    Toggle("Luminance histogram", isOn: $histogram).accessibilityIdentifier("capture-histogram-toggle")
                    Toggle("Highlight zebras", isOn: $zebras).accessibilityIdentifier("capture-zebras-toggle")
                    Toggle("Focus peaking", isOn: $peaking).accessibilityIdentifier("capture-peaking-toggle")
                } header: { Text("Live preview aids") } footer: {
                    Text("Analyzes the unfiltered camera preview, not RAW sensor data or the finished look. Red edges indicate local contrast, not guaranteed focus. All guides are preview-only and never appear in saved photos. Updates are limited to four per second.")
                }
                Section {
                    Text("Use supported volume or Camera Control shutter events while the camera is active. These are disabled during review, imports, countdowns, and setup. Camera Control focus/zoom customization is not included.")
                        .foregroundStyle(FilmyTheme.secondary)
                } header: { Text("Hardware shutter") }
            }
            .scrollContentBackground(.hidden)
            .background(FilmyTheme.background)
            .navigationTitle("Capture setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("capture-setup-done")
                }
            }
        }
        .tint(FilmyTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-setup")
    }
}

private struct CompositionGrid: View {
    let guide: CompositionGuide
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width, h = proxy.size.height
                switch guide {
                case .thirds, .golden:
                    let positions: [CGFloat] = guide == .thirds ? [1.0 / 3, 2.0 / 3] : [0.382, 0.618]
                    for p in positions {
                        path.move(to: CGPoint(x: w * p, y: 0)); path.addLine(to: CGPoint(x: w * p, y: h))
                        path.move(to: CGPoint(x: 0, y: h * p)); path.addLine(to: CGPoint(x: w, y: h * p))
                    }
                case .square:
                    let edge = min(w, h)
                    path.addRect(CGRect(x: (w - edge) / 2, y: (h - edge) / 2, width: edge, height: edge))
                case .crosshair:
                    path.move(to: CGPoint(x: w / 2 - 14, y: h / 2)); path.addLine(to: CGPoint(x: w / 2 + 14, y: h / 2))
                    path.move(to: CGPoint(x: w / 2, y: h / 2 - 14)); path.addLine(to: CGPoint(x: w / 2, y: h / 2 + 14))
                }
            }
            .stroke(.white.opacity(0.38), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CompositionAssistOverlay: View {
    @ObservedObject var store: CompositionAssistStore
    let showHistogram: Bool
    let showLevel: Bool
    var body: some View {
        ZStack {
            if let image = store.overlay {
                Image(uiImage: image).resizable().interpolation(.none)
                    .accessibilityHidden(true)
            }
            if showLevel, let degrees = store.horizon {
                HStack(spacing: 6) {
                    Rectangle().frame(width: 26, height: 2)
                    Text(abs(degrees) < 1 ? "Level" : String(format: "%+.0f°", degrees))
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Rectangle().frame(width: 26, height: 2)
                }
                .foregroundStyle(abs(degrees) < 1 ? FilmyTheme.accent : .white)
                .padding(8).background(.black.opacity(0.55), in: Capsule())
                .accessibilityLabel("Horizon \(String(format: "%.0f", degrees)) degrees")
            }
        }
        .overlay(alignment: .topLeading) {
            if showHistogram, !store.histogram.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PREVIEW LUMA").font(.system(size: 9, weight: .bold))
                    Canvas { context, size in
                        let maximum = max(store.histogram.max() ?? 1, 1)
                        let step = size.width / CGFloat(store.histogram.count)
                        var path = Path()
                        for (index, value) in store.histogram.enumerated() {
                            let height = size.height * CGFloat(value) / CGFloat(maximum)
                            path.addRect(CGRect(x: CGFloat(index) * step, y: size.height - height,
                                                width: max(step - 0.5, 0.5), height: height))
                        }
                        context.fill(path, with: .color(.white))
                    }.frame(width: 102, height: 36)
                    Text(String(format: "Highlights %.1f%%", store.clippingPercent)).font(.system(size: 9))
                }
                .foregroundStyle(.white).padding(8)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 8).padding(.top, 62)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview luminance histogram. \(String(format: "%.1f", store.clippingPercent)) percent highlight warning")
            }
        }
    }
}
