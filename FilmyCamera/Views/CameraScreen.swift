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

/// Keep every shutter-adjacent control reachable when adjustment badges need
/// more width than the camera's top row can provide.
struct CameraTopBarLayout<Controls: View, Indicators: View>: View {
    let controls: Controls
    let indicators: Indicators

    init(@ViewBuilder controls: () -> Controls, @ViewBuilder indicators: () -> Indicators) {
        self.controls = controls()
        self.indicators = indicators()
    }

    var body: some View {
        // Hardware discovery and status changes must never choose a different
        // row count. Reserve both rows before the first camera frame arrives.
        VStack(alignment: .trailing, spacing: 0) {
            controls.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 64 : 48)
            indicators
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .trailing)
        }
    }
}

private enum ViewfinderChromeEdge: Hashable, Sendable { case top, bottom }

private struct ViewfinderChromeHeightKey: PreferenceKey {
    static let defaultValue: [ViewfinderChromeEdge: CGFloat] = [:]

    static func reduce(value: inout [ViewfinderChromeEdge: CGFloat],
                       nextValue: () -> [ViewfinderChromeEdge: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

@MainActor
private final class CompositionAssistStoreBox: ObservableObject {
    let store = CompositionAssistStore()
}

/// The viewfinder and its capture controls. The picture keeps a stable frame
/// while look and camera-tool drawers float above it. Wide layouts put the
/// primary controls in an edge column; compact layouts keep them below the
/// frame within thumb reach.
struct CameraScreen: View {
    // Keep edge controls comfortably reachable with a two-handed iPad grip.
    private var cameraHitTarget: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 64 : FilmyTheme.minimumHitTarget
    }

    @ObservedObject private var membership = MembershipStore.shared
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
    @StateObject private var countdown = CaptureCountdown()
    // Held in a box that never publishes: the store ticks at 10 Hz and only
    // CompositionAssistOverlay (which observes it directly) reads those values.
    @StateObject private var assistBox = CompositionAssistStoreBox()
    private var assists: CompositionAssistStore { assistBox.store }
    @StateObject private var smartRecipes = SmartRecipeStore()
    @State private var isShowingSmartRecipes = false
    @State private var smartPresentation: SmartRecipeSnapshot?
    @StateObject private var shooting = FujiShootingController()
    @State private var isShowingFujiMenu = false
    @State private var isShowingCaptureSetup = false
    @AppStorage("captureDelay") private var storedCaptureDelay = CaptureDelay.off
    private var captureDelay: CaptureDelay { membership.hasFullAccess ? storedCaptureDelay : .off }
    @AppStorage("captureAspect") private var storedCaptureAspect = CaptureAspect.viewfinder
    private var captureAspect: CaptureAspect { membership.hasFullAccess ? storedCaptureAspect : .viewfinder }
    @AppStorage("compositionGuide") private var storedCompositionGuide = CompositionGuide.thirds
    private var compositionGuide: CompositionGuide { membership.hasFullAccess ? storedCompositionGuide : .thirds }
    @AppStorage("showHistogram") private var storedShowHistogram = false
    private var showHistogram: Bool { membership.hasFullAccess && storedShowHistogram }
    @AppStorage("showZebras") private var storedShowZebras = false
    private var showZebras: Bool { membership.hasFullAccess && storedShowZebras }
    @AppStorage("showFocusPeaking") private var storedShowFocusPeaking = false
    private var showFocusPeaking: Bool { membership.hasFullAccess && storedShowFocusPeaking }
    @AppStorage("showHorizonLevel") private var storedShowHorizonLevel = false
    private var showHorizonLevel: Bool { membership.hasFullAccess && storedShowHorizonLevel }
    @State private var recipeForDetail: FilmRecipe?
    @State private var isShowingTools: Bool
    @State private var isShowingManualControls = false
    @State private var isShowingLiveAdjustments = false
    @State private var isShowingLookDrawer = false
    @AppStorage("cameraGestureHintSeen.v1") private var gestureHintSeen = false
    @State private var originalPreviewOverride: Bool?
    @GestureState private var isHoldingOriginalPreview = false
    @GestureState private var isPreviewDragActive = false
    @State private var isShowingLookLibrary = false
    @State private var isShowingRecipeManager = false
    @State private var quickRecipeQuery = ""
    @State private var focusPoint: CGPoint?
    @State private var focusNormalizedPoint: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isPinching = false
    @State private var previewDragMaySelectLook: Bool?
    @State private var previewDragAxis: CameraPreviewDragAxis?
    @State private var exposureDragStart: Float?
    @State private var isShowingExposureReadout = false
    @State private var exposureDragCommitted = false
    @State private var exposureDragSentBias: Float?
    @State private var focusFeedbackRevision = 0
    @State private var suppressLookSwipeUntil = Date.distantPast
    @State private var viewfinderChromeHeights: [ViewfinderChromeEdge: CGFloat] = [:]
    @State private var isShutterBlinking = false
    @State private var isConfirmingCaptureDiscard = false
    @State private var favoritesOnly = false
    @AppStorage("favoriteRecipeIDs.v1") private var favoriteData = Data()
    @AppStorage("cameraGripUseLeftHanded.v1") private var useLeftHandedGrip = false
    @State private var hardwareShutterCaptureRequest = 0
    @State private var hasDismissedLensAdvisory = false
#if DEBUG
    @State private var hardwareShutterEventCount = 0
    @State private var hardwareShutterLastPhase = "none"
    @State private var hardwareShutterActionCount = 0
    @State private var hardwareShutterEventReadiness = "unset"
    @State private var hardwareShutterCaptureReadiness = "unset"
#endif

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

        // Show capture controls on launch. The explicit collapsed-chrome
        // test fixture still exercises revealing them with the toggle.
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let isViewfinderPreview = arguments.contains("-ui-testing-viewfinder-chrome")
        _isShowingTools = State(initialValue: !(isUITesting && isViewfinderPreview))
    }

    private var cameraLayers: some View {
        ZStack {
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height
                let usesEdgeControlColumn = isLandscape || proxy.size.width >= 720

                Group {
                    if usesEdgeControlColumn {
                        edgeControlShell(
                            isLandscape: isLandscape,
                            availableHeight: proxy.size.height,
                            availableWidth: proxy.size.width
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
                VStack(spacing: 8) {
                    if viewModel.hasPendingCapture, let error = viewModel.saveErrorMessage {
                        captureSaveRecovery(error)
                    } else if viewModel.hasPendingCapture && viewModel.isSaving {
                        Label("Saving photo", systemImage: "photo.badge.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .viewfinderChrome(Capsule())
                            .accessibilityIdentifier("capture-saving")
                        if let toastMessage = viewModel.toastMessage, viewModel.toastStyle == .info {
                            ToastView(message: toastMessage, style: viewModel.toastStyle)
                                .transition(.opacity)
                        }
                    } else if let toastMessage = viewModel.toastMessage {
                        ToastView(message: toastMessage, style: viewModel.toastStyle)
                            .transition(.opacity)
                    } else if camera.isLensSmudged && !hasDismissedLensAdvisory && camera.availability == .running {
                        HStack(spacing: 12) {
                            Label("Wipe the camera lens for a clearer photo", systemImage: "camera.aperture")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { hasDismissedLensAdvisory = true } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Dismiss lens cleaning tip")
                        }
                        .padding(.leading, 14)
                        .viewfinderChrome(RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("camera-lens-cleaning-tip")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 82)
                // Animate feedback only, not the camera's geometry transaction.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: viewModel.toastMessage)
            }
            .allowsHitTesting(!isReviewing && !countdown.state.isActive && !shooting.isBusy)
            .disabled(isReviewing || countdown.state.isActive || shooting.isBusy)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(isReviewing || countdown.state.isActive)

            VStack {
                FujiShootingStatusView(controller: shooting, photoLibrary: photoLibrary)
                Spacer()
            }.padding(.top, 104).zIndex(3)

            if countdown.state.isActive { countdownOverlay.zIndex(2) }

            if viewModel.isReviewingImport, let image = viewModel.reviewImage, let recipe = viewModel.reviewRecipe {
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

#if DEBUG
            if hardwareShutterDiagnosticsEnabled {
                hardwareShutterDiagnostics
            }
#endif
        }
    }

    var body: some View {
        cameraLifecycleView
    }

    private var cameraHardwareView: some View {
        cameraLayers
#if DEBUG
        .modifier(CameraHardwareShutterModifier(enabled: canTriggerShutter, action: { hardwareShutterCaptureRequest &+= 1 }) { phase in
            guard hardwareShutterDiagnosticsEnabled else { return }
            hardwareShutterEventCount += 1
            hardwareShutterLastPhase = phase
            hardwareShutterEventReadiness = "ready=\(canTriggerShutter);blocker=\(hardwareShutterBlockingReason)"
        })
#else
        .modifier(CameraHardwareShutterModifier(enabled: canTriggerShutter, action: { hardwareShutterCaptureRequest &+= 1 }))
#endif
        .confirmationDialog("Discard this unsaved photo?", isPresented: $isConfirmingCaptureDiscard, titleVisibility: .visible) {
            Button("Discard photo", role: .destructive) { viewModel.discardReview() }
                .accessibilityIdentifier("capture-save-confirm-discard")
            Button("Keep photo", role: .cancel) { }
        } message: {
            Text("This photo has not been saved to Photos. Discarding cannot be undone.")
        }
    }

    private var smartRecipeLifecycleView: some View {
        cameraHardwareView
        .onChange(of: isSmartRecipeAnalysisActive, initial: true) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: viewModel.selectedRecipe) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: membership.hasFullAccess) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: favoriteData) { _, _ in updateSmartRecipeAnalysis() }
        .onChange(of: smartRecipeFrameKey) { _, _ in smartRecipes.invalidateScene() }
        .onChange(of: viewModel.selectedRecipeID) { _, selected in
            originalPreviewOverride = nil
            smartRecipes.reconcileSelection(currentID: selected, availableIDs: Set(viewModel.recipes.map(\.id)))
        }
        .sheet(isPresented: $isShowingSmartRecipes, onDismiss: { smartPresentation = nil }) {
            SmartRecipeSheet(
                store: smartRecipes, snapshot: smartPresentation,
                selectedID: viewModel.selectedRecipeID, canApply: canApplySmartRecipe,
                onApply: applySmartRecipe, onClose: { isShowingSmartRecipes = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var shootingStateView: some View {
        smartRecipeLifecycleView
        .onChange(of: isShootingSessionActive, initial: true) { _, active in
            shooting.attach(camera: camera, viewModel: viewModel, active: active)
        }
        .onChange(of: camera.manualControls.activeDeviceID) { _, _ in shooting.invalidatePreview() }
        .onChange(of: camera.selectedLensID) { _, _ in shooting.invalidatePreview() }
        .onChange(of: camera.zoomFactor) { _, _ in shooting.invalidatePreview() }
        .onChange(of: viewModel.selectedRecipe) { _, _ in shooting.invalidatePreview() }
        .onChange(of: shooting.settings.showsNaturalPreview) { _, _ in originalPreviewOverride = nil }
        .onChange(of: shooting.isBusy, initial: true) { _, busy in
            viewModel.isFujiBusy = busy
            if busy { countdown.cancel(); blinkShutter() }
        }
        .onChange(of: membership.hasFullAccess) { _, premium in
            if !premium {
                isShowingLiveAdjustments = false
                recipeForDetail = nil
                countdown.cancel()
            }
            updateCompositionAssists()
        }
        .onChange(of: assistOptions, initial: true) { _, _ in updateCompositionAssists() }
        .onChange(of: isCameraVisibleForAssists, initial: true) { _, visible in
            if !visible { countdown.cancel() }
            updateCompositionAssists()
        }
        .onChange(of: isCameraVisibleForAssists && !countdown.state.isActive, initial: true) { _, active in
            camera.setSceneAutoViewfinderActive(active)
        }
        .onChange(of: countdown.state.remaining) { old, new in
            guard countdown.state.isActive, new > 0 else { return }
            let message = old == 0 ? "Photo in \(new) seconds" : "\(new)"
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .onChange(of: captureAspect) { _, _ in countdown.cancel(); assists.stop(); shooting.invalidatePreview(); updateCompositionAssists() }
        .onChange(of: canTriggerShutter) { _, enabled in
            if !enabled {
                isPinching = false
                previewDragMaySelectLook = nil
                previewDragAxis = nil
                isShowingExposureReadout = false
                // A cancelled exposure drag must still let the reticle time out.
                if exposureDragStart != nil { focusFeedbackRevision += 1 }
                exposureDragStart = nil
                exposureDragCommitted = false
                exposureDragSentBias = nil
            }
        }
        .onChange(of: camera.isRunning) { _, running in
            if !running { isShowingExposureReadout = false }
        }
        .onChange(of: isPreviewDragActive) { _, active in
            // One main-actor turn later, so a normal onEnded always runs first.
            if !active { Task { @MainActor in resetCancelledPreviewDrag() } }
        }
        // Re-enter through current SwiftUI state after the system callback,
        // avoiding a retained callback snapshot with stale scene values.
        .onChange(of: hardwareShutterCaptureRequest) { _, _ in capture() }
        .onChange(of: camera.isLensSmudged) { _, smudged in
            if !smudged { hasDismissedLensAdvisory = false }
        }
        .onChange(of: camera.previewViewportSize) { _, _ in
            // A mask from the previous crop must not stretch over a newly
            // rotated or resized viewfinder while its replacement renders.
            assists.stop()
            shooting.invalidatePreview()
            updateCompositionAssists()
        }
    }

    private var cameraPresentationsView: some View {
        shootingStateView
        .sheet(isPresented: $isShowingFujiMenu) {
            FujiQuickMenuView(controller: shooting, camera: camera, viewModel: viewModel, photoLibrary: photoLibrary)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FilmyTheme.background)
        }
        .sheet(isPresented: $isShowingCaptureSetup) {
            PremiumFeatureGate(feature: .captureSetup) { CaptureSetupView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FilmyTheme.background)
        }
        .sheet(isPresented: $isShowingLookLibrary) {
            LookLibraryView(
                recipes: viewModel.recipes,
                selectedRecipeID: viewModel.effectiveSelectedRecipeID,
                onSelect: { recipe in
                    guard membership.requireRecipe(recipe.id) else { return }
                    viewModel.select(recipe: recipe)
                    isShowingLookLibrary = false
                    isShowingLookDrawer = false
                },
                onClose: { isShowingLookLibrary = false },
                libraryPreferences: $viewModel.libraryPreferences
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(FilmyTheme.background)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $isShowingRecipeManager) {
            RecipeLibraryManagerView(
                preferences: $viewModel.libraryPreferences,
                recipes: viewModel.recipes,
                selectedRecipeID: viewModel.selectedRecipeID,
                onSelect: { recipe in
                    viewModel.select(recipe: recipe)
                    isShowingRecipeManager = false
                    isShowingLookDrawer = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $recipeForDetail) { recipe in
            RecipeDetailView(
                recipe: recipe,
                originalRecipe: viewModel.originalRecipe(for: recipe.id),
                isSelected: viewModel.effectiveSelectedRecipeID == recipe.id,
                onSelect: {
                    guard membership.requireRecipe(recipe.id) else { return }
                    viewModel.select(recipe: recipe)
                    recipeForDetail = nil
                },
                // The presenter owns closing the editor. Cancelling never
                // commits its local draft or selects a different recipe.
                onCancel: { recipeForDetail = nil },
                onUpdate: { updated in
                    viewModel.update(recipe: updated)
                    updateSmartRecipeAnalysis()
                },
                onReset: {
                    viewModel.reset(recipeID: recipe.id)
                    updateSmartRecipeAnalysis()
                    recipeForDetail = viewModel.originalRecipe(for: recipe.id)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(FilmyTheme.background)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $isShowingManualControls) {
            PremiumFeatureGate(feature: .manualControls) { ManualCameraControlsView(camera: camera) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FilmyTheme.background)
        }
    }

    private var cameraLifecycleView: some View {
        cameraPresentationsView
        .onAppear {
            shooting.attach(camera: camera, viewModel: viewModel, active: isShootingSessionActive)
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
            camera.setSceneAutoViewfinderActive(false)
            viewModel.isFujiBusy = false
            shooting.attach(camera: camera, viewModel: viewModel, active: false)
            countdown.cancel()
            assists.stop()
            smartRecipes.stop()
            camera.stop(after: CameraActivityPolicy.inactiveGracePeriod)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, _ in
            shooting.attach(camera: camera, viewModel: viewModel, active: isShootingSessionActive)
            updateCameraActivity()
            updateIdleTimer()
        }
        .onChange(of: isCameraTabActive) { _, _ in
            updateCameraActivity()
            updateIdleTimer()
        }
        .onChange(of: viewModel.isReviewingImport) { _, hasReview in
            if hasReview {
                // The linger task dies with the unmounted readout, so clear it here.
                isShowingExposureReadout = false
                camera.setFrameDeliveryPaused(true)
            }
            updateCameraActivity()
            updateIdleTimer()
        }
        .onChange(of: viewModel.isCapturing) { _, isCapturing in
            if isCapturing {
                blinkShutter()
            }
            guard !isCapturing, !viewModel.isReviewingImport else { return }
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

    /// A failed write keeps the exact captured bytes for retry. Never turn a
    /// normal shutter press into an editor or let the next shot overwrite it.
    private func captureSaveRecovery(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Photo not saved yet", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(FilmyTheme.danger)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { captureRecoveryActions }
                VStack(alignment: .leading, spacing: 8) { captureRecoveryActions }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .viewfinderChrome(RoundedRectangle(cornerRadius: 16))
        .dynamicTypeSize(.xSmall ... .accessibility1)
        .accessibilityIdentifier("capture-save-recovery")
    }

    @ViewBuilder
    private var captureRecoveryActions: some View {
        Button {
            viewModel.saveReview(photoLibrary: photoLibrary)
        } label: {
            Text("Retry save").frame(minHeight: 44)
        }
        .accessibilityIdentifier("capture-save-retry")
        if viewModel.saveErrorRequiresSettings {
            Button(action: openSystemSettings) {
                Text("Photos Settings").frame(minHeight: 44)
            }
            .accessibilityIdentifier("capture-save-settings")
        }
        Button(role: .destructive) {
            isConfirmingCaptureDiscard = true
        } label: {
            Text("Discard").frame(minHeight: 44)
        }
        .accessibilityIdentifier("capture-save-discard")
    }

    // MARK: - Shells

    private func portraitShell(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .frame(minHeight: 50)
                .disabled(isNavigationChromeDisabled)

            viewfinderStage(isLandscape: false, overlaysTopBar: false)
                .padding(.top, 4)

            primaryBottomBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .disabled(isNavigationChromeDisabled)
        }
        .overlay(alignment: .bottom) {
            #if !G7_APP
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
            #endif
        }
    }

    private func edgeControlShell(
        isLandscape: Bool,
        availableHeight: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let railOnLeading = useLeftHandedGrip
        let railWidth: CGFloat = isPad ? 152 : 136
        let drawerOnLeading = !railOnLeading

        return HStack(spacing: isPad ? 16 : 12) {
            if railOnLeading {
                edgeControlColumn
                    .frame(width: railWidth)
                    .disabled(isNavigationChromeDisabled)
            }

            viewfinderStage(isLandscape: isLandscape, overlaysTopBar: true)

            if !railOnLeading {
                edgeControlColumn
                    .frame(width: railWidth)
                    .disabled(isNavigationChromeDisabled)
            }
        }
        .padding(.horizontal, isPad ? 20 : 12)
        .padding(.vertical, isPad ? 12 : 6)
        .overlay(alignment: drawerOnLeading ? .bottomLeading : .bottomTrailing) {
            #if !G7_APP
            if isShowingLookDrawer {
                lookDrawer(
                    maxHeight: isLandscape
                        ? max(160, min(UIDevice.current.userInterfaceIdiom == .pad ? 460 : 240, availableHeight - 130))
                        : max(180, min(UIDevice.current.userInterfaceIdiom == .pad ? 460 : 360, availableHeight - 190))
                )
                    .frame(
                        maxWidth: min(560, max(280, availableWidth - railWidth - 52)),
                        alignment: drawerOnLeading ? .leading : .trailing
                    )
                    .padding(.leading, drawerOnLeading ? 12 : 160)
                    .padding(.trailing, drawerOnLeading ? 160 : 12)
                    .padding(.bottom, isPad ? 86 : 78)
                    .disabled(isChromeDisabled)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
    }

    private var isChromeDisabled: Bool {
        // Prime-lens setup can remain active while the camera is unavailable
        // (including Simulator), but it does not make local navigation unsafe.
        // Keep the broader Fuji transaction locks in place while allowing the
        // looks drawer to open during that setup-only phase.
        isCaptureLocked || isNavigationChromeDisabled
    }

    /// Capture, save and recovery state. Settings, Roll and Import stay enabled
    /// while a capture is in flight so their tap can explain the wait.
    private var isCaptureLocked: Bool {
        viewModel.isCapturing || viewModel.isSaving || viewModel.hasPendingCapture
    }

    private var isNavigationChromeDisabled: Bool {
        isImporting || shooting.isBusy || shooting.isComposing
    }

    /// A failed save shows the recovery banner; leaving the camera is blocked there.
    private var isNavigationRecoveryLocked: Bool {
        viewModel.hasPendingCapture && !viewModel.isSaving
    }

    private var isShowingOriginalPreview: Bool {
        originalPreviewOverride ?? shooting.settings.showsNaturalPreview
    }

    private func toggleOriginalPreview() {
        originalPreviewOverride = !isShowingOriginalPreview
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
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("camera-placeholder")
            } else if isReviewing {
                Color.black.opacity(0.55)
                    .allowsHitTesting(false)
            }

            if (!shouldShowCameraEmptyState || isViewfinderChromePreview) && !isReviewing {
                HStack {
                    Spacer(minLength: 0)
                    originalPreviewButton
                }
                .padding(.top, overlaysTopBar ? (viewfinderChromeHeights[.top] ?? 54) + 12 : 12)
                .padding(.trailing, 12)
                .disabled(isChromeDisabled)
            }

            if showGrid && camera.isRunning {
                CompositionGrid(guide: compositionGuide)
            }

            if camera.isRunning && !isReviewing {
                CompositionAssistOverlay(
                    store: assists,
                    showHistogram: showHistogram,
                    showLevel: showHorizonLevel,
                    topClearance: overlaysTopBar ? (viewfinderChromeHeights[.top] ?? 54) + 8 : 8,
                    bottomClearance: (viewfinderChromeHeights[.bottom] ?? 52) + 8
                )
                .allowsHitTesting(canTriggerShutter)
            }

            if camera.isRunning && !isReviewing {
                FocusAssistOverlay(camera: camera, size: size,
                                   topClearance: focusAssistTopClearance(overlaysTopBar: overlaysTopBar))
            }
            if let focusPoint {
                // The tap gesture reports locations in the frame's own space,
                // so the reticle lands exactly where the user touched. It stays
                // hit-test transparent so a visible reticle cannot swallow the
                // next focus tap.
                FocusReticle()
                    .overlay(alignment: .bottom) {
                        if camera.manualControls.exposureMode != .manual && !isShowingExposureReadout {
                            Label(CameraPreviewGesturePolicy.exposureReadout(bias: camera.exposureBias, isManualExposure: false),
                                  systemImage: "sun.max.fill")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(FilmyTheme.accent)
                                .padding(4)
                                .background(.black.opacity(0.65), in: Capsule())
                                .offset(y: 28)
                                .accessibilityHidden(true)
                        }
                    }
                    .position(focusPoint)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.15).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .task(id: focusFeedbackRevision) {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled, exposureDragStart == nil else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            self.focusPoint = nil
                        }
                    }
            }
            if isShowingExposureReadout && camera.isRunning && !isReviewing {
                exposureDragReadout
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
                    .disabled(isNavigationChromeDisabled)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ViewfinderChromeHeightKey.self,
                                                   value: [.top: proxy.size.height])
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            viewfinderFooter(width: size.width)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .disabled(isChromeDisabled)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ViewfinderChromeHeightKey.self,
                                               value: [.bottom: proxy.size.height])
                    }
                }
        }
        .onPreferenceChange(ViewfinderChromeHeightKey.self) { heights in
            // Only chrome contributes measurements; the histogram's frame
            // never feeds back into the values used to place it.
            if viewfinderChromeHeights != heights { viewfinderChromeHeights = heights }
        }
        .clipShape(RoundedRectangle(cornerRadius: FilmyTheme.viewfinderCornerRadius, style: .continuous))
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            ZStack {
                // Keep the renderer mounted across camera start/stop so its
                // frame handler and render-status probe retain their lifetime.
                FilteredCameraPreview(
                    camera: camera,
                    recipe: camera.sceneAuto.development.applying(to: viewModel.selectedRecipe),
                    naturalLiveView: isShowingOriginalPreview || isHoldingOriginalPreview,
                    digitalCrop: shooting.settings.previewCrop
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                if !shouldShowCameraEmptyState {
                    FujiViewfinderOverlay(controller: shooting, camera: camera, selectedRecipe: viewModel.selectedRecipe)
                    livePreviewControls(in: proxy.size)
                }
            }
            .onAppear { camera.updateOrientation(for: proxy.size) }
            .onChange(of: proxy.size) { _, size in
                isPinching = false
                previewDragMaySelectLook = nil
                previewDragAxis = nil
                exposureDragStart = nil
                exposureDragCommitted = false
                exposureDragSentBias = nil
                isShowingExposureReadout = false
                camera.updateOrientation(for: size)
            }
        }
    }

    private func livePreviewControls(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Live camera preview")
            .accessibilityValue(isShowingOriginalPreview || isHoldingOriginalPreview
                ? "Showing original preview" : "Showing the \(viewModel.selectedRecipe.name) look")
            .accessibilityHint(CameraPreviewGesturePolicy.previewAccessibilityHint)
            .accessibilityAction(named: "Focus and expose at center") {
                focusPreview(at: CGPoint(x: size.width / 2, y: size.height / 2), in: size)
            }
            .accessibilityAction(named: "Brighten exposure") { adjustPreviewExposure(by: 0.3) }
            .accessibilityAction(named: "Darken exposure") { adjustPreviewExposure(by: -0.3) }
            .accessibilityAction(named: "Next look") { selectAdjacentLook(.next) }
            .accessibilityAction(named: "Previous look") { selectAdjacentLook(.previous) }
            .accessibilityAction(named: isShowingOriginalPreview ? "Show selected look" : "Show original preview") {
                toggleOriginalPreview()
            }
            .accessibilityAction(named: "Switch camera", switchCameraFromPreview)
            .accessibilityIdentifier("camera-preview")
            .gesture(SpatialTapGesture().onEnded { tap in focusPreview(at: tap.location, in: size) })
            .simultaneousGesture(previewLookSwipe(in: size))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($isHoldingOriginalPreview) { value, isHolding, _ in
                        if case .second(true, _) = value { isHolding = true }
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        guard canTriggerShutter, !shooting.settings.lockPrimeLens, !shooting.isComposing else { return }
                        if previewDragMaySelectLook != nil { previewDragMaySelectLook = false }
                        if !isPinching {
                            isShowingExposureReadout = false
                            isPinching = true
                            pinchStartZoom = camera.zoomFactor
                            dismissGestureHint()
                        }
                        camera.setZoom(pinchStartZoom * scale)
                    }
                    .onEnded { _ in
                        isPinching = false
                        pinchStartZoom = camera.zoomFactor
                        suppressLookSwipeUntil = Date(timeIntervalSinceNow: 0.3)
                    }
            )
    }

    private func focusPreview(at location: CGPoint, in size: CGSize) {
        guard canTriggerShutter, !isPinching else { return }
        HapticFeedback.play(.focus)
        let normalizedPoint = normalizedFocusPoint(for: location, in: size)
        camera.focus(at: normalizedPoint)
        focusNormalizedPoint = normalizedPoint
        focusFeedbackRevision += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
            focusPoint = location
        }
    }

    private func switchCameraFromPreview() {
        guard canTriggerShutter, !isPinching, !shooting.settings.lockPrimeLens, !shooting.isComposing, camera.availableCameraPositions.count > 1 else { return }
        switchCamera()
    }

    private func switchCamera() {
        focusPoint = nil
        focusNormalizedPoint = nil
        HapticFeedback.play(.selection)
        camera.toggleCameraPosition()
    }

    private func selectAdjacentLook(_ direction: CameraLookDirection) {
        #if G7_APP
        return
        #else
        guard canTriggerShutter, !isPinching, !shooting.isComposing,
              let recipe = CameraPreviewGesturePolicy.targetRecipe(
                in: viewModel.quickNavigationRecipes, selectedIdentifier: viewModel.effectiveSelectedRecipeID,
                direction: direction
              ) else { return }
        viewModel.select(recipe: recipe)
        HapticFeedback.play(.selection)
        dismissGestureHint()
        #endif
    }

    private var canAdjustPreviewExposure: Bool {
        canTriggerShutter && !isPinching && camera.manualControls.exposureMode != .manual
            && !camera.manualControls.isApplying
    }

    private func adjustPreviewExposure(by delta: Float) {
        guard canAdjustPreviewExposure else { return }
        camera.setExposureBias(camera.exposureBias + delta)
        focusFeedbackRevision += 1
    }

    private func updatePreviewDragAxis(for translation: CGSize) {
        let axis = CameraPreviewGesturePolicy.resolvedDragAxis(
            current: previewDragAxis, translation: translation, exposureCommitted: exposureDragCommitted)
        if axis == .exposure && previewDragAxis != .exposure { exposureDragStart = camera.exposureBias }
        if axis != .exposure { exposureDragStart = nil }
        previewDragAxis = axis
    }

    private func applyPreviewExposureDrag(_ translation: CGSize, in size: CGSize) {
        guard previewDragAxis == .exposure, let start = exposureDragStart,
              let bias = CameraPreviewGesturePolicy.exposureBias(
                start: start, translation: translation, viewportHeight: size.height) else { return }
        if !exposureDragCommitted {
            guard CameraPreviewGesturePolicy.exposureDragReachesCommit(start: start, target: bias) else { return }
            exposureDragCommitted = true
            isShowingExposureReadout = true
        }
        guard canAdjustPreviewExposure,
              CameraPreviewGesturePolicy.exposureDetent(from: camera.exposureBias, to: bias) != nil else { return }
        exposureDragSentBias = bias
        camera.setExposureBias(bias)
        focusFeedbackRevision += 1
    }

    private var exposureDragReadout: some View {
        let isManual: Bool = camera.manualControls.exposureMode == .manual
        let text: String = CameraPreviewGesturePolicy.exposureReadout(bias: camera.exposureBias, isManualExposure: isManual)
        return exposureDragCapsule(text: text)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity)
            .onChange(of: camera.exposureBias) { (old: Float, new: Float) in
                playExposureDragHaptic(from: old, to: new)
            }
            .task(id: previewDragAxis == .exposure) { await lingerExposureReadout() }
    }

    private func exposureDragCapsule(text: String) -> some View {
        Label(text, systemImage: "sun.max.fill")
            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("camera-exposure-drag-readout")
    }

    private func playExposureDragHaptic(from old: Float, to new: Float) {
        guard previewDragAxis == .exposure,
              let detent = CameraPreviewGesturePolicy.exposureDragHaptic(from: old, to: new, sent: exposureDragSentBias)
        else { return }
        HapticFeedback.play(detent == .zero ? .focus : .controlStep)
    }

    private func lingerExposureReadout() async {
        guard previewDragAxis != .exposure else { return }
        try? await Task.sleep(for: CameraPreviewGesturePolicy.exposureReadoutLinger)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isShowingExposureReadout = false }
    }

    /// A system-cancelled drag never calls onEnded. This runs one turn after
    /// the gesture ends, so a normal onEnded has already read previewDragAxis
    /// and reset it; the reset is then a no-op. A newer drag is left alone.
    private func resetCancelledPreviewDrag() {
        guard !isPreviewDragActive else { return }
        let wasInProgress: Bool = previewDragAxis != nil || previewDragMaySelectLook != nil
        previewDragMaySelectLook = nil
        previewDragAxis = nil
        exposureDragStart = nil
        exposureDragCommitted = false
        exposureDragSentBias = nil
        if wasInProgress { focusFeedbackRevision += 1 }
    }

    private func previewLookSwipe(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($isPreviewDragActive) { _, state, _ in
                if !state { state = true }
            }
            .onChanged { value in
                let enabled = canTriggerShutter && !isPinching && Date() >= suppressLookSwipeUntil
                if previewDragMaySelectLook == nil {
                    previewDragMaySelectLook = enabled
                    exposureDragCommitted = false
                    exposureDragSentBias = nil
                }
                if !enabled { previewDragMaySelectLook = false }
                guard previewDragMaySelectLook == true else { return }
                updatePreviewDragAxis(for: value.translation)
                applyPreviewExposureDrag(value.translation, in: size)
            }
            .onEnded { value in
                defer {
                    previewDragMaySelectLook = nil
                    previewDragAxis = nil
                    exposureDragStart = nil
                    exposureDragCommitted = false
                    exposureDragSentBias = nil
                    focusFeedbackRevision += 1
                }
                guard previewDragAxis == .look,
                      let direction = CameraPreviewGesturePolicy.lookDirection(
                    translation: value.translation,
                    viewportWidth: size.width,
                    interactionEnabled: canTriggerShutter && previewDragMaySelectLook == true,
                    includesPinch: isPinching || Date() < suppressLookSwipeUntil
                ) else { return }
                selectAdjacentLook(direction)
            }
    }

    /// Controls that float along the bottom edge of the frame. Zoom stays
    /// immediately available; the broader camera tools appear on demand.
    @ViewBuilder
    private func viewfinderFooter(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            if isShowingLiveAdjustments {
                LiveRecipeControlsView(
                    recipe: viewModel.selectedRecipe,
                    onUpdate: viewModel.update,
                    onReset: { viewModel.reset(recipeID: viewModel.selectedRecipeID) },
                    onClose: { isShowingLiveAdjustments = false }
                )
            }
            if isShowingTools && !isShowingLiveAdjustments && !hidesToolsForRecoveryPlaceholder {
                toolStrip(minWidth: width - 24)
            }

            // Keep the zoom row mounted while the session stops/restarts.
            // Removing it moves the utility rail (and histogram exclusion
            // area) on every foreground transition. Only visibility and
            // interaction depend on camera readiness, never its layout.
            if !isShowingLookDrawer, !isReviewing {
                ZoomPresetBar(
                    value: camera.zoomFactor,
                    minZoom: camera.minZoomFactor,
                    maxZoom: camera.maxZoomFactor,
                    onSelect: { factor in
                        dismissGestureHint()
                        camera.setZoom(factor, reseedTracking: true)
                    },
                    onAdjust: { direction in
                        let delta: CGFloat = direction == .increment ? 0.5 : -0.5
                        camera.setZoom(camera.zoomFactor + delta)
                    }
                )
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) { gestureHintOverlay }
                .opacity(camera.isRunning || isViewfinderChromePreview ? 1 : 0)
                .disabled((!camera.isRunning && !isViewfinderChromePreview)
                    || shooting.settings.lockPrimeLens || shooting.settingsLocked)
                .accessibilityHidden(!camera.isRunning && !isViewfinderChromePreview)
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
        CameraTopBarLayout {
            HStack(spacing: 4) {
                flashControl
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(isCaptureLocked)

                importButton

                Spacer(minLength: 0)

                ViewThatFits(in: .horizontal) {
                    FilmyWordmark(compact: true)
                        .accessibilityHidden(true)
                    Color.clear.frame(width: 0, height: 0)
                }
                .layoutPriority(-1)

                Spacer(minLength: 0)

                fujiMenuButton
                    .disabled(isCaptureLocked)
                captureSetupButton
                    .disabled(isCaptureLocked)
                settingsButton

            }
        } indicators: {
            HStack(spacing: captureFormatToken == nil ? 8 : 4) {
                SceneAutoControl(camera: camera, isBusy: viewModel.isCapturing || viewModel.isSaving || countdown.state.isActive)
                Spacer(minLength: 0)
                smartRecipeEntry.layoutPriority(1)
                Spacer(minLength: 0)
                g7ProfileBadge
                activeCaptureIndicators.layoutPriority(1)
                captureFormatChip.layoutPriority(1)

                if !isLive {
                    CameraStatusPill(
                        isRunning: camera.isRunning,
                        availability: camera.availability,
                        message: camera.statusMessage
                    )
                    .layoutPriority(2)
                }
            }
            .disabled(isCaptureLocked)
        }
    }

    /// Smart looks form depends only on stable layout inputs, never on the changing suggestion name:
    /// the sparkle alone beside a format chip, the adjustments chip or an accessibility text size,
    /// otherwise the named entry when a fixed reference width fits, else the sparkle.
    @ViewBuilder
    private var smartRecipeEntry: some View {
        if captureFormatToken != nil || isActiveAdjustmentsChipVisible || dynamicTypeSize.isAccessibilitySize {
            compactSmartRecipeEntry
        } else {
            ViewThatFits(in: .horizontal) {
                fullSmartRecipeEntry
                    .frame(idealWidth: Self.smartEntryReferenceWidth, maxWidth: 180, alignment: .leading)
                compactSmartRecipeEntry
            }
        }
    }

    /// Sparkle, the text "Smart looks" at the default size and the entry padding.
    private static let smartEntryReferenceWidth: CGFloat = 100

    private var fullSmartRecipeEntry: some View {
        SmartRecipeEntryPoint(
            store: smartRecipes, selectedID: viewModel.selectedRecipeID,
            canApply: canApplySmartRecipe, onOpen: openSmartRecipes,
            onApply: applySmartRecipe, onUndo: undoSmartRecipe
        )
    }

    private var compactSmartRecipeEntry: some View {
        CompactSmartRecipeEntry(
            store: smartRecipes, selectedID: viewModel.selectedRecipeID,
            canApply: canApplySmartRecipe, onOpen: openSmartRecipes,
            onApply: applySmartRecipe, onUndo: undoSmartRecipe
        )
    }

    @ViewBuilder
    private var g7ProfileBadge: some View {
        #if !G7_APP
        if isCompactDigitalMode, isLive, !dynamicTypeSize.isAccessibilitySize {
            Button {
                toggleLookDrawer()
            } label: {
                Text("G7 X")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(FilmyTheme.accent)
                    .padding(.horizontal, 9)
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
                    .background(Color.black.opacity(0.68), in: Capsule())
                    .overlay { Capsule().stroke(FilmyTheme.accent.opacity(0.36), lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("g7x-profile-badge")
            .accessibilityLabel("G7 X Compact profile")
            .accessibilityHint("Opens the looks drawer")
        }
        #endif
    }

    private var isActiveAdjustmentsChipVisible: Bool {
        let hasBias = abs(camera.exposureBias) >= 0.05 && camera.manualControls.exposureMode == .auto
        let hasHold = camera.isFocusExposureLocked || camera.manualControls.isAnyManualModeEnabled
        return !camera.sceneAuto.isEnabled && (hasBias || hasHold)
    }

    @ViewBuilder
    private var activeCaptureIndicators: some View {
        if isActiveAdjustmentsChipVisible {
            Button {
                if camera.manualControls.isAnyManualModeEnabled {
                    isShowingManualControls = true
                    return
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                    isShowingLookDrawer = false
                    isShowingLiveAdjustments = false
                    isShowingTools = true
                }
            } label: {
                activeCaptureIndicatorLines
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(FilmyTheme.accent)
                .padding(.horizontal, 9)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .background(Color.black.opacity(0.68), in: Capsule())
                .overlay { Capsule().stroke(FilmyTheme.accent.opacity(0.36), lineWidth: 1) }
            }
            .buttonStyle(.pressable)
            .contextMenu {
                if hasExposureBiasToReset {
                    Button("Reset exposure") { camera.setExposureBias(0) }
                }
            }
            .accessibilityActions {
                if hasExposureBiasToReset {
                    Button("Reset exposure") { camera.setExposureBias(0) }
                }
            }
            .accessibilityIdentifier("camera-active-adjustments")
            .accessibilityLabel("Active camera adjustments")
            .accessibilityValue(activeCaptureIndicatorValue)
            .accessibilityHint("Shows the camera controls")
        }
    }

    private var activeCaptureIndicatorLines: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                if abs(camera.exposureBias) >= 0.05 && camera.manualControls.exposureMode == .auto {
                    Text(String(format: "%+.1f EV", camera.exposureBias))
                }
                if camera.isFocusExposureLocked {
                    Label("AE/AF LOCK", systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                }
                if camera.manualControls.isAnyManualModeEnabled {
                    Text(visibleManualReadout?.iso ?? "MANUAL")
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 4) {
                    if let readout = visibleManualReadout { Text(readout.shutter) }
                    if let token = captureFormatToken { formatTokenLabel(token) }
                }
            }
        }
    }

    @ViewBuilder
    private var captureFormatChip: some View {
        if let token = captureFormatToken, !isActiveAdjustmentsChipVisible || dynamicTypeSize.isAccessibilitySize {
            Button {
                HapticFeedback.play(.selection)
                isShowingManualControls = true
            } label: {
                formatTokenLabel(token)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(FilmyTheme.accent)
                    .padding(.horizontal, 9)
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                    .background(Color.black.opacity(0.68), in: Capsule())
                    .overlay { Capsule().stroke(FilmyTheme.accent.opacity(0.36), lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityShowsLargeContentViewer { Text(captureFormatSpokenValue) }
            .accessibilityIdentifier("camera-capture-format")
            .accessibilityLabel("Capture format")
            .accessibilityValue(captureFormatSpokenValue)
            .accessibilityHint("Opens Pro controls")
        }
    }

    private var captureFormatToken: String? {
        let settings = camera.proCaptureSettings
        let base: String
        if settings.format.retainsRAW { base = "RAW" }
        else if settings.dynamicRange == .hdr { base = "HDR" }
        else if settings.livePhoto { base = "LIVE" }
        else if settings.format == .jpeg { base = "JPEG" }
        else if settings.resolution != .mp12 { base = "HEIF" }
        else { return nil }
        return settings.resolution == .mp12 ? base : "\(base) \(settings.resolution.rawValue)"
    }

    private var captureFormatSpokenValue: String {
        let settings = camera.proCaptureSettings
        var parts = [settings.format.title]
        if settings.dynamicRange == .hdr { parts.append("HDR") }
        if settings.livePhoto { parts.append("Live Photo") }
        parts.append("\(settings.resolution.rawValue) megapixels")
        if let reason = captureFormatConflictReason { parts.append(reason) }
        return parts.joined(separator: ", ")
    }

    /// Mirrors the service's refusal so the chip never states a format the shutter will not take.
    private var captureFormatConflictReason: String? {
        let capabilities = camera.proCaptureCapabilities
        guard isLive, !capabilities.resolutions.isEmpty else { return nil }
        let settings = camera.proCaptureSettings
        if let reason = capabilities.unavailableReason(for: settings) { return reason }
        return CameraService.customExposureResolutionRefusal(
            customExposure: camera.manualControls.exposureMode == .manual,
            sceneAutoOwnsExposure: camera.sceneAuto.isEnabled,
            resolution: settings.resolution
        )
    }

    private var manualExposureReadout: (iso: String, shutter: String)? {
        let controls = camera.manualControls
        let seconds = controls.exposureDurationSeconds
        guard controls.exposureMode == .manual, controls.iso >= 1, controls.iso.isFinite,
              seconds.isFinite, seconds > 0 else { return nil }
        let reciprocal = (1 / seconds).rounded()
        guard reciprocal.isFinite else { return nil }
        let shutter = seconds >= 0.3
            ? String(format: "%.1fs", seconds)
            : "1/\(max(Int(min(reciprocal, 1_000_000)), 1))"
        return ("ISO \(Int(controls.iso.rounded()))", shutter)
    }

    /// Visible only when exposure is the sole manual mode; otherwise "MANUAL" keeps covering WB and focus.
    private var visibleManualReadout: (iso: String, shutter: String)? {
        let controls = camera.manualControls
        guard controls.whiteBalanceMode != .manual, controls.focusMode != .manual,
              !dynamicTypeSize.isAccessibilitySize else { return nil }
        return manualExposureReadout
    }

    @ViewBuilder
    private func formatTokenLabel(_ token: String) -> some View {
        HStack(spacing: 3) {
            if captureFormatConflictReason != nil {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            Text(token)
        }
    }

    private var hasExposureBiasToReset: Bool {
        abs(camera.exposureBias) >= 0.05 && camera.manualControls.exposureMode == .auto
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
            if let readout = manualExposureReadout {
                values.append(readout.iso)
                values.append("Shutter \(readout.shutter)")
            }
        }
        if camera.manualControls.whiteBalanceMode == .manual {
            values.append("Manual white balance")
        }
        if camera.manualControls.focusMode == .manual {
            values.append("Manual focus")
        }
        if captureFormatToken != nil {
            values.append(captureFormatSpokenValue)
        }
        return values.joined(separator: ", ")
    }

    /// Keep the current flash selection visible in the top corner,
    /// including its full label, even when the tools are hidden.
    @ViewBuilder
    private var flashControl: some View {
        if camera.flashAvailability != .unsupported {
            FlashControl(
                mode: camera.flashMode,
                availability: camera.flashAvailability,
                action: camera.cycleFlashMode
            )
        }
    }

    private var cameraSwitchButton: some View {
        Button {
            switchCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: cameraHitTarget, height: cameraHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(shooting.settings.lockPrimeLens || shooting.settingsLocked)
        .accessibilityIdentifier("camera-switch-control")
        .accessibilityLabel("Switch camera")
        .accessibilityValue(camera.cameraPosition.title)
        .accessibilityHint("Switches between the front and back cameras.")
    }

    private var settingsButton: some View {
        Button {
            if viewModel.isCapturing || viewModel.isSaving {
                onOpenSettings()
                return
            }
            HapticFeedback.play(.selection)
            closeControlDrawers()
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: cameraHitTarget, height: cameraHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(isNavigationRecoveryLocked)
        .accessibilityIdentifier("settings-tab")
        .accessibilityLabel("Open camera settings")
        .accessibilityHint("Shows camera preferences")
    }

    /// What the toggle reports: the rail is suppressed over a recovery placeholder.
    private var isToolRailVisible: Bool {
        isShowingTools && !hidesToolsForRecoveryPlaceholder
    }

    private func toolsToggle(showsCaption: Bool = false) -> some View {
        let captioned = showsCaption && !isToolRailVisible && !dynamicTypeSize.isAccessibilitySize
        return Button {
            HapticFeedback.play(.selection)
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                if !isShowingTools {
                    isShowingLookDrawer = false
                }
                isShowingTools.toggle()
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: isToolRailVisible ? "xmark" : "switch.2")
                    .font(.system(size: 16, weight: .semibold))
                if captioned {
                    Text("Controls")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(isToolRailVisible ? FilmyTheme.accent : .white)
            .frame(width: captioned ? max(60, cameraHitTarget) : cameraHitTarget, height: cameraHitTarget)
            .background { ChromeShapeBackground(shape: Capsule()) }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer {
            Label("Controls", systemImage: isToolRailVisible ? "xmark" : "switch.2")
        }
        .accessibilityIdentifier("camera-chrome-toggle")
        .accessibilityValue(isToolRailVisible ? "Expanded" : "Collapsed")
        .accessibilityLabel(isToolRailVisible ? "Hide camera controls" : "Show camera controls")
        .accessibilityHint(
            isToolRailVisible
                ? "Hides the control strip"
                : "Shows exposure, grid, Pro controls and self-timer"
        )
    }

    // MARK: - Primary controls and look drawer

    private var primaryBottomBar: some View {
        VStack(spacing: 6) {
            // The Controls caption gives way before the look name does on a narrow phone.
            ViewThatFits(in: .horizontal) {
                primaryLookRow(showsCaption: true)
                primaryLookRow(showsCaption: false)
            }
            .disabled(isCaptureLocked)

            HStack(alignment: .center, spacing: 0) {
                rollButton.frame(width: 76)
                Spacer(minLength: 0)
                captureControl
                    .disabled(isCaptureLocked)
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    cameraSwitchButton
                        .disabled(camera.availableCameraPositions.count < 2)
                    Text("Flip")
                        .font(.caption2.weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(FilmyTheme.secondary)
                        .accessibilityHidden(true)
                }
                .frame(width: 76)
                .disabled(isCaptureLocked)
            }
            .frame(minHeight: 80)
        }
        .frame(maxWidth: FilmyLayout.dockMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private func primaryLookRow(showsCaption: Bool) -> some View {
        HStack(spacing: 6) {
            currentRecipeButton()
                .frame(maxWidth: .infinity, alignment: .leading)
            favoriteCurrentLookButton
            toolsToggle(showsCaption: showsCaption)
                .disabled(!camera.isRunning && !isViewfinderChromePreview)
        }
    }

    private var favoriteIDs: Set<String> { LookLibraryIndex.favorites(from: favoriteData) }

    private var favoriteCurrentLookButton: some View {
        let recipe = viewModel.selectedRecipe
        let favorite = favoriteIDs.contains(recipe.id)
        return Button {
            var updated = favoriteIDs
            if favorite { updated.remove(recipe.id) } else { updated.insert(recipe.id) }
            favoriteData = LookLibraryIndex.encodeFavorites(updated)
            HapticFeedback.play(.selection)
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(favorite ? FilmyTheme.accent : FilmyTheme.primary)
                .frame(width: cameraHitTarget, height: max(48, cameraHitTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("camera-favorite-look")
        .accessibilityLabel(favorite ? "Remove \(recipe.name) from favorites" : "Favorite \(recipe.name)")
        .accessibilityValue(favorite ? "Favorite" : "Not favorite")
        .accessibilityHint("Favorites are shared with the look library. This does not change your look.")
    }

    /// Wide layouts use the edge column so the picture remains visually
    /// centered and the primary controls read like a camera grip.
    private var edgeControlColumn: some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        return VStack(spacing: isPad ? 14 : 10) {
            Spacer(minLength: 0)

            VStack(spacing: 8) {
                currentRecipeButton(compact: true)
                captureControl
            }
            .padding(.vertical, 4)
            .disabled(isCaptureLocked)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    rollButton
                    cameraSwitchButton
                        .disabled(camera.availableCameraPositions.count < 2)
                        .disabled(isCaptureLocked)
                }
                HStack(spacing: 8) {
                    favoriteCurrentLookButton
                    toolsToggle()
                        .disabled(!camera.isRunning && !isViewfinderChromePreview)
                }
                .disabled(isCaptureLocked)
            }

            cameraGripToggle
                .disabled(isCaptureLocked)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var cameraGripToggle: some View {
        Button {
            useLeftHandedGrip.toggle()
            HapticFeedback.play(.selection)
        } label: {
            Image(systemName: useLeftHandedGrip ? "hand.point.left.fill" : "hand.point.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FilmyTheme.primary)
                .frame(width: cameraHitTarget, height: cameraHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("camera-grip-toggle")
        .accessibilityLabel("Camera controls position")
        .accessibilityValue(useLeftHandedGrip ? "Left handed" : "Right handed")
        .accessibilityHint(
            useLeftHandedGrip
                ? "Move the camera controls to the right edge"
                : "Move the camera controls to the left edge"
        )
    }

    private func currentRecipeButton(compact: Bool = false) -> some View {
        let layout = compact || dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            CurrentRecipeButton(
                recipe: viewModel.selectedRecipe,
                isCustomized: viewModel.isCustomized(viewModel.selectedRecipe),
                compactLayout: compact,
                action: {
                    #if !G7_APP
                    toggleLookDrawer()
                    #endif
                }
            )
            Button {
                let shouldOpen = !isShowingLiveAdjustments
                guard !shouldOpen || membership.require(.recipeEditing) else { return }
                closeControlDrawers()
                if shouldOpen { originalPreviewOverride = nil }
                isShowingLiveAdjustments = shouldOpen
            } label: {
                Label("Adjust", systemImage: "slider.horizontal.3")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .frame(minHeight: 44)
            }
            .tint(FilmyTheme.accent)
            .accessibilityIdentifier("live-recipe-adjustments")
            .accessibilityHint("Adjust the look while watching the live camera preview")
        }
    }

    private func focusAssistTopClearance(overlaysTopBar: Bool) -> CGFloat {
        let barHeight: CGFloat = viewfinderChromeHeights[.top] ?? 54
        let base: CGFloat = overlaysTopBar ? barHeight + 8 : 8
        let compareHeight: CGFloat = max(56, cameraHitTarget)
        return base + compareHeight + 8
    }

    private var originalPreviewButton: some View {
        Button {
            HapticFeedback.play(.selection)
            toggleOriginalPreview()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 18, weight: .semibold))
                Text(isShowingOriginalPreview ? "Original" : "Compare")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isShowingOriginalPreview ? FilmyTheme.accent : .white)
            .frame(width: max(60, cameraHitTarget), height: max(56, cameraHitTarget))
            .background { ChromeShapeBackground(shape: RoundedRectangle(cornerRadius: 14)) }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("camera-original-preview-toggle")
        .accessibilityLabel(isShowingOriginalPreview ? "Show selected look" : "Show original preview")
        .accessibilityValue(isShowingOriginalPreview ? "Original" : "Selected look")
        .accessibilityHint("Compare the live camera preview without changing the selected look or saved photo")
    }

    private func lookDrawer(maxHeight: CGFloat) -> some View {
        // Header, filters, footer, three gaps, and outer padding must all
        // fit before assigning the remaining height to scrolling recipes.
        let showsSearch = maxHeight >= 340
        let chromeHeight = 64 + cameraHitTarget + max(48, cameraHitTarget) + 38 + (showsSearch ? 50 : 0)
        let active = viewModel.quickRecipes
        let visible = active.filter { recipe in
            (!favoritesOnly || favoriteIDs.contains(recipe.id))
                && (!showsSearch || quickRecipeQuery.isEmpty
                    || RecipeCatalog.searchText(for: recipe).localizedStandardContains(quickRecipeQuery))
        }

        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow(
                        text: recipeEyebrow,
                        color: isCompactDigitalMode ? FilmyTheme.accent : FilmyTheme.filmAccent
                    )
                    Text("Looks")
                        .font(.system(.title3).weight(.bold))
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
                        .frame(minHeight: 64)
                        .background(FilmyTheme.panel, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Tune \(viewModel.selectedRecipe.name)")

                Button(action: toggleLookDrawer) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FilmyTheme.secondary)
                        .frame(width: cameraHitTarget, height: cameraHitTarget)
                        .background(FilmyTheme.panel, in: Circle())
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("recipe-drawer-close")
                .accessibilityLabel("Close look picker")
            }
            .padding(.horizontal, 8)
            .layoutPriority(1)

            HStack(spacing: 8) {
                Button {
                    favoritesOnly = false
                    HapticFeedback.play(.selection)
                } label: {
                    Text("Active \(active.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(!favoritesOnly ? FilmyTheme.primary : FilmyTheme.secondary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: cameraHitTarget, minHeight: cameraHitTarget)
                        .overlay(alignment: .bottom) {
                            if !favoritesOnly { FilmRegistration() }
                        }
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("camera-looks-all")
                .accessibilityAddTraits(!favoritesOnly ? .isSelected : [])
                Button {
                    favoritesOnly = true
                    HapticFeedback.play(.selection)
                } label: {
                    Label("Favorites", systemImage: "heart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(favoritesOnly ? FilmyTheme.primary : FilmyTheme.secondary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: cameraHitTarget, minHeight: cameraHitTarget)
                        .overlay(alignment: .bottom) {
                            if favoritesOnly { FilmRegistration() }
                        }
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("camera-looks-favorites")
                .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)

            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(FilmyTheme.secondary)
                    TextField("Search active looks", text: $quickRecipeQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .accessibilityIdentifier("camera-looks-search")
                    if !quickRecipeQuery.isEmpty {
                        Button {
                            quickRecipeQuery = ""
                        } label: {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            }

            if visible.isEmpty {
                Text(active.isEmpty ? "Your quick menu is empty. Open Packs to add looks."
                     : favoritesOnly ? "No active favorites match. Manage them in Packs."
                     : "No active looks match your search.")
                    .font(.subheadline)
                    .foregroundStyle(FilmyTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .accessibilityIdentifier(favoritesOnly ? "camera-favorites-empty" : "camera-looks-empty")
            } else {
                RecipePickerView(
                    recipes: visible,
                    selectedRecipeID: Binding(get: { viewModel.effectiveSelectedRecipeID }, set: { id in
                        viewModel.select(recipe: viewModel.recipe(for: id))
                        originalPreviewOverride = nil
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            isShowingLookDrawer = false
                        }
                    }),
                    onOpenDetail: openRecipeDetail,
                    compact: !favoritesOnly
                )
                .frame(maxHeight: max(maxHeight - chromeHeight, 70))
                .id(favoritesOnly)
            }

            HStack(spacing: 8) {
                Button {
                    HapticFeedback.play(.selection)
                    isShowingLookLibrary = true
                } label: {
                    Label("Browse all", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity, minHeight: max(48, cameraHitTarget))
                        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("look-library-open")
                .accessibilityHint("Browse and search all \(viewModel.recipes.count) looks, including hidden recipes")
                Button {
                    HapticFeedback.play(.selection)
                    isShowingRecipeManager = true
                } label: {
                    Label("Packs", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity, minHeight: max(48, cameraHitTarget))
                        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("camera-recipe-packs")
                .accessibilityHint("Choose the packs and individual looks in your quick menu")
            }
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(FilmyTheme.accent)
            .buttonStyle(.pressable)
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
                isCapturing: viewModel.isCapturing || shooting.isBusy,
                isEnabled: !camera.manualControls.isApplying && framingIsReady && !shooting.settingUpPrime && shooting.validationMessage == nil,
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
            if viewModel.isCapturing || viewModel.isSaving {
                onOpenGallery()
                return
            }
            closeControlDrawers()
            onOpenGallery()
        } label: {
            VStack(spacing: 3) {
                RollThumbnail(asset: photoLibrary.galleryAssets.first, photoLibrary: photoLibrary)
                Text("Roll")
                    .font(.caption2.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(FilmyTheme.secondary)
            }
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isNavigationRecoveryLocked)
        .accessibilityIdentifier("roll-tab")
        .accessibilityLabel("Open roll")
        .accessibilityHint("Shows the frames you have kept")
    }

    private var importButton: some View {
        Button {
            if viewModel.isCapturing || viewModel.isSaving {
                onImportPhoto()
                return
            }
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
            .frame(width: cameraHitTarget, height: cameraHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isImporting || isNavigationRecoveryLocked)
        .accessibilityLabel(isImporting ? "Importing photo" : "Import photo")
        .accessibilityHint("Choose a photo and apply the current film recipe")
        .accessibilityIdentifier("import-photo")
    }

    // MARK: - Tool strips

    private static let toolStripFadeWidth: CGFloat = 16

    /// Fades the trailing edge so a clipped tool reads as "more to scroll". Taller than the strip so shadows survive.
    private var toolStripFadeMask: some View {
        HStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.toolStripFadeWidth)
        }
        .padding(.vertical, -12)
    }

    private func toolStrip(minWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ExposureControl(value: camera.exposureBias, onReset: {
                    camera.setExposureBias(0)
                }) { direction in
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

                timerControl
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .padding(.trailing, Self.toolStripFadeWidth)
            .frame(minWidth: max(minWidth, 0))
        }
        .scrollClipDisabled()
        .mask { toolStripFadeMask }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isCompactDigitalMode ? "g7x-capture-controls" : "camera-utility-rail"
        )
        .accessibilityLabel(isCompactDigitalMode ? "Compact camera controls" : "Camera controls")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var proControlsButton: some View {
        Button {
            HapticFeedback.play(.selection)
            isShowingManualControls = true
        } label: {
            Label("Pro", systemImage: "slider.horizontal.3")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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

    private var timerControl: some View {
        let delay = captureDelay
        let isArmed = delay != .off
        return Button {
            guard membership.require(.captureSetup) else { return }
            HapticFeedback.play(.selection)
            let all = CaptureDelay.allCases
            let index = all.firstIndex(of: delay) ?? 0
            storedCaptureDelay = all[(index + 1) % all.count]
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .bold))
                if isArmed {
                    Text(delay.title)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .foregroundStyle(isArmed ? FilmyTheme.background : .white)
            .padding(.horizontal, isArmed ? 12 : 0)
            .frame(minWidth: FilmyTheme.toolControlHeight, minHeight: FilmyTheme.toolControlHeight)
            .background {
                if isArmed {
                    Capsule().fill(FilmyTheme.accent)
                } else {
                    ChromeShapeBackground(shape: Capsule())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer { Label("Timer \(delay.title)", systemImage: "timer") }
        .accessibilityIdentifier("timer-control")
        .accessibilityLabel("Self-timer")
        .accessibilityValue(isArmed ? "\(delay.rawValue) seconds" : "Off")
        .accessibilityAddTraits(isArmed ? .isSelected : [])
        .accessibilityHint("Cycles between off, 3, 5 and 10 seconds")
        .accessibilityActions {
            if isArmed {
                Button("Turn timer off") { storedCaptureDelay = .off }
            }
        }
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
        .accessibilityLabel("Composition grid")
        .accessibilityValue(showGrid ? "On" : "Off")
    }

    // MARK: - State

    private var shouldShowCameraEmptyState: Bool {
        !camera.isRunning
    }

    /// The rail would cover the placeholder's only recovery action.
    private var hidesToolsForRecoveryPlaceholder: Bool {
        if isViewfinderChromePreview || camera.isRunning { return false }
        switch camera.availability {
        case .interrupted, .needsRecovery, .unavailable, .permissionDenied:
            return true
        default:
            return false
        }
    }

    private var isImporting: Bool {
        viewModel.isImporting || isImportInProgress
    }

    private var isReviewing: Bool {
        viewModel.isReviewingImport
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
                action: resumeCamera
            )
        case .needsRecovery:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                message: camera.statusMessage,
                actionTitle: "Resume Camera",
                action: resumeCamera
            )
        case .unavailable:
            PreviewPlaceholder(
                isSimulator: false,
                recipe: viewModel.selectedRecipe,
                message: camera.statusMessage,
                actionTitle: "Resume Camera",
                action: resumeCamera
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

    // MARK: - Smart recipe suggestions

    private var canApplySmartRecipe: Bool {
        scenePhase == .active && isCameraTabActive && camera.isRunning
            && camera.availability == .running && !isChromeDisabled && !isReviewing
            && viewModel.reviewImage == nil && !countdown.state.isActive && !camera.manualControls.isApplying
    }

    private var isSmartRecipeAnalysisActive: Bool {
        smartRecipes.isEnabled && canTriggerShutter && !isShowingLookDrawer
            && !isShowingLiveAdjustments
    }

    private var smartRecipeFrameKey: [String] {
        [camera.cameraPosition.rawValue, camera.selectedLensID ?? "", String(describing: camera.zoomFactor),
         String(describing: camera.previewViewportSize), String(describing: camera.previewRotationAngle),
         String(camera.previewMirrored)]
    }

    private func updateSmartRecipeAnalysis() {
        let favorites = (try? JSONDecoder().decode(Set<String>.self, from: favoriteData)) ?? []
        smartRecipes.configure(camera: camera, active: isSmartRecipeAnalysisActive,
                               recipes: viewModel.recipes, favoriteIDs: favorites)
    }

    private func openSmartRecipes() {
        guard !isChromeDisabled, !countdown.state.isActive else { return }
        smartPresentation = smartRecipes.snapshot
        closeControlDrawers()
        isShowingSmartRecipes = true
    }

    private func applySmartRecipe(_ id: String) {
        guard smartRecipes.isEnabled, canApplySmartRecipe,
              let recipe = viewModel.recipes.first(where: { $0.id == id }) else { return }
        smartRecipes.recordSelection(previousID: viewModel.selectedRecipeID, appliedID: recipe.id)
        viewModel.select(recipe: recipe)
        isShowingSmartRecipes = false
    }

    private func undoSmartRecipe() {
        guard canApplySmartRecipe,
              let id = smartRecipes.undo?.target(currentID: viewModel.selectedRecipeID,
                                                 availableIDs: Set(viewModel.recipes.map(\.id))),
              let recipe = viewModel.recipes.first(where: { $0.id == id }) else { return }
        smartRecipes.clearUndo()
        viewModel.select(recipe: recipe)
    }

    // MARK: - Actions

    private func capture() {
#if DEBUG
        if hardwareShutterDiagnosticsEnabled {
            hardwareShutterActionCount += 1
            hardwareShutterCaptureReadiness = "ready=\(canTriggerShutter);blocker=\(hardwareShutterBlockingReason)"
        }
#endif
        guard canTriggerShutter else { return }
        HapticFeedback.play(.capture)
        dismissGestureHint()
        closeLookAndAdjustDrawers()
        if captureDelay == .off {
            performShutterCapture()
        } else {
            countdown.start(seconds: captureDelay.rawValue) {
                // The gate closed during the countdown: no capture, but tell the user.
                guard canTriggerShutter else {
                    HapticFeedback.play(.warning)
                    return
                }
                performShutterCapture()
            }
        }
    }

    private static var gestureHintSuppressed: Bool {
        let process = ProcessInfo.processInfo
        return process.arguments.contains { $0.hasPrefix("-ui-testing") } || process.environment["XCTestConfigurationFilePath"] != nil
    }

    private var gestureHintText: String {
        #if G7_APP
        return "Pinch to zoom"
        #else
        return "Swipe for looks \u{00B7} Pinch to zoom"
        #endif
    }

    private var showsGestureHint: Bool {
        !gestureHintSeen && !Self.gestureHintSuppressed && camera.isRunning && !isReviewing
    }

    @ViewBuilder
    private var gestureHintOverlay: some View {
        if showsGestureHint {
            Text(gestureHintText)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(FilmyTheme.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.68), in: Capsule())
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .alignmentGuide(.top) { dimensions in dimensions[.bottom] + 8 }
                .transition(gestureHintTransition)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(gestureHintText)
                .accessibilityIdentifier("camera-gesture-hint")
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    dismissGestureHint()
                }
        }
    }

    private var gestureHintTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom))
    }

    private func dismissGestureHint() {
        guard !gestureHintSeen else { return }
        withAnimation(.easeOut(duration: 0.2)) { gestureHintSeen = true }
    }

    private func performShutterCapture() {
        if shooting.needsCoordinator {
            shooting.capture(camera: camera, viewModel: viewModel, photoLibrary: photoLibrary)
        } else {
            viewModel.capture(camera: camera, photoLibrary: photoLibrary)
        }
    }

    private var fujiMenuButton: some View {
        Button {
            closeControlDrawers()
            isShowingFujiMenu = true
        } label: {
            Text("Q").font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(shooting.needsCoordinator ? FilmyTheme.filmAccent : .white)
                .frame(width: cameraHitTarget, height: cameraHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Open Q shooting menu")
        .accessibilityIdentifier("fuji-q-menu")
    }

    private func closeControlDrawers() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isShowingLookDrawer = false
            isShowingLiveAdjustments = false
            isShowingTools = false
        }
    }

    /// The shutter leaves the control strip where the user set it.
    private func closeLookAndAdjustDrawers() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isShowingLookDrawer = false
            isShowingLiveAdjustments = false
        }
    }

    private func openRecipeDetail(_ recipe: FilmRecipe) {
        guard !shooting.isComposing, membership.require(.recipeEditing) else { return }
        closeControlDrawers()
        recipeForDetail = viewModel.recipe(for: recipe.id)
    }

    private func toggleLookDrawer() {
        guard !shooting.isComposing else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
            if !isShowingLookDrawer {
                isShowingLiveAdjustments = false
                isShowingTools = false
            }
            isShowingLookDrawer.toggle()
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

    private func resumeCamera() {
        guard scenePhase == .active, isCameraTabActive, !isImporting else { return }
        if !viewModel.isReviewingImport {
            camera.setFrameDeliveryPaused(false)
        }
        camera.start()
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
            hasReview: viewModel.isReviewingImport,
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
            camera.setFrameDeliveryPaused(false)
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

        let factor = CGFloat(shooting.settings.previewCrop)
        let croppedPoint = CGPoint(x: 0.5 + (rotatedPreviewPoint.x - 0.5) / factor,
                                   y: 0.5 + (rotatedPreviewPoint.y - 0.5) / factor)
        return CameraService.captureDevicePoint(
            fromRotatedPreviewPoint: croppedPoint,
            rotationAngle: camera.previewRotationAngle,
            mirrored: camera.previewMirrored
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Sparkle-only Smart looks for a crowded indicator row. Same actions, labels and identifiers as `SmartRecipeEntryPoint`.
private struct CompactSmartRecipeEntry: View {
    @ObservedObject var store: SmartRecipeStore
    let selectedID: String
    let canApply: Bool
    let onOpen: () -> Void
    let onApply: (String) -> Void
    let onUndo: () -> Void

    var body: some View {
        let top = store.options.first
        HStack(spacing: 0) {
            Button(action: onOpen) {
                Image(systemName: "sparkles")
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(SmartRecipeEntryCopy.openerLabel)
            .accessibilityValue(store.status.entryValue)
            .accessibilityHint(SmartRecipeEntryCopy.openerHint)
            .accessibilityIdentifier("smart-recipes-open")
            if store.undo?.appliedID == selectedID {
                Button(action: onUndo) {
                    Text("Undo").frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .disabled(!canApply)
                .accessibilityLabel("Undo smart look")
                .accessibilityIdentifier("smart-recipes-undo")
            } else if let option = top, option.id != selectedID {
                Button { onApply(option.id) } label: {
                    Text("Use").frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .disabled(!canApply)
                .accessibilityLabel(SmartRecipeEntryCopy.quickApplyTitle(option.recipe.name))
                .accessibilityIdentifier("smart-recipes-quick-apply")
            }
        }
        .font(.caption2.weight(.bold))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(FilmyTheme.accent)
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .contain)
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
        // Constrain the aspect-fill image before clipping, so portrait and
        // landscape photos cannot draw over the Roll label below it.
        .frame(width: 44, height: 44)
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
    private var isShootingSessionActive: Bool {
        scenePhase == .active && isCameraTabActive && camera.isRunning && camera.availability == .running
            && !isReviewing && !isImporting
    }
    private var isCameraVisibleForAssists: Bool {
        scenePhase == .active && isCameraTabActive && camera.isRunning && camera.availability == .running && !isReviewing && !isImporting
            && !viewModel.isCapturing && recipeForDetail == nil && !isShowingLookLibrary && !isShowingRecipeManager
            && !isShowingManualControls && !isShowingCaptureSetup
            && !isShowingFujiMenu
            && !isShowingSmartRecipes
    }
    private var canTriggerShutter: Bool {
        isCameraVisibleForAssists && viewModel.reviewImage == nil && !viewModel.isSaving && !camera.manualControls.isApplying
            && !countdown.state.isActive && framingIsReady && !shooting.isBusy && !shooting.settingUpPrime
            && !camera.isFujiCapturing && !isShowingFujiMenu && shooting.validationMessage == nil
    }
#if DEBUG
    private var hardwareShutterDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private var hardwareShutterBlockingReason: String {
        if scenePhase != .active { return "scene-inactive" }
        if !isCameraTabActive { return "camera-tab-inactive" }
        if !camera.isRunning { return "camera-not-running" }
        if camera.availability != .running { return "availability-\(camera.availability.rawValue)" }
        if isReviewing { return "reviewing" }
        if isImporting { return "importing" }
        if viewModel.isCapturing { return "capturing" }
        if recipeForDetail != nil { return "recipe-detail" }
        if isShowingLookLibrary { return "look-library" }
        if isShowingManualControls { return "manual-controls" }
        if isShowingCaptureSetup { return "capture-setup" }
        if viewModel.reviewImage != nil { return "review-image" }
        if viewModel.isSaving { return "saving" }
        if camera.manualControls.isApplying { return "manual-controls-applying" }
        if countdown.state.isActive { return "countdown-active" }
        if !framingIsReady { return "framing-not-ready" }
        return "none"
    }

    private var hardwareShutterDiagnosticsValue: String {
        "ready=\(canTriggerShutter);blocker=\(hardwareShutterBlockingReason);events=\(hardwareShutterEventCount);lastPhase=\(hardwareShutterLastPhase);actions=\(hardwareShutterActionCount);eventReady=\(hardwareShutterEventReadiness);captureReady=\(hardwareShutterCaptureReadiness);capture=\(viewModel.captureTimingStatus)"
    }

    private var hardwareShutterDiagnostics: some View {
        Text(hardwareShutterDiagnosticsValue)
            .accessibilityElement()
            .accessibilityIdentifier("camera-hardware-shutter-status")
            .accessibilityLabel("Hardware shutter status")
            .accessibilityValue(hardwareShutterDiagnosticsValue)
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
    }
#endif
    private var framingIsReady: Bool {
        guard captureAspect != .viewfinder else { return true }
        let viewport = camera.previewViewportSize
        guard viewport.width > 0, viewport.height > 0,
              let ratio = captureAspect.ratio(isLandscape: viewport.width > viewport.height) else { return false }
        return abs(Double(viewport.width / viewport.height) - ratio) < 0.015
    }
    private var assistOptions: CompositionAssistStore.Options {
        .init(histogram: showHistogram, zebras: showZebras, peaking: showFocusPeaking, level: showHorizonLevel, digitalCrop: shooting.settings.previewCrop)
    }
    private func updateCompositionAssists() {
        assists.configure(camera: camera, options: assistOptions, active: isCameraVisibleForAssists)
    }
    private var captureSetupBadgeText: String? {
        var parts: [String] = []
        if captureAspect != .viewfinder { parts.append(captureAspect.title) }
        if captureDelay != .off { parts.append(captureDelay.title) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    @ViewBuilder
    private var captureSetupBadge: some View {
        if let text = captureSetupBadgeText {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(FilmyTheme.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.72), in: Capsule())
                .offset(y: 5)
                .accessibilityHidden(true)
        }
    }

    private var captureSetupButton: some View {
        Button {
            closeControlDrawers()
            isShowingCaptureSetup = true
        } label: {
            Image(systemName: captureDelay == .off ? "viewfinder" : "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(captureDelay == .off ? FilmyTheme.primary : FilmyTheme.accent)
                .frame(width: cameraHitTarget, height: cameraHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .overlay(alignment: .bottom) { captureSetupBadge }
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
#if DEBUG
    let onEventPhase: (String) -> Void
#endif
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onCameraCaptureEvent(isEnabled: enabled) { event in
#if DEBUG
                onEventPhase(String(describing: event.phase))
#endif
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
    @AppStorage("captureFinish") private var finish = PhotoFinish.photo
    @AppStorage("compositionGuide") private var guide = CompositionGuide.thirds
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("showHistogram") private var histogram = false
    @AppStorage("showZebras") private var zebras = false
    @AppStorage("showFocusPeaking") private var peaking = false
    @AppStorage("showHorizonLevel") private var level = false
    @AppStorage(HistogramPlacement.horizontalPreferenceKey) private var histogramPositionX = 0.0
    @AppStorage(HistogramPlacement.verticalPreferenceKey) private var histogramPositionY = 0.0

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
                    Picker("Photo finish", selection: $finish) {
                        Text("Photo").tag(PhotoFinish.photo)
                        Text("Instant Print").tag(PhotoFinish.instantPrint)
                    }.accessibilityIdentifier("capture-finish-picker")
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
                    if histogram {
                        Button("Reset histogram position") {
                            histogramPositionX = 0
                            histogramPositionY = 0
                        }
                        .accessibilityIdentifier("capture-histogram-reset")
                    }
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
            .accessibilityIdentifier("capture-setup-form")
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
    let topClearance: CGFloat
    let bottomClearance: CGFloat
    @AppStorage(HistogramPlacement.horizontalPreferenceKey) private var histogramPositionX = 0.0
    @AppStorage(HistogramPlacement.verticalPreferenceKey) private var histogramPositionY = 0.0
    @GestureState private var dragTranslation = CGSize.zero

    private var savedPosition: CGPoint {
        HistogramPlacement.sanitized(CGPoint(x: histogramPositionX, y: histogramPositionY))
    }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Zebras and the level must never consume tap-to-focus or pinch zoom.
        // Hit testing is enabled only on the histogram card added below.
        .allowsHitTesting(false)
        .overlay {
            if showHistogram, !store.histogram.isEmpty {
                GeometryReader { proxy in
                    let placement = HistogramPlacement(viewport: proxy.size,
                                                       topClearance: topClearance,
                                                       bottomClearance: bottomClearance)
                    histogramCard(size: placement.cardSize)
                        .frame(width: placement.cardSize.width, height: placement.cardSize.height)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .gesture(
                            DragGesture(minimumDistance: 3, coordinateSpace: .named("histogram-viewfinder"))
                                .updating($dragTranslation) { value, translation, _ in
                                    translation = value.translation
                                }
                                .onEnded { value in
                                    let center = placement.center(normalizedPosition: savedPosition,
                                                                  translation: value.translation)
                                    savePosition(placement.normalizedPosition(for: center, fallback: savedPosition))
                                }
                        )
                        .contextMenu {
                            Button("Reset histogram position", systemImage: "arrow.uturn.backward", action: resetPosition)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("camera-histogram")
                        .accessibilityLabel("Preview luminance histogram. \(String(format: "%.1f", store.clippingPercent)) percent highlight warning")
                        .accessibilityValue("Horizontal \(Int(savedPosition.x * 100)) percent, vertical \(Int(savedPosition.y * 100)) percent")
                        .accessibilityHint("Drag to move. Touch and hold to reset the position. Movement actions are also available.")
                        .accessibilityAction(named: "Reset histogram position", resetPosition)
                        .accessibilityAction(named: "Move histogram left") { moveBy(x: -0.1, y: 0) }
                        .accessibilityAction(named: "Move histogram right") { moveBy(x: 0.1, y: 0) }
                        .accessibilityAction(named: "Move histogram up") { moveBy(x: 0, y: -0.1) }
                        .accessibilityAction(named: "Move histogram down") { moveBy(x: 0, y: 0.1) }
                        .position(placement.center(normalizedPosition: savedPosition, translation: dragTranslation))
                }
                .coordinateSpace(name: "histogram-viewfinder")
            }
        }
    }

    private func histogramCard(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if size.height >= 32 {
                HStack(spacing: 3) {
                    Text("PREVIEW LUMA")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                }
                .font(.system(size: 9, weight: .bold))
            }
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
            }
            .frame(maxHeight: 36)
            if size.height >= 56 {
                Text(String(format: "Highlights %.1f%%", store.clippingPercent)).font(.system(size: 9))
            }
        }
        .foregroundStyle(.white)
        .padding(min(8, size.height / 4))
    }

    private func savePosition(_ point: CGPoint) {
        let point = HistogramPlacement.sanitized(point)
        histogramPositionX = point.x
        histogramPositionY = point.y
    }

    private func resetPosition() { savePosition(.zero) }

    private func moveBy(x: CGFloat, y: CGFloat) {
        savePosition(CGPoint(x: savedPosition.x + x, y: savedPosition.y + y))
    }
}
