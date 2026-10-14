import Foundation
import AVKit
import SwiftUI
import UIKit
import Observation

enum CameraActivityAction: Equatable {
    case start
    case stop
    /// Keep the session warm for a short grace period so a quick return
    /// (Retake, back from the Roll or Settings) shows a live viewfinder at
    /// once; the session is released if the user stays away.
    case stopAfterGrace
    case hold
}

/// First-run camera tips, one at a time in the gesture-hint slot. Wording follows
/// CameraPreviewGesturePolicy: swipe = look, hold = original, vertical drag = exposure, tap = focus.
enum CameraGestureTip: Int, CaseIterable, Hashable, Sendable {
    case swipe, hold, drag, tap

    var text: String {
        switch self {
        case .swipe: return "Swipe for looks \u{00B7} Pinch to zoom"
        case .hold: return "Hold to see the original"
        case .drag: return "Drag up or down for brightness"
        case .tap: return "Tap to focus"
        }
    }

    /// Time on screen, counted from insertion (includes the 1 s fade-in delay).
    var duration: Duration { self == .swipe ? .seconds(8) : .seconds(6) }

    /// Next tip after `current` not in `skipped`; nil ends the sequence.
    static func next(after current: CameraGestureTip, skipped: Set<CameraGestureTip>) -> CameraGestureTip? {
        allCases.first { $0.rawValue > current.rawValue && !skipped.contains($0) }
    }
}

/// Tip progress for this app run. Outside CameraScreen because ContentView rebuilds it on every
/// tab switch. Memory only: no settings key (AGENTS.md settings contract).
@MainActor @Observable
final class CameraGestureTipProgress {
    static let shared = CameraGestureTipProgress()
    private(set) var tip: CameraGestureTip? = .swipe
    private(set) var learned: Set<CameraGestureTip> = []

    /// Moves past the current tip; true when the sequence has ended.
    @discardableResult
    func advance(alsoSkipping unavailable: Set<CameraGestureTip> = []) -> Bool {
        guard let current = tip else { return true }
        tip = CameraGestureTip.next(after: current, skipped: learned.union(unavailable))
        return tip == nil
    }

    /// Records a performed gesture; true when it is the tip on screen.
    func noteUsed(_ used: CameraGestureTip) -> Bool {
        learned.insert(used)
        return tip == used
    }

    func reset() {
        tip = .swipe
        learned = []
    }
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

    /// On iPhone a `.large` sheet hides the viewfinder, so its frames can be
    /// skipped. At regular width (iPad) the sheet is a form sheet and the
    /// finder stays visible around it.
    static func sheetCoversViewfinder(fullHeightSheetOpen: Bool, isCompactWidth: Bool) -> Bool {
        fullHeightSheetOpen && isCompactWidth
    }

    /// Only an explicit compact width counts; a nil size class never pauses.
    static func isCompactWidth(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .compact
    }

    /// The single decision for pausing preview frame delivery while the
    /// session keeps running: an import, an import review, or a covering sheet.
    static func pausesFrameDelivery(isImporting: Bool, hasImportReview: Bool, coveredBySheet: Bool) -> Bool {
        isImporting || hasImportReview || coveredBySheet
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

/// Height of the open tool strip, so the gesture tip can tell one row from two.
private struct ToolStripHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum SavedFrameAnchor: Hashable, Sendable { case viewfinder, rollThumbnail }

private struct SavedFrameAnchorKey: PreferenceKey {
    // Computed: Anchor is not guaranteed Sendable, and a stored static would trip Swift 6.
    static var defaultValue: [SavedFrameAnchor: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [SavedFrameAnchor: Anchor<CGRect>],
                       nextValue: () -> [SavedFrameAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The look name shown briefly mid-viewfinder after a swipe or a drawer pick.
private struct LookFlash: Equatable {
    let name: String
    let position: String?
    let id = UUID()
}

@MainActor
private final class CompositionAssistStoreBox: ObservableObject {
    let store = CompositionAssistStore()
}

/// The preview aids the Aids tray toggles. Preview only: none reach saved pixels.
private enum CameraAid: CaseIterable, Identifiable {
    case level
    case histogram
    case zebras
    case peaking
    case loupe

    var id: Self { self }

    var title: String {
        switch self {
        case .level: return "Level"
        case .histogram: return "Histogram"
        case .zebras: return "Zebras"
        case .peaking: return "Peaking"
        case .loupe: return "Loupe"
        }
    }

    var symbol: String {
        switch self {
        case .level: return "level"
        case .histogram: return "chart.bar.xaxis"
        case .zebras: return "circle.lefthalf.striped.horizontal"
        case .peaking: return "scribble.variable"
        case .loupe: return "plus.magnifyingglass"
        }
    }

    var identifier: String {
        switch self {
        case .level: return "aids-level-toggle"
        case .histogram: return "aids-histogram-toggle"
        case .zebras: return "aids-zebras-toggle"
        case .peaking: return "aids-peaking-toggle"
        case .loupe: return "aids-loupe-toggle"
        }
    }
}

/// VoiceOver focus targets around the Aids button and tray.
private enum CameraAidsFocus: Hashable {
    case button
    case close
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var proControlsOpeningSection: ProControlsSection = .top
    @AppStorage(G7DateStampPreferences.enabledKey) private var dateStampEnabled = false
    @State private var dateStampNotice: String?
    @State private var dateStampNoticeTask: Task<Void, Never>?
    @State private var isShowingLiveAdjustments = false
    @State private var isShowingLookDrawer = false
    @State private var isShowingPendingOriginals = false
    @AppStorage("cameraGestureHintSeen.v1") private var gestureHintSeen = false
    private var gestureTips: CameraGestureTipProgress { .shared }
    @State private var originalPreviewOverride: Bool?
    @GestureState private var isHoldingOriginalPreview = false
    @GestureState private var isPreviewDragActive = false
    @State private var isShowingLookLibrary = false
    @State private var isShowingRecipeManager = false
    @State private var quickRecipeQuery = ""
    @State private var isSearchingLooks = false
    @FocusState private var isLookSearchFocused: Bool
    @State private var lookStripHeight: CGFloat = 0
    @State private var lookStripActive: [FilmRecipe] = []
    /// Whole catalog for the Favorites segment and search. Loaded on demand, cleared when the drawer closes.
    @State private var lookStripCatalog: [FilmRecipe] = []
    @State private var lookSearchResults: [FilmRecipe] = []
    @State private var lookStripRecent: [FilmRecipe] = []
    @State private var focusPoint: CGPoint?
    @State private var focusNormalizedPoint: CGPoint?
    /// Measured from the open tool strip (taller than two controls means two rows). Kept across hides.
    @State private var isToolStripTwoRows = false
    /// The Aids tray replaces the tool strip in its slot while true.
    @State private var isShowingAidsTray = false
    @AccessibilityFocusState private var aidsFocus: CameraAidsFocus?
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isPinching = false
    @State private var previewDragMaySelectLook: Bool?
    @State private var previewDragAxis: CameraPreviewDragAxis?
    @State private var exposureDragStart: Float?
    @State private var isShowingExposureReadout = false
    @State private var lookFlash: LookFlash?
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
            .ignoresSafeArea(.keyboard, edges: .bottom)
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
                        toastRow(message: toastMessage)
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
                    } else if showsPendingExportsCard {
                        pendingExportsNotice
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
        .overlayPreferenceValue(SavedFrameAnchorKey.self) { anchors in
            SavedFrameLandingOverlay(anchors: anchors, notice: viewModel.savedFrameNotice)
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
        .sheet(isPresented: $isShowingPendingOriginals, onDismiss: reconcilePendingExports) {
            pendingOriginalsSheet
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
        .sheet(isPresented: $isShowingSmartRecipes, onDismiss: { smartPresentation = nil }) { [snapshot = smartPresentation] in
            // The body must read the snapshot, or the sheet keeps a stale nil.
            SmartRecipeSheet(
                store: smartRecipes, snapshot: snapshot,
                selectedID: viewModel.selectedRecipeID, canApply: canApplySmartRecipe,
                onApply: applySmartRecipe, onClose: { isShowingSmartRecipes = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var shootingSessionStateView: some View {
        smartRecipeLifecycleView
        .onChange(of: isShootingSessionActive, initial: true) { _, active in
            shooting.attach(camera: camera, viewModel: viewModel, active: active)
        }
        .onChange(of: camera.manualControls.activeDeviceID) { _, _ in shooting.invalidatePreview() }
        .onChange(of: camera.manualControls.exposureMode) { _, mode in
            // The drag tip cannot be used in manual exposure: move on instead of stalling the sequence.
            if mode == .manual && gestureTips.tip == .drag { dismissGestureHint() }
        }
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
        .onChange(of: isSceneAutoViewfinderActive, initial: true) { _, active in
            camera.setSceneAutoViewfinderActive(active)
        }
        .onChange(of: countdown.state.remaining) { old, new in
            guard countdown.state.isActive, new > 0 else { return }
            let message = old == 0 ? "Photo in \(new) seconds" : "\(new)"
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .onChange(of: captureAspect) { _, _ in countdown.cancel(); assists.stop(); shooting.invalidatePreview(); updateCompositionAssists() }
    }

    /// Continues `shootingSessionStateView`: one chain of every observer is too long for the Xcode 26 type checker.
    private var shootingStateView: some View {
        shootingSessionStateView
        .onChange(of: canTriggerShutter) { _, enabled in
            if !enabled {
                isPinching = false
                previewDragMaySelectLook = nil
                previewDragAxis = nil
                isShowingExposureReadout = false
                lookFlash = nil
                // A cancelled exposure drag must still let the reticle time out.
                if exposureDragStart != nil { focusFeedbackRevision += 1 }
                exposureDragStart = nil
                exposureDragCommitted = false
                exposureDragSentBias = nil
            }
        }
        .onChange(of: camera.isRunning) { _, running in
            if !running {
                isShowingExposureReadout = false
                lookFlash = nil
            }
        }
        .onChange(of: isShowingLookLibrary) { _, showing in
            if !showing { refreshLookStripAfterSheet() }
        }
        .onChange(of: isShowingRecipeManager) { _, showing in
            if !showing { refreshLookStripAfterSheet() }
        }
        .onChange(of: isHoldingOriginalPreview) { _, holding in noteOriginalHold(holding) }
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
        .sheet(isPresented: $isShowingManualControls) { [opening = proControlsOpeningSection] in
            // The body must read the section, or the sheet keeps a stale .top.
            PremiumFeatureGate(feature: .manualControls) { ManualCameraControlsView(camera: camera, initialSection: opening) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FilmyTheme.background)
        }
    }

    private var cameraLifecycleView: some View {
        cameraPresentationsView
        .onAppear {
            if !gestureHintSeen && gestureTips.tip == nil { gestureTips.reset() }
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
            dateStampNoticeTask?.cancel()
            dateStampNoticeTask = nil
            dateStampNotice = nil
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
                lookFlash = nil
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
        .onChange(of: isViewfinderCoveredBySheet) { _, _ in
            updateCameraActivity()
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

    // MARK: - Owed Photos exports notice

    private var showsPendingExportsCard: Bool {
        viewModel.showsPendingPhotosExportsNotice && !isShowingLookDrawer
    }

    private func reconcilePendingExports() {
        Task { await viewModel.reconcilePendingPhotosExports() }
    }

    private func savePendingExports() {
        Task { await viewModel.savePendingPhotosExports(photoLibrary: photoLibrary) }
    }

    /// Non-nil only when Save would be refused again until the user changes
    /// Photos access in Settings.
    private var pendingExportsSettingsDetail: String? {
        if PhotoLibraryAuthorizationPolicy.isRefused(photoLibrary.addOnlyAuthorizationStatus) {
            return "Allow Photos access in Settings to save them."
        }
        let awaitingFullAccess: Bool = viewModel.pendingExportsAwaitFullAccessOnly
        if awaitingFullAccess && PhotoLibraryAuthorizationPolicy.isRefused(photoLibrary.authorizationStatus) {
            return "Live Photos need full Photos access in Settings."
        }
        return nil
    }

    /// Calm card: captures kept in Filmy that are not in Photos yet. No
    /// danger colour; nothing is lost.
    private var pendingExportsNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            pendingExportsTitle
            pendingExportsDetail
            pendingExportsActions
        }
        .padding(14)
        .viewfinderChrome(RoundedRectangle(cornerRadius: 16))
        .dynamicTypeSize(.xSmall ... .accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera-pending-exports")
        .onAppear { viewModel.announcePendingPhotosExportsOnce() }
    }

    private var pendingExportsTitle: some View {
        let title: String = CameraViewModel.pendingExportsTitle(count: viewModel.pendingPhotosExportIDs.count)
        return Label(title, systemImage: "photo.badge.arrow.down")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var pendingExportsDetail: some View {
        // At accessibility sizes the Settings button already says it, and the
        // extra line would push the card into the viewfinder.
        if let detail = pendingExportsSettingsDetail, !dynamicTypeSize.isAccessibilitySize {
            Text(detail)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pendingExportsActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { pendingExportsButtons }
            VStack(alignment: .leading, spacing: 8) { pendingExportsButtons }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var pendingExportsPrimaryButton: some View {
        if pendingExportsSettingsDetail != nil {
            Button(action: openSystemSettings) {
                Text("Settings").frame(minHeight: FilmyTheme.minimumHitTarget)
            }
            .accessibilityLabel("Photos Settings")
            .accessibilityIdentifier("camera-pending-exports-settings")
        } else {
            Button(action: savePendingExports) {
                Text(viewModel.isSavingPendingExports ? "Saving" : "Save")
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
            }
            .disabled(viewModel.isSavingPendingExports)
            .accessibilityLabel("Save to Photos")
            .accessibilityIdentifier("camera-pending-exports-save")
        }
    }

    @ViewBuilder
    private var pendingExportsButtons: some View {
        pendingExportsPrimaryButton
        Button { isShowingPendingOriginals = true } label: {
            Text("Show").frame(minHeight: FilmyTheme.minimumHitTarget)
        }
        .accessibilityLabel("Show in Filmy originals")
        .accessibilityIdentifier("camera-pending-exports-show")
        Button { viewModel.dismissPendingPhotosExportsNotice() } label: {
            Text("Later").frame(minHeight: FilmyTheme.minimumHitTarget)
        }
        .accessibilityLabel("Later")
        .accessibilityHint("Hides this until Filmy opens again.")
        .accessibilityIdentifier("camera-pending-exports-later")
    }

    private var pendingOriginalsSheet: some View {
        NavigationStack {
            FilmyOriginalsView(photoLibrary: photoLibrary)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingPendingOriginals = false }
                            .accessibilityIdentifier("camera-pending-exports-done")
                    }
                }
        }
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
    }

    private func edgeControlShell(
        isLandscape: Bool,
        availableHeight: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let railOnLeading = useLeftHandedGrip
        let railWidth: CGFloat = isPad ? 152 : 136

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
    }

    private var isChromeDisabled: Bool {
        // Prime-lens setup can remain active while the camera is unavailable
        // (including Simulator), but it does not make local navigation unsafe.
        // Keep the broader Fuji transaction locks in place while allowing the
        // looks drawer to open during that setup-only phase.
        isCaptureLocked || isNavigationChromeDisabled
    }

    /// Capture, save and recovery state. Settings and Roll stay enabled
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

    // MARK: - Viewfinder

    private func viewfinderStage(isLandscape: Bool, overlaysTopBar: Bool) -> some View {
        GeometryReader { proxy in
            let size = ViewfinderLayout.size(available: proxy.size, isLandscape: isLandscape, aspect: captureAspect)

            viewfinder(size: size, overlaysTopBar: overlaysTopBar)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { lookStripSlot(stage: proxy.size, viewfinder: size) }
        }
    }

    /// The slim look picker docks over the bottom of the viewfinder, outside its
    /// clip shape so it may span the side bands. Adjust, review and the tool strip
    /// each take the slot when the picker is not shown.
    @ViewBuilder
    private func lookStripSlot(stage: CGSize, viewfinder: CGSize) -> some View {
        #if !G7_APP
        if isShowingLookDrawer && !isShowingLiveAdjustments && !isReviewing {
            let inset: CGFloat = max(0, (stage.height - viewfinder.height) / 2 + 8)
            let cap: CGFloat = dynamicTypeSize.isAccessibilitySize ? viewfinder.height * 0.6 - 8 : viewfinder.height - 16
            lookDrawer(maxHeight: max(126, cap))
                .frame(maxWidth: max(0, min(640, stage.width - 16)))
                .frame(maxHeight: .infinity, alignment: isLookSearchFocused ? .top : .bottom)
                .padding(.vertical, inset)
                .disabled(isChromeDisabled)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        #endif
    }

    /// Histogram and level assists rise above the footer chrome, or above the look picker while it is open.
    private var histogramBottomClearance: CGFloat {
        let chrome: CGFloat = viewfinderChromeHeights[.bottom] ?? 52
        let strip: CGFloat = isShowingLookDrawer ? lookStripHeight + 8 : 0
        return max(chrome, strip) + 8
    }

    private func viewfinder(size: CGSize, overlaysTopBar: Bool) -> some View {
        ZStack(alignment: .top) {
            previewSurface(fujiTopChrome: overlaysTopBar ? viewfinderChromeHeights[.top] : nil)
                .anchorPreference(key: SavedFrameAnchorKey.self, value: .bounds) { (bounds: Anchor<CGRect>) -> [SavedFrameAnchor: Anchor<CGRect>] in
                    [.viewfinder: bounds]
                }

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
                    bottomClearance: histogramBottomClearance
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
            viewfinderMidSlot
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: lookFlash?.id)

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

    private func previewSurface(fujiTopChrome: CGFloat?) -> some View {
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
                    FujiViewfinderOverlay(controller: shooting, camera: camera, selectedRecipe: viewModel.selectedRecipe,
                                          topChromeHeight: fujiTopChrome)
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
                lookFlash = nil
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
                            lookFlash = nil
                            isPinching = true
                            pinchStartZoom = camera.zoomFactor
                            noteGestureTipUsed(.swipe)
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
        noteGestureTipUsed(.tap)
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
        noteGestureTipUsed(.swipe)
        flashSwipedLook(recipe)
        #endif
    }

    private var isLookFlashVisible: Bool { camera.isRunning || isViewfinderChromePreview }

    /// Swipe order, which lists the compact digital looks first.
    private func flashSwipedLook(_ recipe: FilmRecipe) {
        let ordered: [FilmRecipe] = LookLibraryIndex.results(
            in: viewModel.quickNavigationRecipes, query: "", filter: .all, favorites: [])
        flashLook(id: recipe.id, among: ordered)
    }

    /// Picker tile pick: selects and keeps the look picker open. The position
    /// counts over the list the user was looking at.
    private func selectDrawerLook(id: String, among visible: [FilmRecipe]) {
        let changed: Bool = id != viewModel.effectiveSelectedRecipeID
        viewModel.select(recipe: viewModel.recipe(for: id))
        originalPreviewOverride = nil
        if changed {
            HapticFeedback.play(.selection)
            flashLook(id: id, among: visible)
        }
    }

    /// Shows the look name only when the select took effect and the flash can be seen.
    /// The announcement uses the same gate as the visible flash.
    private func flashLook(id: String, among list: [FilmRecipe]) {
        guard isLookFlashVisible, !isReviewing, !isHoldingOriginalPreview,
              viewModel.effectiveSelectedRecipeID == id else { return }
        let name: String = viewModel.recipe(for: id).name
        let position: String? = CameraPreviewGesturePolicy.lookPositionText(in: list, selectedIdentifier: id)
        isShowingExposureReadout = false
        lookFlash = LookFlash(name: name, position: position)
        let spoken: String = position.map { "\(name), \($0)" } ?? name
        UIAccessibility.post(notification: .announcement, argument: spoken)
    }

    /// Hold-to-compare: newest claim wins the middle slot; release sets nothing.
    private func noteOriginalHold(_ holding: Bool) {
        if holding {
            noteGestureTipUsed(.hold)
            lookFlash = nil
            isShowingExposureReadout = false
        }
        guard isLookFlashVisible, !isReviewing else { return }
        HapticFeedback.play(.focus)
        UIAccessibility.post(notification: .announcement, argument: holding ? "Showing original" : "Showing look")
    }

    @ViewBuilder
    private var viewfinderMidSlot: some View {
        if !isReviewing {
            switch currentMidSlot {
            case .original:
                originalHoldPill
            case .exposure:
                exposureDragReadout
            case .lookName:
                if let flash = lookFlash { lookFlashView(flash) }
            case .none:
                EmptyView()
            }
        }
    }

    private var originalHoldPill: some View {
        Label("ORIGINAL", systemImage: "circle.lefthalf.filled")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .viewfinderChrome(Capsule(), fill: Color.black.opacity(0.6))
            .accessibilityHidden(true)
            .accessibilityIdentifier("camera-original-hold-pill")
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func lookFlashView(_ flash: LookFlash) -> some View {
        VStack(spacing: 2) {
            Text(flash.name)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let position = flash.position {
                Text(position)
                    .font(.footnote.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(FilmyTheme.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .minimumScaleFactor(0.8)
        .viewfinderChrome(RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous),
                          fill: Color.black.opacity(0.6))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera-look-flash")
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
        .task(id: flash.id) { await expireLookFlash(id: flash.id) }
    }

    private func expireLookFlash(id: UUID) async {
        try? await Task.sleep(for: CameraPreviewGesturePolicy.lookFlashDuration)
        guard !Task.isCancelled, lookFlash?.id == id else { return }
        lookFlash = nil
    }

    private func toastRow(message: String) -> some View {
        toastRowContent(message: message).transition(.opacity)
    }

    @ViewBuilder
    private func toastRowContent(message: String) -> some View {
        if let action = viewModel.toastAction {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ToastView(message: message, style: viewModel.toastStyle)
                    toastActionButton(action)
                }
                VStack(alignment: .trailing, spacing: 6) {
                    ToastView(message: message, style: viewModel.toastStyle)
                    toastActionButton(action)
                }
            }
        } else {
            ToastView(message: message, style: viewModel.toastStyle)
        }
    }

    /// A sibling of ToastView, which stays a single static element.
    @ViewBuilder
    private func toastActionButton(_ action: CameraViewModel.ToastAction) -> some View {
        switch action {
        case .undoLookReset:
            Button { viewModel.undoLookReset() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .padding(.horizontal, 14)
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                    .viewfinderChrome(Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("camera-toast-undo")
            .accessibilityLabel("Undo look reset")
        case .viewSavedFrame:
            Button { viewSavedFrameInRoll() } label: {
                Text("View")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .padding(.horizontal, 14)
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                    .viewfinderChrome(Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .disabled(isNavigationRecoveryLocked)
            .accessibilityIdentifier("camera-toast-view")
            .accessibilityLabel("View in Roll")
        }
    }

    /// Same sequence as rollButton, after the toast is dismissed.
    private func viewSavedFrameInRoll() {
        viewModel.dismissToast()
        if viewModel.isCapturing || viewModel.isSaving {
            onOpenGallery()
            return
        }
        closeControlDrawers()
        onOpenGallery()
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
            lookFlash = nil
            isShowingExposureReadout = true
        }
        guard canAdjustPreviewExposure,
              CameraPreviewGesturePolicy.exposureDetent(from: camera.exposureBias, to: bias) != nil else { return }
        noteGestureTipUsed(.drag)
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
                    onReset: { viewModel.resetLookWithUndo(recipeID: viewModel.selectedRecipeID) },
                    onClose: { isShowingLiveAdjustments = false }
                )
            }
            if isShowingTools && !isShowingLiveAdjustments && !isShowingLookDrawer && !hidesToolsForRecoveryPlaceholder {
                toolStripSlot(minWidth: width - 24)
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
                        camera.setZoom(factor, reseedTracking: true)
                    },
                    onAdjust: { direction in
                        let delta: CGFloat = direction == .increment ? 0.5 : -0.5
                        camera.setZoom(camera.zoomFactor + delta)
                    }
                )
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    if gestureTipSitsOnZoomRow(footerWidth: width) { gestureHintOverlay }
                }
                .opacity(camera.isRunning || isViewfinderChromePreview ? 1 : 0)
                .disabled((!camera.isRunning && !isViewfinderChromePreview)
                    || shooting.settings.lockPrimeLens || shooting.settingsLocked)
                .accessibilityHidden(!camera.isRunning && !isViewfinderChromePreview)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if !gestureTipSitsOnZoomRow(footerWidth: width) { gestureHintOverlay }
        }
    }

    // MARK: - Top bar

    /// The G7 X profile is a camera mode rather than a film stock, so its
    /// drawer names it as a camera profile.
    private var isCompactDigitalMode: Bool {
        viewModel.selectedRecipe.filmBase == .compactDigital
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
                    openProControls(at: manualChipSection)
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
            .accessibilityHint(activeAdjustmentsChipHint)
        }
    }

    private var manualChipSection: ProControlsSection {
        let controls: CameraManualControls = camera.manualControls
        if controls.exposureMode == .manual {
            return .exposure
        } else if controls.whiteBalanceMode == .manual {
            return .whiteBalance
        } else if controls.focusMode == .manual {
            return .focus
        } else {
            return .top
        }
    }

    private var activeAdjustmentsChipHint: String {
        guard camera.manualControls.isAnyManualModeEnabled else { return "Shows the camera controls" }
        switch manualChipSection {
        case .exposure: return "Opens Pro controls at exposure"
        case .whiteBalance: return "Opens Pro controls at white balance"
        case .focus: return "Opens Pro controls at focus"
        case .top, .format: return "Opens Pro controls"
        }
    }

    private func openProControls(at section: ProControlsSection) {
        proControlsOpeningSection = section
        isShowingManualControls = true
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
                openProControls(at: .format)
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
            .accessibilityHint("Opens Pro controls at Capture format")
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
        .accessibilityShowsLargeContentViewer {
            Label("Switch camera", systemImage: "arrow.triangle.2.circlepath.camera")
        }
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
        .accessibilityShowsLargeContentViewer {
            Label("Settings", systemImage: "gearshape.fill")
        }
    }

    /// What the toggle reports: the rail is suppressed over a recovery placeholder.
    private var isToolRailVisible: Bool {
        isShowingTools && !isShowingLookDrawer && !hidesToolsForRecoveryPlaceholder
    }

    private func toolsToggle(showsCaption: Bool = false) -> some View {
        let captioned = showsCaption && !isToolRailVisible && !dynamicTypeSize.isAccessibilitySize
        return Button {
            HapticFeedback.play(.selection)
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                isShowingAidsTray = false
                if isShowingLookDrawer {
                    isShowingLookDrawer = false
                    isShowingTools = true
                } else {
                    isShowingTools.toggle()
                }
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
                : "Shows exposure, grid, Pro, timer and aids"
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
            UIAccessibility.post(notification: .announcement,
                                 argument: favorite ? "Removed from favorites" : "Added to favorites")
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
        .accessibilityShowsLargeContentViewer {
            Label("Favorite", systemImage: favorite ? "heart.fill" : "heart")
        }
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
                Label("Adjust", systemImage: "dial.low")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .frame(minHeight: 44)
            }
            .tint(FilmyTheme.accent)
            .accessibilityIdentifier("live-recipe-adjustments")
            .accessibilityLabel("Adjust look")
            .accessibilityHint("Shows quick sliders over the live camera preview")
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
        let isFiltering: Bool = isSearchingLooks && !quickRecipeQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let mode: LookStripMode = lookStripMode(isFiltering: isFiltering)
        let visible: [FilmRecipe] = lookStripVisible(mode: mode)
        let shown: [FilmRecipe] = lookStripShown(visible: visible)

        return VStack(spacing: 0) {
            lookStripHeader(activeCount: lookStripActive.count)
                .contentShape(Rectangle())
                .simultaneousGesture(lookStripDismissDrag)
            lookStripContent(visible: visible, shown: shown, mode: mode)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(FilmyTheme.backgroundRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(FilmyTheme.tertiary)
                .frame(width: 36, height: 4)
                .padding(.top, 3)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
        .background { lookStripHeightReader }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look picker")
        .accessibilityIdentifier("recipe-drawer")
        .accessibilityAction(.escape) { closeLookDrawer() }
        // A flexible frame takes the whole cap, so the panel docks to the slot edge instead of floating mid-viewfinder.
        .frame(maxHeight: maxHeight, alignment: isLookSearchFocused ? .top : .bottom)
        .onAppear {
            lookStripActive = viewModel.quickRecipes
            if favoritesOnly { loadLookCatalog() }
        }
        .onDisappear {
            isSearchingLooks = false
            isLookSearchFocused = false
            quickRecipeQuery = ""
            lookStripCatalog = []
            lookSearchResults = []
            lookStripRecent = []
        }
    }

    /// Measures the docked panel so the histogram and level assists can clear it.
    private var lookStripHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { lookStripHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in lookStripHeight = height }
        }
    }

    private enum LookStripMode: String { case active, favorites, recent, results }

    private func lookStripMode(isFiltering: Bool) -> LookStripMode {
        if isSearchingLooks {
            if isFiltering { return .results }
            return lookStripRecent.isEmpty ? .active : .recent
        }
        return favoritesOnly ? .favorites : .active
    }

    private func loadLookCatalog() {
        lookStripCatalog = viewModel.recipes
    }

    private func refreshLookCatalogIfShown() {
        if favoritesOnly || isSearchingLooks { loadLookCatalog() }
    }

    /// The loaded catalog, or the live one before the first load is visible.
    private var lookSearchCatalog: [FilmRecipe] {
        lookStripCatalog.isEmpty ? viewModel.recipes : lookStripCatalog
    }

    /// Re-reads the quick menu and, when Favorites or search is on, the catalog after the library or Packs sheet closes.
    private func refreshLookStripAfterSheet() {
        lookStripActive = viewModel.quickRecipes
        refreshLookCatalogIfShown()
    }

    /// The list for the current mode. Favorites and search read the whole
    /// catalog; Active reads the cached quick menu.
    private func lookStripVisible(mode: LookStripMode) -> [FilmRecipe] {
        switch mode {
        case .results:
            return lookSearchResults
        case .recent:
            return lookStripRecent
        case .favorites:
            let favorites: Set<String> = favoriteIDs
            let source: [FilmRecipe] = lookSearchCatalog
            return source.filter { (recipe: FilmRecipe) -> Bool in favorites.contains(recipe.id) }
        case .active:
            return lookStripActive
        }
    }

    /// The current look stays ringed at the start when the filters hide it.
    private func lookStripShown(visible: [FilmRecipe]) -> [FilmRecipe] {
        let currentID: String = viewModel.effectiveSelectedRecipeID
        let holdsCurrent: Bool = visible.contains { (recipe: FilmRecipe) -> Bool in recipe.id == currentID }
        if visible.isEmpty || holdsCurrent { return visible }
        return [viewModel.selectedRecipe] + visible
    }

    @ViewBuilder
    private func lookStripContent(visible: [FilmRecipe], shown: [FilmRecipe], mode: LookStripMode) -> some View {
        if visible.isEmpty {
            Text(lookStripEmptyText(mode: mode))
                .font(.caption)
                .foregroundStyle(FilmyTheme.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 5 : 3)
                .frame(maxWidth: .infinity, minHeight: 76)
                .accessibilityIdentifier(mode == .favorites ? "camera-favorites-empty" : "camera-looks-empty")
        } else {
            RecipePickerView(
                recipes: shown,
                selectedRecipeID: Binding(get: { viewModel.effectiveSelectedRecipeID }, set: { id in
                    selectDrawerLook(id: id, among: visible)
                }),
                onOpenDetail: openRecipeDetail,
                compact: mode == .active,
                favoriteIDs: favoriteIDs,
                showsFavoriteBadges: mode != .favorites,
                onToggleFavorite: toggleDrawerFavorite,
                keepsOrder: mode == .recent || mode == .results,
                listMarker: lookStripMarker(mode: mode, shownCount: shown.count)
            )
            .id(mode.rawValue)
        }
    }

    private func lookStripMarker(mode: LookStripMode, shownCount: Int) -> RecipePickerView.ListMarker? {
        switch mode {
        case .results:
            return RecipePickerView.ListMarker(title: "Results", systemImage: "magnifyingglass", count: shownCount)
        case .recent:
            return RecipePickerView.ListMarker(title: "Recent", systemImage: "clock.arrow.circlepath", count: shownCount)
        case .favorites, .active:
            return nil
        }
    }

    private func lookStripEmptyText(mode: LookStripMode) -> String {
        switch mode {
        case .results: return "No looks match your search."
        case .favorites: return "No favorites yet. Tap the heart on the camera."
        case .active, .recent: return "Your quick menu is empty. Open Packs to add looks."
        }
    }

    /// Hearts or unhearts a drawer tile with the same key and encoder as the
    /// camera heart. Never selects the look and never closes the drawer.
    private func toggleDrawerFavorite(_ recipe: FilmRecipe) {
        var updated = favoriteIDs
        let removing = updated.contains(recipe.id)
        if removing { updated.remove(recipe.id) } else { updated.insert(recipe.id) }
        favoriteData = LookLibraryIndex.encodeFavorites(updated)
        HapticFeedback.play(.selection)
        UIAccessibility.post(notification: .announcement,
                             argument: removing ? "Removed from favorites" : "Added to favorites")
    }

    /// Swipe down on the header closes the picker. The look row scrolls
    /// vertically between groups, so the gesture is attached to the header only.
    private var lookStripDismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { (value: DragGesture.Value) in
                guard value.translation.height > 32,
                      value.translation.height > abs(value.translation.width) * 1.5 else { return }
                closeLookDrawer()
            }
    }

    @ViewBuilder
    private func lookStripHeader(activeCount: Int) -> some View {
        if isSearchingLooks {
            lookSearchRow
        } else {
            ViewThatFits(in: .horizontal) {
                lookHeaderRow(activeCount: activeCount, iconOnly: false, tuneShowsText: true)
                lookHeaderRow(activeCount: activeCount, iconOnly: false, tuneShowsText: false)
                lookHeaderRow(activeCount: activeCount, iconOnly: true, tuneShowsText: false)
                lookHeaderTwoRows(activeCount: activeCount)
            }
        }
    }

    private func lookHeaderRow(activeCount: Int, iconOnly: Bool, tuneShowsText: Bool) -> some View {
        HStack(spacing: 4) {
            lookSegments(iconOnly: iconOnly, activeCount: activeCount)
            Spacer(minLength: 0)
            lookSearchToggleButton
            lookBrowseButton
            lookPacksButton
            lookTuneButton(showsText: tuneShowsText)
            lookCloseButton
                .padding(.leading, 4)
        }
        .frame(minHeight: cameraHitTarget)
    }

    /// Split-view iPad only: the four actions drop to a second row.
    private func lookHeaderTwoRows(activeCount: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                lookSegments(iconOnly: false, activeCount: activeCount)
                Spacer(minLength: 0)
                lookCloseButton
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                lookSearchToggleButton
                lookBrowseButton
                lookPacksButton
                lookTuneButton(showsText: true)
            }
        }
        .frame(minHeight: cameraHitTarget)
    }

    private func lookSegments(iconOnly: Bool, activeCount: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                favoritesOnly = false
                HapticFeedback.play(.selection)
            } label: {
                lookActiveSegmentLabel(iconOnly: iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(!favoritesOnly ? FilmyTheme.primary : FilmyTheme.secondary)
                    .padding(.horizontal, 12)
                    .frame(minWidth: cameraHitTarget, minHeight: cameraHitTarget)
                    .overlay(alignment: .bottom) {
                        if !favoritesOnly { FilmRegistration() }
                    }
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("camera-looks-all")
            .accessibilityLabel("Active looks, \(activeCount)")
            .accessibilityAddTraits(!favoritesOnly ? .isSelected : [])
            Button {
                loadLookCatalog()
                favoritesOnly = true
                HapticFeedback.play(.selection)
            } label: {
                Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(favoritesOnly ? FilmyTheme.primary : FilmyTheme.secondary)
                    .frame(minWidth: cameraHitTarget, minHeight: cameraHitTarget)
                    .overlay(alignment: .bottom) {
                        if favoritesOnly { FilmRegistration() }
                    }
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("camera-looks-favorites")
            .accessibilityLabel("Favorites")
            .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func lookActiveSegmentLabel(iconOnly: Bool) -> some View {
        if iconOnly {
            Image(systemName: "rectangle.stack")
        } else {
            Text("Active").lineLimit(1).fixedSize()
        }
    }

    private var lookSearchToggleButton: some View {
        lookHeaderIconButton(
            systemImage: "magnifyingglass",
            identifier: "camera-looks-search-toggle",
            label: "Search all looks",
            hint: "Shows your recent looks. Type to search every look."
        ) {
            loadLookCatalog()
            lookStripRecent = recentLookList()
            isSearchingLooks = true
        }
    }

    private var lookBrowseButton: some View {
        lookHeaderIconButton(
            systemImage: "books.vertical",
            identifier: "look-library-open",
            label: "Browse all looks",
            hint: "Browse and search all \(viewModel.recipes.count) looks, including hidden recipes"
        ) {
            HapticFeedback.play(.selection)
            isShowingLookLibrary = true
        }
    }

    private var lookPacksButton: some View {
        lookHeaderIconButton(
            systemImage: "square.stack.3d.up",
            identifier: "camera-recipe-packs",
            label: "Packs",
            hint: "Choose the packs and individual looks in your quick menu"
        ) {
            HapticFeedback.play(.selection)
            isShowingRecipeManager = true
        }
    }

    private var lookCloseButton: some View {
        lookHeaderIconButton(
            systemImage: "xmark",
            identifier: "recipe-drawer-close",
            label: "Close look picker",
            hint: ""
        ) {
            closeLookDrawer()
        }
    }

    private func lookHeaderIconButton(
        systemImage: String,
        identifier: String,
        label: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.subheadline).weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(FilmyTheme.primary)
                .frame(width: cameraHitTarget, height: cameraHitTarget)
                .background(FilmyTheme.panel, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityShowsLargeContentViewer()
    }

    private func lookTuneButton(showsText: Bool) -> some View {
        Button {
            openRecipeDetail(viewModel.selectedRecipe)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.vertical.3")
                if showsText {
                    Text("Tune").lineLimit(1).fixedSize()
                }
            }
            .font(.system(.subheadline).weight(.bold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, showsText ? 12 : 0)
            .frame(minWidth: cameraHitTarget, minHeight: cameraHitTarget)
            .background(FilmyTheme.panel, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Tune \(viewModel.selectedRecipe.name)")
        .accessibilityHint("Opens every setting for this look")
        .accessibilityShowsLargeContentViewer()
    }

    private func endLookSearch() {
        isLookSearchFocused = false
        isSearchingLooks = false
        quickRecipeQuery = ""
        lookSearchResults = []
    }

    /// Looks switched to recently, newest first. Unknown or removed ids are dropped.
    private func recentLookList() -> [FilmRecipe] {
        let catalog: [FilmRecipe] = lookSearchCatalog
        return viewModel.recentRecipeIDs.compactMap { (id: String) -> FilmRecipe? in
            catalog.first { (recipe: FilmRecipe) -> Bool in recipe.id == id }
        }
    }

    private var lookSearchQuery: Binding<String> {
        Binding<String>(
            get: { quickRecipeQuery },
            set: { (query: String) in
                quickRecipeQuery = query
                updateLookSearchResults(query)
            }
        )
    }

    /// Runs in the field's setter so no frame shows stale or empty results.
    private func updateLookSearchResults(_ query: String) {
        let trimmed: String = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            lookSearchResults = []
            lookStripRecent = recentLookList()
            return
        }
        let found: [FilmRecipe] = LookLibraryIndex.results(in: lookSearchCatalog, query: trimmed, filter: .all, favorites: [])
        lookSearchResults = LookLibraryIndex.nameMatchesFirst(found, query: trimmed)
    }

    private var lookSearchRow: some View {
        HStack(spacing: 4) {
            lookSearchField
            Button {
                endLookSearch()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(FilmyTheme.accent)
                    .padding(.horizontal, 8)
                    .frame(minWidth: cameraHitTarget, minHeight: cameraHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("camera-looks-search-done")
            .accessibilityLabel("Done searching")
            lookCloseButton
        }
        .frame(minHeight: cameraHitTarget)
    }

    private var lookSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(FilmyTheme.secondary)
            TextField("Search all looks", text: lookSearchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isLookSearchFocused)
                .onSubmit { isLookSearchFocused = false }
                .accessibilityIdentifier("camera-looks-search")
            if !quickRecipeQuery.isEmpty {
                Button {
                    lookSearchQuery.wrappedValue = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camera-looks-search-clear")
                .accessibilityLabel("Clear search")
            }
        }
        .font(.subheadline)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 12)
        .frame(height: cameraHitTarget)
        .background(FilmyTheme.panel, in: Capsule())
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
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .lineLimit(3)
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
            VStack(spacing: 2) {
                RollThumbnail(asset: photoLibrary.galleryAssets.first, photoLibrary: photoLibrary)
                    .anchorPreference(key: SavedFrameAnchorKey.self, value: .bounds) { (bounds: Anchor<CGRect>) -> [SavedFrameAnchor: Anchor<CGRect>] in
                        [.rollThumbnail: bounds]
                    }
                Text("Roll")
                    .font(.caption2.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(FilmyTheme.secondary)
            }
            .frame(width: 64)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isNavigationRecoveryLocked)
        .accessibilityShowsLargeContentViewer { Label("Roll", systemImage: "square.grid.3x3") }
        .accessibilityIdentifier("roll-tab")
        .accessibilityLabel("Open roll")
        .accessibilityHint("Shows the frames you have kept")
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
        ViewThatFits(in: .horizontal) {
            toolStripOneRow
            toolStripBalancedRows
            toolStripTwoRows(minWidth: minWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { toolStripHeightProbe }
        .onPreferenceChange(ToolStripHeightKey.self) { (height: CGFloat) in
            let twoRows: Bool = height > FilmyTheme.toolControlHeight * 2
            if isToolStripTwoRows != twoRows { isToolStripTwoRows = twoRows }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isCompactDigitalMode ? "g7x-capture-controls" : "camera-utility-rail"
        )
        .accessibilityLabel(isCompactDigitalMode ? "Compact camera controls" : "Camera controls")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var toolStripHeightProbe: some View {
        GeometryReader { (proxy: GeometryProxy) in
            Color.clear.preference(key: ToolStripHeightKey.self, value: proxy.size.height)
        }
    }

    /// A: every tool on one row.
    private var toolStripOneRow: some View {
        HStack(spacing: 8) {
            toolStripExposureGroup
            toolStripGridButton
            toolStripTrailingGroup
        }
        .padding(4)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// C: exposure and grid on the first row, lens, Pro and timer on the second.
    private var toolStripBalancedRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                toolStripExposureGroup
                toolStripGridButton
            }
            .padding(4)
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                toolStripTrailingGroup
            }
            .padding(4)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func toolStripTwoRows(minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                toolStripExposureGroup
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)

            toolStripScroller(minWidth: minWidth) {
                toolStripButtonGroup
            }
        }
    }

    private func toolStripScroller<Content: View>(
        minWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .padding(.trailing, Self.toolStripFadeWidth)
            .frame(minWidth: max(minWidth, 0))
        }
        .scrollClipDisabled()
        .mask { toolStripFadeMask }
    }

    private var toolStripExposureGroup: some View {
        ExposureControl(value: camera.exposureBias, onReset: {
            camera.setExposureBias(0)
        }) { direction in
            let delta: Float = direction == .increment ? (1.0 / 3.0) : -(1.0 / 3.0)
            camera.setExposureBias(camera.exposureBias + delta)
        }
        .opacity(camera.manualControls.exposureMode == .manual ? 0.45 : 1)
        .disabled(camera.manualControls.exposureMode == .manual || camera.manualControls.isApplying)
        .overlay(alignment: .topLeading) { focusLockPill }
    }

    /// True while the AE/AF lock pill is offered: after a focus tap, or while locked.
    private var isFocusLockPillShowing: Bool {
        let hasPoint: Bool = focusPoint != nil || camera.isFocusExposureLocked
        return hasPoint
            && focusNormalizedPoint != nil
            && camera.manualControls.exposureMode != .manual
            && camera.manualControls.focusMode != .manual
    }

    /// Floats 8 pt above the exposure control, over the picture, so it never changes the strip's rows.
    @ViewBuilder
    private var focusLockPill: some View {
        if isFocusLockPillShowing, let focusNormalizedPoint {
            FocusLockControl(isLocked: camera.isFocusExposureLocked, showsTitle: true) {
                camera.toggleFocusExposureLock(at: focusNormalizedPoint)
            }
            .alignmentGuide(.top) { (dimensions: ViewDimensions) in dimensions[.bottom] + 8 }
        }
    }

    /// Keeps a slot as wide as its widest state, so a changing label never reflows the row.
    private func toolStripStableSlot<Content: View, Reserve: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder reserve: () -> Reserve
    ) -> some View {
        ZStack(alignment: .leading) {
            reserve()
                .hidden()
                .accessibilityHidden(true)
            content()
        }
    }

    /// Every armed timer title, overlaid so the widest rendered one sets the reserve.
    private static let armedCaptureDelays: [CaptureDelay] = CaptureDelay.allCases.filter { $0 != .off }

    private var timerReserve: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .bold))
            ZStack(alignment: .leading) {
                ForEach(Self.armedCaptureDelays) { (delay: CaptureDelay) in
                    Text(delay.title)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: FilmyTheme.toolControlHeight)
    }

    private var timerSlot: some View {
        toolStripStableSlot {
            timerControl
        } reserve: {
            timerReserve
        }
    }

    /// Every lens title, overlaid so the widest rendered one sets the reserve.
    private var lensReserve: some View {
        ZStack(alignment: .leading) {
            ForEach(camera.availableLenses) { lens in
                Label(lens.title, systemImage: "camera.aperture")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: FilmyTheme.toolControlHeight)
    }

    private var lensSlot: some View {
        toolStripStableSlot {
            CameraLensMenu(camera: camera)
        } reserve: {
            lensReserve
        }
    }

    @ViewBuilder
    private var toolStripGridButton: some View {
        gridToggle(
            accessibilityIdentifier: isCompactDigitalMode
                ? "g7x-grid-control"
                : "grid-control"
        )
        #if !G7_APP
        if isCompactDigitalMode {
            dateStampToggle
        }
        #endif
    }

    #if !G7_APP
    /// One-tap Date stamp for the G7 X strip. Writes the same key as the Settings row.
    private var dateStampToggle: some View {
        Button {
            toggleDateStamp()
        } label: {
            Image(systemName: dateStampEnabled ? "calendar.badge.checkmark" : "calendar")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(dateStampEnabled ? FilmyTheme.background : .white)
                .frame(width: FilmyTheme.toolControlHeight, height: FilmyTheme.toolControlHeight)
                .background {
                    if dateStampEnabled {
                        Circle().fill(FilmyTheme.accent)
                    } else {
                        ChromeShapeBackground(shape: Circle())
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer { Label("Date stamp", systemImage: "calendar") }
        .accessibilityIdentifier("g7x-date-stamp-control")
        .accessibilityLabel("Date stamp")
        .accessibilityValue(dateStampEnabled ? "On" : "Off")
        .accessibilityHint("Prints the capture date on saved photos. The viewfinder does not show it.")
    }

    private var dateStampNoticeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private func toggleDateStamp() {
        HapticFeedback.play(.selection)
        let enabled: Bool = !dateStampEnabled
        dateStampEnabled = enabled
        let message: String = enabled ? "Date stamp on, saved photos only" : "Date stamp off"
        dateStampNoticeTask?.cancel()
        withAnimation(dateStampNoticeAnimation) { dateStampNotice = message }
        dateStampNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            withAnimation(dateStampNoticeAnimation) { dateStampNotice = nil }
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Floats above the strip without moving it and never takes touches.
    @ViewBuilder
    private var dateStampNoticeOverlay: some View {
        if isCompactDigitalMode, let message = dateStampNotice {
            Text(message)
                .font(.caption.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background { ChromeShapeBackground(shape: Capsule()) }
                .alignmentGuide(.top) { (dimensions: ViewDimensions) -> CGFloat in dimensions[.bottom] + 6 }
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityIdentifier("g7x-date-stamp-notice")
        }
    }
    #else
    private var dateStampNoticeOverlay: some View { EmptyView() }
    #endif

    /// The strip, or the Aids tray in the same slot while the tray is open.
    @ViewBuilder
    private func toolStripSlot(minWidth: CGFloat) -> some View {
        if isShowingAidsTray {
            aidsTray
        } else {
            toolStrip(minWidth: minWidth)
                .overlay(alignment: .top) { dateStampNoticeOverlay }
        }
    }

    private var aidsTrayAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    /// Effective on/off, as the viewfinder overlays use it.
    private func isAidOn(_ aid: CameraAid) -> Bool {
        switch aid {
        case .level: return showHorizonLevel
        case .histogram: return showHistogram
        case .zebras: return showZebras
        case .peaking: return showFocusPeaking
        case .loupe: return camera.focusLoupeEnabled
        }
    }

    private var activeAidCount: Int {
        let flags: [Bool] = [
            showHorizonLevel,
            showHistogram,
            showZebras,
            showFocusPeaking,
            camera.focusLoupeEnabled
        ]
        return flags.filter { $0 }.count
    }

    private func toggleAid(_ aid: CameraAid) {
        let enabled: Bool = !isAidOn(aid)
        switch aid {
        case .level:
            guard membership.require(.captureSetup) else { return }
            storedShowHorizonLevel = enabled
        case .histogram:
            guard membership.require(.captureSetup) else { return }
            storedShowHistogram = enabled
        case .zebras:
            guard membership.require(.captureSetup) else { return }
            storedShowZebras = enabled
        case .peaking:
            guard membership.require(.captureSetup) else { return }
            storedShowFocusPeaking = enabled
        case .loupe:
            guard membership.require(.manualControls) else { return }
            camera.setFocusLoupeEnabled(enabled)
        }
        HapticFeedback.play(.selection)
    }

    private func openAidsTray() {
        HapticFeedback.play(.selection)
        withAnimation(aidsTrayAnimation) { isShowingAidsTray = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if isShowingAidsTray { aidsFocus = .close }
        }
    }

    private func closeAidsTray() {
        HapticFeedback.play(.selection)
        withAnimation(aidsTrayAnimation) { isShowingAidsTray = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if !isShowingAidsTray { aidsFocus = .button }
        }
    }

    private var aidsButton: some View {
        let count: Int = activeAidCount
        let anyOn: Bool = count > 0
        let valueText: String = anyOn ? "\(count) on" : "All off"
        return Button {
            openAidsTray()
        } label: {
            Image(systemName: "scope")
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(anyOn ? FilmyTheme.background : .white)
                .frame(width: FilmyTheme.toolControlHeight, height: FilmyTheme.toolControlHeight)
                .background {
                    if anyOn {
                        Circle().fill(FilmyTheme.filmAccent)
                    } else {
                        ChromeShapeBackground(shape: Circle())
                    }
                }
                .overlay(alignment: .topTrailing) { aidsCountBadge(count) }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer { Label("Shooting aids", systemImage: "scope") }
        .accessibilityIdentifier("camera-aids-button")
        .accessibilityLabel("Shooting aids")
        .accessibilityValue(valueText)
        .accessibilityHint("Shows level, histogram, zebras, focus peaking and loupe over the viewfinder. Aids never appear in saved photos.")
        .accessibilityFocused($aidsFocus, equals: .button)
    }

    @ViewBuilder
    private func aidsCountBadge(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(FilmyTheme.filmAccent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background { Capsule().fill(FilmyTheme.background) }
                .padding(2)
                .accessibilityHidden(true)
        }
    }

    private var aidsTrayRow: some View {
        HStack(spacing: 8) {
            aidsBackButton
            ForEach(CameraAid.allCases) { (aid: CameraAid) in
                aidToggle(aid)
            }
        }
        .padding(8)
    }

    private var aidsTray: some View {
        ViewThatFits(in: .horizontal) {
            aidsTrayRow
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                aidsTrayRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius)
                .fill(Color.black.opacity(0.68))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera-aids-tray")
        .accessibilityLabel("Shooting aids")
        .accessibilityHint("Aids never appear in saved photos.")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var aidsBackButton: some View {
        Button {
            closeAidsTray()
        } label: {
            aidsCell(symbol: "chevron.backward", caption: "Back")
                .foregroundStyle(.white)
                .background { ChromeShapeBackground(shape: RoundedRectangle(cornerRadius: 12)) }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer { Label("Back", systemImage: "chevron.backward") }
        .accessibilityIdentifier("camera-aids-close")
        .accessibilityLabel("Back to camera controls")
        .accessibilityFocused($aidsFocus, equals: .close)
    }

    private func aidToggle(_ aid: CameraAid) -> some View {
        let isOn: Bool = isAidOn(aid)
        return Button {
            toggleAid(aid)
        } label: {
            aidsCell(symbol: aid.symbol, caption: aid.title)
                .foregroundStyle(isOn ? FilmyTheme.background : .white)
                .background { aidToggleBackground(isOn: isOn) }
                .overlay(alignment: .topTrailing) { aidOnBadge(isOn: isOn) }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
        .accessibilityShowsLargeContentViewer { Label(aid.title, systemImage: aid.symbol) }
        .accessibilityIdentifier(aid.identifier)
        .accessibilityLabel(aid.title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func aidsCell(symbol: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text(caption)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .padding(.horizontal, 8)
        .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.toolControlHeight + 8)
    }

    @ViewBuilder
    private func aidToggleBackground(isOn: Bool) -> some View {
        if isOn {
            RoundedRectangle(cornerRadius: 12).fill(FilmyTheme.accent)
        } else {
            ChromeShapeBackground(shape: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func aidOnBadge(isOn: Bool) -> some View {
        if isOn {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(FilmyTheme.background)
                .padding(3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var toolStripTrailingGroup: some View {
        if camera.availableLenses.count > 1 {
            lensSlot
        }

        proControlsButton

        timerSlot

        aidsButton
    }

    @ViewBuilder
    private var toolStripButtonGroup: some View {
        toolStripGridButton
        toolStripTrailingGroup
    }

    private var proControlsButton: some View {
        Button {
            HapticFeedback.play(.selection)
            openProControls(at: .top)
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
        .accessibilityShowsLargeContentViewer { Label("Pro controls", systemImage: "slider.horizontal.3") }
        .accessibilityIdentifier("pro-controls-button")
        .accessibilityLabel("Pro controls")
        .accessibilityValue(
            camera.manualControls.isApplying
                ? "Applying camera settings"
                : (camera.manualControls.isAnyManualModeEnabled ? "Manual settings active" : "Auto settings")
        )
        .accessibilityHint("Set ISO, shutter speed, white balance, and focus")
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

    /// The five `.large` sheets that hide the viewfinder at compact width.
    /// Manual controls (medium detent) and the Fuji menu are excluded on
    /// purpose: the finder is live behind them and the Fuji sampler consumes
    /// frames.
    private var isFullHeightSheetOpen: Bool {
        isShowingLookLibrary || isShowingRecipeManager || recipeForDetail != nil
            || isShowingSmartRecipes || isShowingCaptureSetup || isShowingPendingOriginals
    }

    /// A nil size class counts as not compact, so it never pauses.
    private var isViewfinderCoveredBySheet: Bool {
        CameraActivityPolicy.sheetCoversViewfinder(
            fullHeightSheetOpen: isFullHeightSheetOpen,
            isCompactWidth: CameraActivityPolicy.isCompactWidth(horizontalSizeClass)
        )
    }

    private var pausesFrameDelivery: Bool {
        CameraActivityPolicy.pausesFrameDelivery(
            isImporting: isImporting,
            hasImportReview: viewModel.isReviewingImport,
            coveredBySheet: isViewfinderCoveredBySheet
        )
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
        closeAdjustForCapture()
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
        let tip: CameraGestureTip = gestureTips.tip ?? .swipe
        #if G7_APP
        if tip == .swipe { return "Pinch to zoom" }
        #endif
        return tip.text
    }

    private var currentMidSlot: CameraMidSlot {
        CameraPreviewGesturePolicy.midSlot(
            isHoldingOriginal: isHoldingOriginalPreview && camera.isRunning,
            isShowingExposure: isShowingExposureReadout && camera.isRunning,
            hasLookFlash: lookFlash != nil && isLookFlashVisible
        )
    }

    private var showsGestureHint: Bool {
        guard !gestureHintSeen, let tip = gestureTips.tip, !Self.gestureHintSuppressed,
              camera.isRunning, !isReviewing, !isShowingLookDrawer, !isShowingLiveAdjustments,
              !isViewfinderCoveredBySheet, !isImporting else { return false }
        if tip == .drag && !canAdjustPreviewExposure { return false }
        // The focus-lock pill floats where the tip would sit; the tip waits until it is gone.
        // On a tall strip the tip sits on the zoom row, so only the footer-top tip yields.
        if isShowingTools && isFocusLockPillShowing && !gestureTipSitsOnZoomRow(footerWidth: 0) { return false }
        return currentMidSlot == .none
    }

    /// Tall footer (open strip at accessibility sizes, or a two-row strip): the tip keeps
    /// its shipped spot on the zoom row instead of rising into the middle of the picture.
    private func gestureTipSitsOnZoomRow(footerWidth: CGFloat) -> Bool {
        // footerWidth kept for call-site stability; rows come from the measured strip.
        let stripOpen: Bool = isShowingTools && !isShowingLiveAdjustments && !hidesToolsForRecoveryPlaceholder
        let tallStrip: Bool = dynamicTypeSize.isAccessibilitySize || isToolStripTwoRows || isShowingAidsTray
        return stripOpen && tallStrip
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
                .id(gestureTips.tip)
                .transition(gestureHintTransition)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(gestureHintText)
                .accessibilityIdentifier("camera-gesture-hint")
                .task(id: gestureTips.tip) {
                    guard let shown = gestureTips.tip else { return }
                    try? await Task.sleep(for: shown.duration)
                    guard !Task.isCancelled, gestureTips.tip == shown else { return }
                    dismissGestureHint()
                }
        }
    }

    private var gestureHintTransition: AnyTransition {
        let base: AnyTransition = reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom))
        // One second of empty slot before each tip appears.
        return AnyTransition.asymmetric(
            insertion: base.animation(.easeOut(duration: 0.2).delay(1)),
            removal: AnyTransition.opacity
        )
    }

    /// Timeout of the visible tip: moves to the next tip, or ends the sequence.
    private func dismissGestureHint() {
        guard !gestureHintSeen else { return }
        let unavailable: Set<CameraGestureTip> = camera.manualControls.exposureMode == .manual ? [.drag] : []
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            if gestureTips.advance(alsoSkipping: unavailable) { gestureHintSeen = true }
        }
    }

    private func noteGestureTipUsed(_ tip: CameraGestureTip) {
        guard !gestureHintSeen, !gestureTips.learned.contains(tip) else { return }
        if gestureTips.noteUsed(tip) { dismissGestureHint() }
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
                .overlay(alignment: .bottom) { fujiMenuActiveDot }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Q menu, shooting settings")
        .accessibilityValue(fujiMenuAccessibilityValue)
        .accessibilityHint("Drive, bracketing, shooting banks and other quick controls")
        .accessibilityInputLabels(["Q", "Q menu", "Shooting settings"])
        .accessibilityShowsLargeContentViewer { Text("Q menu") }
        .accessibilityIdentifier("fuji-q-menu")
    }

    /// Non-colour cue that the Q menu holds an active drive, bracket, bank or multiple exposure.
    @ViewBuilder
    private var fujiMenuActiveDot: some View {
        if shooting.needsCoordinator {
            Circle()
                .fill(FilmyTheme.filmAccent)
                .frame(width: 5, height: 5)
                .padding(.bottom, 5)
                .accessibilityHidden(true)
        }
    }

    private var fujiMenuAccessibilityValue: String {
        if shooting.isComposing { return "Multiple exposure in progress" }
        return shooting.needsCoordinator ? "Drive, bracket or bank active" : "Standard"
    }

    private func closeControlDrawers() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isShowingLookDrawer = false
            isShowingLiveAdjustments = false
            isShowingTools = false
            isShowingAidsTray = false
        }
    }

    /// The shutter closes Adjust only. The control strip and the look picker stay as the user set them.
    private func closeAdjustForCapture() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isShowingLiveAdjustments = false
        }
    }

    private func closeLookDrawer() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isShowingLookDrawer = false
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
                isShowingAidsTray = false
                lookStripActive = viewModel.quickRecipes
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
        camera.setFrameDeliveryPaused(pausesFrameDelivery)
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
            camera.setFrameDeliveryPaused(pausesFrameDelivery)
            camera.start()
        case .stop:
            camera.stop()
        case .stopAfterGrace:
            camera.stop(after: CameraActivityPolicy.deferredStopDelay(
                hasReview: viewModel.reviewImage != nil
            ))
        case .hold:
            camera.setFrameDeliveryPaused(pausesFrameDelivery)
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
    /// Identifies the shown image so a replacement cross-fades instead of swapping.
    @State private var imageKey: PhotoLibraryImageRequestKey?

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
                    .id(imageKey)
                    .transition(.opacity)
            } else {
                ChromeShapeBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        // Constrain the aspect-fill image before clipping, so portrait and
        // landscape photos cannot draw over the Roll label below it.
        .frame(width: FilmyTheme.toolControlHeight, height: FilmyTheme.toolControlHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(image == nil ? 0 : 0.5), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
        .task(id: requestKey) {
            // Keep the previous image while the new one loads; clear only when
            // there is nothing to load.
            guard let asset,
                  PhotoLibraryGalleryImagePolicy.canLoad(
                      isPhotosAsset: asset.isPhotosAsset,
                      authorizationStatus: photoLibrary.authorizationStatus
                  ) else {
                image = nil
                imageKey = nil
                return
            }

            let loadedImage = await photoLibrary.image(
                for: asset,
                targetSize: CGSize(width: 180, height: 180)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                image = loadedImage
                imageKey = requestKey
            }
        }
    }
}

/// Lands a just-saved frame at the Roll: a thumbnail flight from the viewfinder
/// to the Roll thumbnail, then an accent pulse. Reduce Motion, a missing anchor
/// or a missing thumbnail gets the pulse only. Never hit-testable or announced.
private struct SavedFrameLandingOverlay: View {
    let anchors: [SavedFrameAnchor: Anchor<CGRect>]
    let notice: CameraViewModel.SavedFrameNotice?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flight: SavedFrameFlightPlan?
    @State private var pulseToken = 0

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let rollRect: CGRect? = anchors[.rollThumbnail].map { proxy[$0] }
            let viewfinderRect: CGRect? = anchors[.viewfinder].map { proxy[$0] }
            ZStack(alignment: .topLeading) {
                pulseLayer(rollRect: rollRect)
                flightLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: notice?.revision) { _, revision in
                guard let revision else { return }
                land(revision: revision, from: viewfinderRect, to: rollRect)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pulseLayer(rollRect: CGRect?) -> some View {
        if pulseToken > 0, let rollRect {
            SavedFramePulse()
                .id(pulseToken)
                .frame(width: rollRect.width, height: rollRect.height)
                .position(x: rollRect.midX, y: rollRect.midY)
        }
    }

    @ViewBuilder
    private var flightLayer: some View {
        if let flight {
            SavedFrameFlight(plan: flight, onFinished: { finishFlight(revision: flight.revision) })
                .id(flight.revision)
        }
    }

    private func land(revision: Int, from: CGRect?, to: CGRect?) {
        guard !reduceMotion, let thumbnail = notice?.thumbnail, let from, let to else {
            pulseToken += 1
            return
        }
        flight = SavedFrameFlightPlan(revision: revision, image: thumbnail, from: from, to: to)
    }

    private func finishFlight(revision: Int) {
        guard flight?.revision == revision else { return }
        flight = nil
        pulseToken += 1
    }
}

private struct SavedFrameFlightPlan {
    let revision: Int
    let image: UIImage
    let from: CGRect
    let to: CGRect
}

private struct SavedFrameFlight: View {
    let plan: SavedFrameFlightPlan
    let onFinished: () -> Void

    @State private var landed = false

    var body: some View {
        let rect: CGRect = landed ? plan.to : plan.from
        Image(uiImage: plan.image)
            .resizable()
            .scaledToFill()
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .position(x: rect.midX, y: rect.midY)
            .onAppear {
                withAnimation(.easeIn(duration: 0.35), completionCriteria: .logicallyComplete) {
                    landed = true
                } completion: {
                    onFinished()
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                onFinished()
            }
    }
}

/// A 2 pt accent outline that fades over 0.6 s. Opacity only, so it runs under Reduce Motion.
private struct SavedFramePulse: View {
    @State private var faded = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(FilmyTheme.accent, lineWidth: 2)
            .opacity(faded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { faded = true }
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
            && !isShowingPendingOriginals
    }
    private var isSceneAutoViewfinderActive: Bool {
        isCameraVisibleForAssists && !countdown.state.isActive
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
        if isShowingPendingOriginals { return "pending-originals" }
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
        .accessibilityShowsLargeContentViewer {
            Label("Capture setup", systemImage: captureDelay == .off ? "viewfinder" : "timer")
        }
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
