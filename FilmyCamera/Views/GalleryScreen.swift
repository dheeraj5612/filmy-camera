import Photos
import SwiftUI
import UIKit

struct GalleryScreen: View {
    @ObservedObject var photoLibrary: PhotoLibraryService

    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingPhoto = false
    @State private var selectedAsset: PhotoLibraryGalleryAsset?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(
                        eyebrow: "The archive",
                        title: "Roll",
                        trailing: photoLibrary.galleryAssets.isEmpty ? nil : "\(photoLibrary.galleryAssets.count) frames"
                    )

                    Text("A contact sheet for the frames worth keeping.")
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
            .background(FilmyTheme.background.ignoresSafeArea())
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
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var archiveSummary: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FilmyTheme.accent.opacity(0.14))
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FilmyTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("CONTACT SHEET")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(FilmyTheme.accent)
                Text("Recent frames, recipe by recipe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(photoLibrary.galleryAssets.count)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text("FRAMES")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(FilmyTheme.tertiary)
            }
        }
        .padding(14)
        .background(FilmyTheme.panel.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contact sheet")
        .accessibilityValue("\(photoLibrary.galleryAssets.count) frames")
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
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FilmyTheme.mint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage access to saved frames")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("Choose which frames the Roll can see")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(FilmyTheme.panel.opacity(0.76), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityHint("Choose which saved Filmy Camera frames can be viewed in the Roll")
    }

    private var galleryGrid: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .lastTextBaseline) {
                Text("RECENT FRAMES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(FilmyTheme.tertiary)
                Spacer(minLength: 8)
                Text("Newest first")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
            }

            GlassCard(padding: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(photoLibrary.galleryAssets) { asset in
                        Button {
                            selectedAsset = asset
                            isShowingPhoto = true
                        } label: {
                            GalleryThumbnail(asset: asset, photoLibrary: photoLibrary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            photoLibrary.metadata(for: asset).map {
                                "Photo in your gallery, \($0.recipe.name)"
                            } ?? "Photo in your gallery"
                        )
                    }
                }
            }
        }
    }

    private var archiveAccessNotice: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(width: 28, height: 28)
                .background(FilmyTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Showing your saved frames")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text("Enable Photos read access to refresh this archive from your library.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(FilmyTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(FilmyTheme.panel)
                    .overlay {
                        ProgressView().tint(FilmyTheme.accent)
                    }
            }
        }
        .aspectRatio(
            0.78,
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if let metadata = photoLibrary.metadata(for: asset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.recipe.name)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(metadata.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
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
        .task(id: asset.id) {
            image = await photoLibrary.image(for: asset, targetSize: CGSize(width: 360, height: 440))
        }
        .onChange(of: photoLibrary.authorizationStatus) { _, status in
            guard asset.isPhotosAsset,
                  status == .authorized || status == .limited else {
                if asset.isPhotosAsset { image = nil }
                return
            }
            image = nil
        }
    }
}

private struct RollEmptyState: View {
    let systemName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(FilmyTheme.accent.opacity(0.14))
                        Image(systemName: systemName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(FilmyTheme.accent)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "film.stack")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FilmyTheme.mint)
                    Text("Finished frames stay here with their recipe and capture time.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FilmyTheme.mint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FilmyTheme.background)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHint("Opens the relevant permission settings")
                }
            }
        }
    }
}

private struct GalleryDetailView: View {
    let asset: PhotoLibraryGalleryAsset
    @ObservedObject var photoLibrary: PhotoLibraryService

    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
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
                ProgressView().tint(FilmyTheme.accent)
            }
        }
        .task {
            image = await photoLibrary.image(for: asset, targetSize: CGSize(width: 1600, height: 2200))
        }
        .onChange(of: photoLibrary.authorizationStatus) { _, status in
            guard asset.isPhotosAsset else { return }
            if status != .authorized && status != .limited {
                image = nil
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            detailToolbar
        }
        .overlay(alignment: .bottom) {
            if let metadata = photoLibrary.metadata(for: asset) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(metadata.recipe.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Text(metadata.recipe.subtitle)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(metadata.capturedAt, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background {
                    LinearGradient(
                        colors: [.clear, FilmyTheme.background.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
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
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
