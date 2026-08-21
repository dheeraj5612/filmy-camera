import Photos
import SwiftUI
import UIKit

struct GalleryScreen: View {
    @ObservedObject var photoLibrary: PhotoLibraryService

    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingPhoto = false
    @State private var selectedAsset: PhotoLibraryGalleryAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                FilmyPageBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeading(
                            eyebrow: "Library",
                            title: "Roll",
                            trailing: photoLibrary.galleryAssets.isEmpty ? nil : "\(photoLibrary.galleryAssets.count) frames"
                        )

                        Text("Every finished frame, organized in one place.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !photoLibrary.galleryAssets.isEmpty {
                            archiveSummary
                        }
                        galleryContent
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
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
        .sheet(isPresented: $isShowingPhoto) {
            if let selectedAsset {
                GalleryDetailView(asset: selectedAsset, photoLibrary: photoLibrary)
                    .presentationDetents([.large])
                    .presentationBackground(FilmyTheme.background)
                    .presentationCornerRadius(28)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var archiveSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(FilmyTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Contact sheet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FilmyTheme.accent)
                    Text("Recent frames, recipe by recipe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FilmyTheme.primary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(photoLibrary.galleryAssets.count)")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("frames")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FilmyTheme.tertiary)
                }
            }

            Rectangle()
                .fill(FilmyTheme.line)
                .frame(height: 1)

            HStack(spacing: 0) {
                archiveMetric(title: "ORDER", value: "NEWEST FIRST")
                Spacer(minLength: 12)
                archiveMetric(
                    title: "SOURCE",
                    value: archiveSourceLabel
                )
            }
        }
        .padding(16)
        .background(FilmyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contact sheet")
        .accessibilityValue(
            "\(photoLibrary.galleryAssets.count) frames. Source: \(archiveSourceLabel). Order: newest first."
        )
    }

    private var archiveSourceLabel: String {
        let assets = photoLibrary.galleryAssets
        let hasPhotosAssets = assets.contains(where: \.isPhotosAsset)
        let hasCachedAssets = assets.contains(where: { !$0.isPhotosAsset })

        switch (hasPhotosAssets, hasCachedAssets) {
        case (true, true):
            return "PHOTOS + CACHE"
        case (true, false):
            return photoLibrary.authorizationStatus == .limited ? "LIMITED PHOTOS" : "PHOTOS"
        case (false, true):
            return "LOCAL CACHE"
        case (false, false):
            return "—"
        }
    }

    private func archiveMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(FilmyTheme.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(FilmyTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func clearSelectionIfUnavailable() {
        guard let selectedAsset,
              !photoLibrary.galleryAssets.contains(where: { $0.id == selectedAsset.id }) else {
            return
        }
        self.selectedAsset = nil
        isShowingPhoto = false
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
                } else {
                    RollEmptyState(
                        systemName: "photo.on.rectangle.angled",
                        title: "Your frames will live here",
                        message: "Capture a moment with a recipe and it will appear in this quiet little roll."
                    )
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
                } else {
                    galleryGrid
                }
                limitedAccessControl
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
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    archiveAccessNotice
                    galleryGrid
                }
            }
        @unknown default:
            RollEmptyState(
                systemName: "photo",
                title: "Gallery unavailable",
                message: "Filmy Camera could not read the photo library right now."
            )
        }
    }

    private var limitedAccessControl: some View {
        Button {
            photoLibrary.presentLimitedLibraryPicker()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(FilmyTheme.mint.opacity(0.14))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FilmyTheme.mint)
                }
                .frame(width: 30, height: 30)

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
                    .foregroundStyle(FilmyTheme.accent)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(FilmyTheme.panel.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FilmyTheme.mint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityHint("Choose which saved Filmy Camera frames can be viewed in the Roll")
    }

    private var galleryGrid: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 8) {
                Text("RECENT FRAMES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(FilmyTheme.tertiary)

                Capsule()
                    .fill(FilmyTheme.line)
                    .frame(width: 4, height: 4)

                Text("CONTACT SHEET")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(FilmyTheme.accent)

                Spacer(minLength: 8)
                Text("NEWEST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(FilmyTheme.secondary)
            }

            GlassCard(padding: 11) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(photoLibrary.galleryAssets) { asset in
                        Button {
                            selectedAsset = asset
                            isShowingPhoto = true
                        } label: {
                            GalleryThumbnail(asset: asset, photoLibrary: photoLibrary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .accessibilityLabel(
                            photoLibrary.metadata(for: asset).map {
                                "Photo in your gallery, \($0.recipe.name)"
                            } ?? "Photo in your gallery"
                        )
                        .accessibilityHint("Opens frame details")
                    }
                }
            }
        }
    }

    private var archiveAccessNotice: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(FilmyTheme.accent.opacity(0.13))
                    Image(systemName: "lock.open")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FilmyTheme.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Showing your saved frames")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("Enable Photos read access to refresh this archive from your library.")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Button("Open Photos Settings", action: openSystemSettings)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                .accessibilityIdentifier("gallery-photos-permission-settings")
                .accessibilityHint("Opens Filmy Camera Photos permissions")
        }
        .padding(14)
        .background(FilmyTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(FilmyTheme.accent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Showing frames saved by Filmy Camera")
        .accessibilityValue("Enable Photos read access to refresh your archive")
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

    private var imageRequestKey: PhotoLibraryImageRequestKey {
        PhotoLibraryGalleryImagePolicy.requestKey(
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
                FilmyTheme.panel
                    .overlay {
                        VStack(spacing: 9) {
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(FilmyTheme.secondary)
                            ProgressView()
                                .tint(FilmyTheme.accent)
                                .scaleEffect(0.8)
                        }
                    }
            }
        }
        .aspectRatio(
            0.76,
            contentMode: .fit
        )
        .overlay {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if let metadata = photoLibrary.metadata(for: asset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.recipe.name)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(metadata.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 10, y: 6)
        .task(id: imageRequestKey) {
            image = nil
            guard PhotoLibraryGalleryImagePolicy.canLoad(
                isPhotosAsset: asset.isPhotosAsset,
                authorizationStatus: photoLibrary.authorizationStatus
            ) else {
                return
            }

            let loadedImage = await photoLibrary.image(
                for: asset,
                targetSize: CGSize(width: 360, height: 440)
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
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

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    FilmyTheme.panel

                    HStack(spacing: 7) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.055))
                                .frame(width: 22, height: 70)
                        }
                    }
                    .rotationEffect(.degrees(-10))
                    .offset(x: 112, y: -8)
                    .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(FilmyTheme.accent.opacity(0.14))
                            Image(systemName: systemName)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(FilmyTheme.accent)
                        }
                        .frame(width: 58, height: 58)

                        if let heroLabel {
                            Text(heroLabel)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.3)
                                .foregroundStyle(FilmyTheme.tertiary)
                        }
                    }
                }
                .frame(height: 154)
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

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FilmyTheme.mint)
                        Text("Finished frames stay here with their recipe and capture time.")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(FilmyTheme.mint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundStyle(FilmyTheme.background)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
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
            FilmyTheme.background.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 26)
                    .scaleEffect(zoomScale)
                    .offset(imageOffset)
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
                                }
                            }
                            .onEnded { _ in
                                pinchBaseZoom = nil
                                if zoomScale <= 1.05 {
                                    resetImageTransform()
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard zoomScale > 1 else { return }
                                imageOffset = CGSize(
                                    width: dragBaseOffset.width + value.translation.width,
                                    height: dragBaseOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                dragBaseOffset = imageOffset
                            }
                    )
                    .onTapGesture(count: 2, perform: resetImageTransform)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(FilmyTheme.accent)
                    Text("DEVELOPING FRAME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FilmyTheme.tertiary)
                }
            }
        }
        .task(id: imageRequestKey) {
            image = nil
            guard PhotoLibraryGalleryImagePolicy.canLoad(
                isPhotosAsset: asset.isPhotosAsset,
                authorizationStatus: photoLibrary.authorizationStatus
            ) else {
                return
            }

            let loadedImage = await photoLibrary.image(
                for: asset,
                targetSize: CGSize(width: 1600, height: 2200)
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailToolbar
        }
        .overlay(alignment: .bottom) {
            if let metadata = photoLibrary.metadata(for: asset) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RECIPE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.1)
                                .foregroundStyle(FilmyTheme.accent)
                            Text(metadata.recipe.name)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(zoomScale > 1 ? "ZOOM \(Int(zoomScale * 100))%" : "FIT TO SCREEN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(FilmyTheme.tertiary)
                    }

                    Text(metadata.recipe.subtitle)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))

                    HStack(spacing: 7) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        Text(metadata.capturedAt, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.58))
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
                .padding(.horizontal, 14)
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

    private var detailToolbar: some View {
        ZStack {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.panel, in: Circle())
                }
                .accessibilityLabel("Close frame")

                Spacer()

                Button {
                    shareFrame()
                } label: {
                    Group {
                        if isPreparingShare {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                        .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.panel, in: Circle())
                }
                .accessibilityLabel("Share frame")
                .disabled(image == nil || isDeleting || isPreparingShare)

                if photoLibrary.canDelete(asset: asset) {
                    Button {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                            .background(FilmyTheme.panel, in: Circle())
                    }
                    .accessibilityLabel("Delete frame")
                    .disabled(isDeleting)
                }
            }

            VStack(spacing: 2) {
                Text("ROLL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(FilmyTheme.accent)
                Text("FRAME DETAIL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(FilmyTheme.primary)
            }
            .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
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
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
