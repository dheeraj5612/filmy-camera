import Photos
import SwiftUI
import UIKit

/// The Roll: a contact sheet of every frame kept with Filmy Camera. Three
/// square columns run nearly edge to edge so the frames, not the chrome, fill
/// the screen.
struct GalleryScreen: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedAsset: PhotoLibraryGalleryAsset?
    @AppStorage("rollRoomyGrid") private var roomyGrid = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Three columns on iPhone; iPad widths flow as many ~200pt squares as
    /// fit so the contact sheet does not become three enormous tiles.
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: roomyGrid ? 240 : 168, maximum: roomyGrid ? 360 : 240), spacing: 6)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: roomyGrid || dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FilmyPageBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(
                            eyebrow: "LIBRARY",
                            title: "Roll",
                            trailing: photoLibrary.galleryAssets.isEmpty ? nil : "\(photoLibrary.galleryAssets.count) frames"
                        )
                        .padding(.horizontal, FilmyTheme.pageMargin)

                        if !photoLibrary.galleryAssets.isEmpty {
                            rollSummary
                                .padding(.horizontal, FilmyTheme.pageMargin)
                        }

                        galleryContent

                        if photoLibrary.galleryAssets.isEmpty {
                            Button(action: onBackToCamera) {
                                Label("Make your first frame", systemImage: "camera")
                            }
                            .buttonStyle(.filmyPrimary)
                            .padding(.horizontal, FilmyTheme.pageMargin)
                            .accessibilityIdentifier("roll-start-shooting")
                            .accessibilityHint("Returns to the camera without changing Photos permissions")
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CameraReturnBar(accessibilityIdentifier: "roll-back-to-camera", action: onBackToCamera)
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                photoLibrary.refresh()
            }
        }
        .task {
            // Keep the Roll useful without prompting for broad Photos read
            // access. It displays frames created by Filmy Camera and its
            // private local fallback cache.
            photoLibrary.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            photoLibrary.refresh()
            clearSelectionIfUnavailable()
        }
        .onChange(of: photoLibrary.authorizationStatus) { _, _ in
            clearSelectionIfUnavailable()
        }
        .onChange(of: photoLibrary.assets.map(\.localIdentifier)) { _, _ in
            clearSelectionIfUnavailable()
        }
        .onChange(of: photoLibrary.localSavedFrames.map(\.assetIdentifier)) { _, _ in
            clearSelectionIfUnavailable()
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedAsset != nil },
            set: { if !$0 { selectedAsset = nil } }
        )) {
            GalleryPager(
                selection: $selectedAsset,
                photoLibrary: photoLibrary,
                onBackToCamera: onBackToCamera
            )
            .ignoresSafeArea()
            .presentationBackground(.black)
        }
    }

    private var rollSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
            Text("Newest first")
            Text("·")
            Text(archiveSourceLabel)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                HapticFeedback.play(.selection)
                roomyGrid.toggle()
            } label: {
                Image(systemName: roomyGrid ? "square.grid.3x3" : "square.grid.2x2")
                    .font(.system(.subheadline).weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                    .frame(width: 48, height: 48)
                    .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("roll-grid-layout")
            .accessibilityLabel("Change Roll layout")
            .accessibilityValue(roomyGrid ? "Roomy grid" : "Contact sheet")
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(FilmyTheme.secondary)
        .accessibilityElement(children: .contain)
    }

    private var archiveSourceLabel: String {
        let assets = photoLibrary.galleryAssets
        let hasPhotosAssets = assets.contains(where: \.isPhotosAsset)
        let hasCachedAssets = assets.contains(where: { !$0.isPhotosAsset })

        switch (hasPhotosAssets, hasCachedAssets) {
        case (true, true):
            return "Photos and local cache"
        case (true, false):
            return photoLibrary.authorizationStatus == .limited ? "Limited Photos access" : "Photos"
        case (false, true):
            return "Local cache"
        case (false, false):
            return "No source"
        }
    }

    /// Keeps the open detail sheet pointed at the entry the Roll currently
    /// lists for that frame. An authorization change can swap a Photos asset
    /// for its cached fallback (or back); the sheet must follow that swap
    /// rather than keep loading a source that is no longer available.
    private func clearSelectionIfUnavailable() {
        guard let selectedAsset else { return }
        guard let current = photoLibrary.galleryAssets.first(where: { $0.id == selectedAsset.id }) else {
            self.selectedAsset = nil
            return
        }
        if current.isPhotosAsset != selectedAsset.isPhotosAsset {
            self.selectedAsset = current
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        switch photoLibrary.authorizationStatus {
        case .authorized, .notDetermined:
            if photoLibrary.galleryAssets.isEmpty {
                if photoLibrary.authorizationStatus == .notDetermined {
                    RollEmptyState(
                        systemName: "photo.badge.plus",
                        title: "Give your roll a home",
                        message: "Allow photo access to show the frames you have made with Filmy Camera.",
                        actionTitle: "Allow Photos access",
                        action: requestReadAccess
                    )
                    .padding(.horizontal, FilmyTheme.pageMargin)
                } else {
                    RollEmptyState(
                        systemName: "photo.on.rectangle.angled",
                        title: "Your frames will live here",
                        message: "Take a photo, choose your look, then save it to see it here."
                    )
                    .padding(.horizontal, FilmyTheme.pageMargin)
                }
            } else {
                galleryGrid
            }
        case .limited:
            VStack(alignment: .leading, spacing: 14) {
                if photoLibrary.galleryAssets.isEmpty {
                    RollEmptyState(
                        systemName: "photo.on.rectangle.angled",
                        title: "Your selected roll is empty",
                        message: "Filmy Camera can only show frames saved by Filmy Camera that you allow it to read."
                    )
                    .padding(.horizontal, FilmyTheme.pageMargin)
                } else {
                    galleryGrid
                }
                limitedAccessControl
                    .padding(.horizontal, FilmyTheme.pageMargin)
            }
        case .denied, .restricted:
            if photoLibrary.galleryAssets.isEmpty {
                RollEmptyState(
                    systemName: "lock.slash",
                    title: "Photo access is off",
                    message: "Enable Photos access in Settings to see your saved frames.",
                    heroLabel: nil,
                    actionTitle: "Open Settings",
                    action: openSystemSettings
                )
                .padding(.horizontal, FilmyTheme.pageMargin)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    archiveAccessNotice
                        .padding(.horizontal, FilmyTheme.pageMargin)
                    galleryGrid
                }
            }
        @unknown default:
            RollEmptyState(
                systemName: "photo",
                title: "Gallery unavailable",
                message: "Filmy Camera could not read the photo library right now."
            )
            .padding(.horizontal, FilmyTheme.pageMargin)
        }
    }

    private var limitedAccessControl: some View {
        Button {
            photoLibrary.presentLimitedLibraryPicker()
        } label: {
            HStack(spacing: 12) {
                SettingIcon(systemName: "checkmark.circle", tint: FilmyTheme.mint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage access to saved frames")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("Choose which frames the Roll can see")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityHint("Choose which saved Filmy Camera frames can be viewed in the Roll")
    }

    private var galleryGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(photoLibrary.galleryAssets) { asset in
                Button {
                    selectedAsset = asset
                } label: {
                    GalleryThumbnail(asset: asset, photoLibrary: photoLibrary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    photoLibrary.metadata(for: asset).map {
                        "Photo in your gallery, \($0.recipe.name)"
                    } ?? "Photo in your gallery"
                )
                .accessibilityHint("Opens frame details")
            }
        }
        .padding(.horizontal, 6)
    }

    private var archiveAccessNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingIcon(systemName: "lock.open")

            VStack(alignment: .leading, spacing: 6) {
                Text("Showing your saved frames")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text("Enable Photos read access to refresh this roll from your library.")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Photos Settings", action: openSystemSettings)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                    .accessibilityIdentifier("gallery-photos-permission-settings")
                    .accessibilityHint("Opens Filmy Camera Photos permissions")
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(FilmyTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.accent.opacity(0.26), lineWidth: 1)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestReadAccess() {
        Task { _ = await photoLibrary.requestAccessIfNeeded() }
    }
}

private struct GalleryThumbnail: View {
    let asset: PhotoLibraryGalleryAsset
    @ObservedObject var photoLibrary: PhotoLibraryService

    @State private var image: UIImage?
    @State private var imageLoadFailed = false

    private var imageRequestKey: PhotoLibraryImageRequestKey {
        PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: asset.assetIdentifier,
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        )
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if imageLoadFailed {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 18, weight: .medium))
                        Text("Unavailable")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(FilmyTheme.secondary)
                } else {
                    FilmyTheme.panel
                        .overlay {
                            ProgressView()
                                .tint(FilmyTheme.accent)
                                .scaleEffect(0.8)
                        }
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let metadata = photoLibrary.metadata(for: asset) {
                    Text(metadata.recipe.name)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .task(id: imageRequestKey) {
                image = nil
                imageLoadFailed = false
                guard PhotoLibraryGalleryImagePolicy.canLoad(
                    isPhotosAsset: asset.isPhotosAsset,
                    authorizationStatus: photoLibrary.authorizationStatus
                ) else {
                    imageLoadFailed = true
                    return
                }

                let loadedImage = await photoLibrary.image(
                    for: asset,
                    targetSize: CGSize(width: 400, height: 400)
                )
                guard !Task.isCancelled else { return }
                image = loadedImage
                imageLoadFailed = loadedImage == nil
            }
    }
}

private struct RollEmptyState: View {
    let systemName: String
    let title: String
    let message: String
    var heroLabel: String? = "NO FRAMES YET"
    var actionTitle: String?
    var action: (() -> Void)?

    private var sampleRecipes: [FilmRecipe] {
        Array(FilmRecipe.builtIns.prefix(3))
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    FilmyTheme.backgroundRaised

                    HStack(spacing: -22) {
                        ForEach(Array(sampleRecipes.enumerated()), id: \.element.id) { index, recipe in
                            RecipeSwatch(recipe: recipe, compact: true, showsLabel: false)
                                .frame(width: 92, height: 62)
                                .rotationEffect(.degrees(Double(index - 1) * 7))
                                .offset(y: index == 1 ? -6 : 4)
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                                .zIndex(index == 1 ? 1 : 0)
                        }
                    }
                    .opacity(0.9)

                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: systemName)
                                .font(.system(size: 11, weight: .bold))
                            if let heroLabel {
                                Text(heroLabel)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1.2)
                            }
                        }
                        .foregroundStyle(FilmyTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(FilmyTheme.accent.opacity(0.14), in: Capsule())
                        .padding(.bottom, 12)
                    }
                }
                .frame(height: 150)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: FilmyTheme.cornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: FilmyTheme.cornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .font(.system(.subheadline, design: .default).weight(.medium))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.filmyPrimary)
                            .accessibilityHint("Opens the relevant permission settings")
                    }
                }
                .padding(18)
            }
        }
    }
}

/// UIKit owns the interactive horizontal slide and cancellation physics.
/// Selection changes only after a completed transition, not during a drag.
private struct GalleryPager: UIViewControllerRepresentable {
    @Binding var selection: PhotoLibraryGalleryAsset?
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 16]
        )
        pager.view.backgroundColor = .black
        pager.view.accessibilityIdentifier = "gallery-pager"
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        context.coordinator.pager = pager
        context.coordinator.synchronize(with: self)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.synchronize(with: self)
    }

    static func dismantleUIViewController(_ pager: UIPageViewController, coordinator: Coordinator) {
        pager.dataSource = nil
        pager.delegate = nil
        coordinator.pages.removeAll()
        coordinator.pager = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: GalleryPager
        weak var pager: UIPageViewController?
        var pages: [String: GalleryPageController] = [:]
        private var assets: [PhotoLibraryGalleryAsset] = []
        private var indices: [String: Int] = [:]
        private var isTransitioning = false
        private var needsSynchronization = false
        private var activeID: String?

        init(parent: GalleryPager) { self.parent = parent }

        func synchronize(with parent: GalleryPager) {
            self.parent = parent
            guard let pager else { return }
            guard !isTransitioning else {
                needsSynchronization = true
                return
            }
            needsSynchronization = false
            guard let selection = parent.selection else {
                pages.removeAll()
                return
            }
            refreshSnapshot()
            guard let index = indices[selection.id] else {
                // The selected frame may disappear when Photos authorization
                // or the source changes. Dismiss the stale detail immediately
                // instead of leaving an orphaned page on screen.
                pages.removeAll()
                self.parent.selection = nil
                return
            }
            let current = pager.viewControllers?.first as? GalleryPageController
            if current?.assetIdentifier != selection.id {
                pager.setViewControllers([page(at: index)], direction: .forward, animated: false)
            }
            finishSelection(at: index)
        }

        private func refreshSnapshot() {
            assets = parent.photoLibrary.galleryAssets
            indices = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($0.element.id, $0.offset) })
        }

        private func detail(for asset: PhotoLibraryGalleryAsset) -> GalleryDetailView {
            GalleryDetailView(
                asset: asset,
                photoLibrary: parent.photoLibrary,
                onBackToCamera: parent.onBackToCamera,
                onClose: { [weak self] in self?.parent.selection = nil },
                onZoomChanged: { [weak self] zoomed in
                    guard let self,
                          (self.pager?.viewControllers?.first as? GalleryPageController)?.assetIdentifier == asset.id else { return }
                    self.pager?.view.subviews.compactMap { $0 as? UIScrollView }.forEach {
                        $0.isScrollEnabled = !zoomed
                    }
                },
                onPreviousPhoto: { [weak self] in self?.move(by: -1) },
                onNextPhoto: { [weak self] in self?.move(by: 1) }
            )
        }

        private func page(at index: Int) -> GalleryPageController {
            let asset = assets[index]
            if let existing = pages[asset.id] { return existing }
            let controller = GalleryPageController(assetIdentifier: asset.id, rootView: detail(for: asset))
            controller.view.backgroundColor = .black
            controller.view.accessibilityElementsHidden = true
            pages[asset.id] = controller
            return controller
        }

        private func adjacent(to controller: UIViewController, offset: Int) -> UIViewController? {
            guard let controller = controller as? GalleryPageController,
                  let index = indices[controller.assetIdentifier],
                  let next = GalleryPagingPolicy.neighbor(of: index, offset: offset, count: assets.count) else { return nil }
            return page(at: next)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? {
            adjacent(to: controller, offset: -1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? {
            adjacent(to: controller, offset: 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            _ = finished
            _ = completed
            let currentID = (pageViewController.viewControllers?.first as? GalleryPageController)?.assetIdentifier
            synchronizeSelectionAfterTransition(currentID: currentID)
        }

        private func move(by offset: Int) {
            guard !isTransitioning, let pager,
                  let current = pager.viewControllers?.first as? GalleryPageController,
                  let index = indices[current.assetIdentifier],
                  let next = GalleryPagingPolicy.neighbor(of: index, offset: offset, count: assets.count) else { return }
            isTransitioning = true
            pager.setViewControllers(
                [page(at: next)], direction: offset > 0 ? .forward : .reverse,
                animated: !UIAccessibility.isReduceMotionEnabled
            ) { [weak self] finished in
                guard let self else { return }
                self.isTransitioning = false
                _ = finished
                let currentID = (self.pager?.viewControllers?.first as? GalleryPageController)?.assetIdentifier
                self.synchronizeSelectionAfterTransition(currentID: currentID)
            }
        }

        private func synchronizeSelectionAfterTransition(currentID: String?) {
            guard pager != nil else { return }
            refreshSnapshot()
            if let currentID,
               let current = assets.first(where: { $0.id == currentID }) {
                // Resolve the completed page against the latest Photos
                // snapshot. This avoids selecting an asset at a stale index
                // when the source changed while the transition was running.
                parent.selection = current
            } else if let selection = parent.selection,
                      let current = assets.first(where: { $0.id == selection.id }) {
                parent.selection = current
            } else {
                parent.selection = nil
            }
            synchronize(with: parent)
        }

        private func finishSelection(at index: Int) {
            let currentID = assets[index].id
            if activeID != currentID {
                pager?.view.subviews.compactMap { $0 as? UIScrollView }.forEach { $0.isScrollEnabled = true }
                activeID = currentID
            }
            let retainedIDs = Set(GalleryPagingPolicy.retainedIndices(around: index, count: assets.count).map { assets[$0].id })
            pages = pages.filter { retainedIDs.contains($0.key) }
            for (id, controller) in pages {
                // Rebuild every retained page from the latest asset. Photos
                // authorization and source changes can replace the backing
                // image while the page controller itself remains cached.
                if let asset = assets.first(where: { $0.id == id }) {
                    controller.rootView = detail(for: asset)
                }
                controller.view.accessibilityElementsHidden = id != currentID
            }
            pager?.view.accessibilityValue = "\(index + 1) of \(assets.count)"
        }
    }
}

@MainActor
private final class GalleryPageController: UIHostingController<GalleryDetailView> {
    let assetIdentifier: String

    init(assetIdentifier: String, rootView: GalleryDetailView) {
        self.assetIdentifier = assetIdentifier
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(assetIdentifier:rootView:)") }
}

private struct GalleryDetailView: View {
    let asset: PhotoLibraryGalleryAsset
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void

    let onClose: () -> Void
    let onZoomChanged: (Bool) -> Void
    let onPreviousPhoto: () -> Void
    let onNextPhoto: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var imageLoadFailed = false
    @State private var loadGeneration = 0
    @State private var retryGeneration = 0
    @State private var shareURL: URL?
    @State private var isShowingShareSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var actionErrorMessage: String?
    @State private var zoomScale: CGFloat = 1
    @State private var pinchBaseZoom: CGFloat?
    @State private var imageOffset: CGSize = .zero
    @State private var dragBaseOffset: CGSize = .zero
    @State private var dragStartedZoomed = false
    @State private var isDraggingFrame = false
    @State private var shareGeneration = 0

    private var imageRequestKey: PhotoLibraryImageRequestKey {
        PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: asset.assetIdentifier,
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                frameContent(in: proxy.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(frameDragGesture(in: proxy.size))
            .clipped()
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: zoomScale) { _, scale in onZoomChanged(scale > 1) }
        .onDisappear { onZoomChanged(false) }
        .accessibilityAction(named: "Previous photo") {
            guard !isPagingLocked else { return }
            onPreviousPhoto()
        }
        .accessibilityAction(named: "Next photo") {
            guard !isPagingLocked else { return }
            onNextPhoto()
        }
        .task(id: imageTaskID) {
            await loadImage()
        }
        .onDisappear {
            shareGeneration &+= 1
            if !isShowingShareSheet, let shareURL {
                photoLibrary.removeTemporaryShare(at: shareURL)
                self.shareURL = nil
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailToolbar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if photoLibrary.galleryAssets.count > 1 {
                    pagingControls
                }
                if let metadata = photoLibrary.metadata(for: asset) {
                    metadataCard(metadata)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(photoLibrary.metadata(for: asset).map { "Selected gallery photo, \($0.recipe.name)" } ?? "Selected gallery photo")
        .sheet(isPresented: $isShowingShareSheet, onDismiss: {
            if let shareURL {
                photoLibrary.removeTemporaryShare(at: shareURL)
            }
            shareURL = nil
        }) {
            if let shareURL {
                ShareSheet(items: [shareURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(
            "Delete this frame?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Frame", role: .destructive) {
                deleteFrame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the frame from Photos and from your Filmy Camera roll.")
        }
        .alert(
            "Couldn’t update frame",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Try again in a moment.")
        }
    }

    @ViewBuilder
    private func frameContent(in viewport: CGSize) -> some View {
        if let image {
            let fittedSize = fittedImageSize(for: image.size, in: viewport)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fittedSize.width, height: fittedSize.height)
                .padding(.vertical, 20)
                .scaleEffect(zoomScale)
                .offset(constrainedOffset(imageOffset, in: viewport))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .accessibilityLabel("Photo")
                .accessibilityValue(zoomScale > 1 ? "Zoomed \(Int(zoomScale * 100)) percent" : "Fit to screen")
                .accessibilityHint("Swipe left or right for another frame. Pinch to zoom, drag while zoomed, or double tap to reset.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        zoomScale = min(zoomScale + 0.5, 4)
                    case .decrement:
                        zoomScale = max(zoomScale - 0.5, 1)
                    @unknown default:
                        break
                    }
                    if zoomScale == 1 {
                        resetImageTransform()
                    } else {
                        imageOffset = constrainedOffset(imageOffset, in: viewport)
                        dragBaseOffset = imageOffset
                    }
                }
                .accessibilityAction(named: "Reset zoom", resetImageTransform)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            dragStartedZoomed = true
                            let baseZoom = pinchBaseZoom ?? zoomScale
                            if pinchBaseZoom == nil { pinchBaseZoom = zoomScale }
                            zoomScale = min(max(baseZoom * value, 1), 4)
                            if zoomScale == 1 {
                                imageOffset = .zero
                                dragBaseOffset = .zero
                            } else {
                                imageOffset = constrainedOffset(imageOffset, in: viewport)
                            }
                        }
                        .onEnded { _ in
                            pinchBaseZoom = nil
                            if zoomScale <= 1.05 {
                                resetImageTransform()
                            } else {
                                imageOffset = constrainedOffset(imageOffset, in: viewport)
                                dragBaseOffset = imageOffset
                            }
                        }
                )
                .onTapGesture(count: 2, perform: resetImageTransform)
        } else if imageLoadFailed {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(FilmyTheme.secondary)
                Eyebrow(text: "FRAME COULDN’T LOAD")
                Button("Try Again") { retryGeneration &+= 1 }
                    .buttonStyle(.filmyPrimary)
                    .disabled(isLoadingImage)
                    .accessibilityIdentifier("gallery-image-retry")
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(FilmyTheme.accent)
                Eyebrow(text: "DEVELOPING FRAME")
            }
        }
    }

    private var isNavigationLocked: Bool {
        isDeleting || isPreparingShare || isShowingShareSheet || isShowingDeleteConfirmation
    }

    private var isPagingLocked: Bool {
        isNavigationLocked || zoomScale > 1.001 || pinchBaseZoom != nil
    }

    private var pagingControls: some View {
        HStack(spacing: 16) {
            Button { moveFrame(.previous) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous frame")
            .accessibilityIdentifier("gallery-previous-frame")
            .disabled(adjacentAsset(.previous) == nil || isPagingLocked)

            Text("\(currentFrameNumber) of \(photoLibrary.galleryAssets.count)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 80)
                .accessibilityLabel("Frame")
                .accessibilityValue("\(currentFrameNumber) of \(photoLibrary.galleryAssets.count)")
                .accessibilityIdentifier("gallery-frame-position")

            Button { moveFrame(.next) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next frame")
            .accessibilityIdentifier("gallery-next-frame")
            .disabled(adjacentAsset(.next) == nil || isPagingLocked)
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .viewfinderChrome(Capsule())
    }

    private var currentFrameNumber: Int {
        photoLibrary.galleryAssets.firstIndex(where: { $0.id == asset.id }).map { $0 + 1 } ?? 0
    }

    private func adjacentAsset(_ direction: GalleryPagingDirection) -> PhotoLibraryGalleryAsset? {
        let assets = photoLibrary.galleryAssets
        guard let target = GalleryPagingPolicy.targetIdentifier(
            in: assets.map(\.id), selectedIdentifier: asset.id, direction: direction
        ) else { return nil }
        return assets.first(where: { $0.id == target })
    }

    private func moveFrame(_ direction: GalleryPagingDirection) {
        guard !isPagingLocked, adjacentAsset(direction) != nil else { return }
        // Clear the old pixels before asking the pager to move. The coordinator
        // replaces the retained page with the latest asset after transition.
        image = nil
        imageLoadFailed = false
        loadGeneration &+= 1
        resetImageTransform()
        switch direction {
        case .previous:
            onPreviousPhoto()
        case .next:
            onNextPhoto()
        }
        HapticFeedback.play(.selection)
    }

    private func frameDragGesture(in viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isNavigationLocked else { return }
                if !isDraggingFrame {
                    dragStartedZoomed = zoomScale > 1 || pinchBaseZoom != nil
                    isDraggingFrame = true
                }
                if zoomScale > 1 || pinchBaseZoom != nil { dragStartedZoomed = true }
                guard zoomScale > 1 else { return }
                imageOffset = constrainedOffset(
                    CGSize(
                        width: dragBaseOffset.width + value.translation.width,
                        height: dragBaseOffset.height + value.translation.height
                    ),
                    in: viewport
                )
            }
            .onEnded { value in
                defer {
                    dragStartedZoomed = false
                    isDraggingFrame = false
                }
                dragBaseOffset = imageOffset
                guard !dragStartedZoomed, !isNavigationLocked,
                      let direction = GalleryPagingPolicy.swipeDirection(
                        translation: value.translation,
                        viewportWidth: viewport.width,
                        zoomScale: zoomScale
                      ) else { return }
                moveFrame(direction)
            }
    }

    private var imageTaskID: String {
        "\(imageRequestKey.assetIdentifier)|\(imageRequestKey.authorizationStatusRawValue ?? -1)|\(retryGeneration)"
    }

    private func metadataCard(_ metadata: SavedFrameMetadata) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RecipeSwatch(recipe: metadata.recipe, compact: true, showsLabel: false)
                .frame(width: 52, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata.recipe.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metadata.capturedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
            }

            Spacer(minLength: 8)

            Text(zoomScale > 1 ? "\(Int(zoomScale * 100))%" : "FIT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.72))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .viewfinderChrome(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gallery-frame-metadata")
    }

    private var detailToolbar: some View {
        HStack(spacing: 10) {
            FilmyIconButton(systemName: "xmark", accessibilityLabel: "Close frame") {
                onClose()
            }

            BackToCameraButton(accessibilityIdentifier: "frame-back-to-camera") {
                onClose()
                onBackToCamera()
            }

            Spacer()

            Button {
                shareFrame()
            } label: {
                Group {
                    if isPreparingShare {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                .background { ChromeShapeBackground(shape: Circle()) }
                .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Share frame")
            .disabled(image == nil || isDeleting || isPreparingShare)

            if photoLibrary.canDelete(asset: asset) {
                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FilmyTheme.danger)
                        .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                        .background { ChromeShapeBackground(shape: Circle()) }
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Delete frame")
                .disabled(isDeleting || isPreparingShare)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func deleteFrame() {
        isDeleting = true
        photoLibrary.delete(asset: asset) { result in
            isDeleting = false
            switch result {
            case .success:
                onClose()
            case .failure(let error):
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func shareFrame() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        shareGeneration &+= 1
        let generation = shareGeneration
        let sharingAsset = asset
        let requestKey = imageRequestKey
        Task { @MainActor in
            let url = await photoLibrary.shareURL(for: sharingAsset)
            guard generation == shareGeneration,
                  requestKey == imageRequestKey else {
                if let url { photoLibrary.removeTemporaryShare(at: url) }
                isPreparingShare = false
                return
            }
            isPreparingShare = false
            guard let url else {
                actionErrorMessage = "The original frame could not be prepared for sharing. Try again in a moment."
                return
            }
            shareURL = url
            isShowingShareSheet = true
        }
    }

    /// Each request is stamped with a generation so a replacement load (a
    /// new request key while one is in flight) always supersedes the older
    /// one instead of being rejected by it.
    private func loadImage() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let loadingAsset = asset
        let requestKey = imageRequestKey

        image = nil
        imageLoadFailed = false
        isLoadingImage = true
        resetImageTransform()

        guard PhotoLibraryGalleryImagePolicy.canLoad(
            isPhotosAsset: loadingAsset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        ) else {
            isLoadingImage = false
            imageLoadFailed = true
            return
        }

        let loadedImage = await photoLibrary.image(
            for: loadingAsset,
            targetSize: CGSize(width: 1600, height: 2200),
            contentMode: .aspectFit
        )
        guard generation == loadGeneration, requestKey == imageRequestKey,
              !Task.isCancelled else { return }

        image = loadedImage
        imageLoadFailed = loadedImage == nil
        isLoadingImage = false
    }

    private func resetImageTransform() {
        var transaction = Transaction()
        transaction.animation = reduceMotion
            ? nil
            : .spring(response: 0.28, dampingFraction: 0.82)
        // A nil animation does not override every animation inherited from a
        // parent transaction. Disable animations explicitly for Reduce Motion
        // so double-tap, VoiceOver, and pinch resets all behave consistently.
        transaction.disablesAnimations = reduceMotion

        withTransaction(transaction) {
            zoomScale = 1
            pinchBaseZoom = nil
            imageOffset = .zero
            dragBaseOffset = .zero
        }
    }

    /// Keep at least part of a zoomed image in the viewport. Without this
    /// bound, a long drag could move a frame completely offscreen and leave
    /// the detail sheet looking empty until the user reset zoom.
    private func constrainedOffset(_ offset: CGSize, in viewport: CGSize) -> CGSize {
        // `scaledToFit` receives the viewport after the 20pt vertical padding
        // on each side. Use that actual fitted image size: a portrait or
        // panoramic frame has empty margins in one axis and should not be
        // allowed to drift out of view as though it filled the whole sheet.
        let fittedSize = fittedImageSize(for: image?.size ?? viewport, in: viewport)
        let paddedSize = CGSize(width: fittedSize.width, height: fittedSize.height + 40)
        let maxX = max(0, (paddedSize.width * zoomScale - viewport.width) / 2)
        let maxY = max(0, (paddedSize.height * zoomScale - viewport.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func fittedImageSize(for imageSize: CGSize, in viewport: CGSize) -> CGSize {
        let availableImageSize = CGSize(
            width: max(viewport.width, 1),
            height: max(viewport.height - 40, 1)
        )
        let fitScale = min(
            availableImageSize.width / max(imageSize.width, 1),
            availableImageSize.height / max(imageSize.height, 1)
        )
        return CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad presents activity sheets as popovers. Give UIKit a stable,
        // centered anchor so sharing never crashes or chooses an off-screen
        // source when the detail view is opened from a narrow split view.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(
                x: controller.view.bounds.midX,
                y: controller.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
