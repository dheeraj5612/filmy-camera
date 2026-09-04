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

    /// Three columns on iPhone; iPad widths flow as many ~200pt squares as
    /// fit so the contact sheet does not become three enormous tiles.
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: 3)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
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
        .fullScreenCover(item: $selectedAsset) { asset in
            GalleryDetailView(
                asset: asset,
                photoLibrary: photoLibrary,
                onBackToCamera: onBackToCamera
            )
                .presentationBackground(FilmyTheme.background)
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
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(FilmyTheme.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Newest first. Source: \(archiveSourceLabel)")
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
                        message: "Capture a moment with a recipe and it will appear in this quiet little roll."
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
        LazyVGrid(columns: columns, spacing: 3) {
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
        .padding(.horizontal, 3)
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

private struct GalleryDetailView: View {
    let asset: PhotoLibraryGalleryAsset
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var imageLoadFailed = false
    @State private var loadGeneration = 0
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

    private var imageRequestKey: PhotoLibraryImageRequestKey {
        PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: asset.assetIdentifier,
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { proxy in
                    let fittedSize = fittedImageSize(for: image.size, in: proxy.size)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .padding(.vertical, 20)
                        .scaleEffect(zoomScale)
                        .offset(constrainedOffset(imageOffset, in: proxy.size))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Photo")
                        .accessibilityValue(zoomScale > 1 ? "Zoomed \(Int(zoomScale * 100)) percent" : "Fit to screen")
                        .accessibilityHint("Pinch to zoom, drag while zoomed, or double tap to reset")
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
                            }
                        }
                        .accessibilityAction(named: "Reset zoom", resetImageTransform)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let baseZoom = pinchBaseZoom ?? zoomScale
                                    if pinchBaseZoom == nil {
                                        pinchBaseZoom = zoomScale
                                    }
                                    zoomScale = min(max(baseZoom * value, 1), 4)
                                    if zoomScale == 1 {
                                        imageOffset = .zero
                                        dragBaseOffset = .zero
                                    } else {
                                        imageOffset = constrainedOffset(imageOffset, in: proxy.size)
                                    }
                                }
                                .onEnded { _ in
                                    pinchBaseZoom = nil
                                    if zoomScale <= 1.05 {
                                        resetImageTransform()
                                    } else {
                                        imageOffset = constrainedOffset(imageOffset, in: proxy.size)
                                        dragBaseOffset = imageOffset
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    guard zoomScale > 1 else { return }
                                    imageOffset = constrainedOffset(
                                        CGSize(
                                            width: dragBaseOffset.width + value.translation.width,
                                            height: dragBaseOffset.height + value.translation.height
                                        ),
                                        in: proxy.size
                                    )
                                }
                                .onEnded { _ in
                                    dragBaseOffset = imageOffset
                                }
                        )
                        .onTapGesture(count: 2, perform: resetImageTransform)
                }
            } else if imageLoadFailed {
                VStack(spacing: 14) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(FilmyTheme.secondary)
                    Eyebrow(text: "FRAME COULDN’T LOAD")
                    Button("Try Again") {
                        Task { await loadImage() }
                    }
                    .buttonStyle(.filmyPrimary)
                    .disabled(isLoadingImage)
                    .accessibilityIdentifier("gallery-image-retry")
                }
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(FilmyTheme.accent)
                    Eyebrow(text: "DEVELOPING FRAME")
                }
            }
        }
        .task(id: imageRequestKey) {
            await loadImage()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailToolbar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let metadata = photoLibrary.metadata(for: asset) {
                metadataCard(metadata)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
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
    }

    private var detailToolbar: some View {
        HStack(spacing: 10) {
            FilmyIconButton(systemName: "xmark", accessibilityLabel: "Close frame") {
                dismiss()
            }

            BackToCameraButton(accessibilityIdentifier: "frame-back-to-camera") {
                dismiss()
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
                .disabled(isDeleting)
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
                dismiss()
            case .failure(let error):
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func shareFrame() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task { @MainActor in
            let url = await photoLibrary.shareURL(for: asset)
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
        loadGeneration += 1
        let generation = loadGeneration

        image = nil
        imageLoadFailed = false
        isLoadingImage = true

        guard PhotoLibraryGalleryImagePolicy.canLoad(
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        ) else {
            isLoadingImage = false
            imageLoadFailed = true
            return
        }

        let loadedImage = await photoLibrary.image(
            for: asset,
            targetSize: CGSize(width: 1600, height: 2200),
            contentMode: .aspectFit
        )
        guard generation == loadGeneration, !Task.isCancelled else { return }

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
