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
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeading(
                        eyebrow: "Your roll",
                        title: "Roll",
                        trailing: photoLibrary.galleryAssets.isEmpty ? nil : "\(photoLibrary.galleryAssets.count) recent"
                    )

                    galleryContent
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
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
            // access. Filmy Camera can display its own locally cached frames;
            // browsing other Photos is an explicit user choice below.
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
                    EmptyStateCard(
                        systemName: "photo.badge.plus",
                        title: "Give your roll a home",
                        message: "Allow photo access to show the frames you have made with Filmy Camera.",
                        actionTitle: "Browse Photos",
                        action: requestReadAccess
                    )
                } else {
                    EmptyStateCard(
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
                    EmptyStateCard(
                        systemName: "photo.on.rectangle.angled",
                        title: "Your selected roll is empty",
                        message: "Filmy Camera can only show the photos you selected for it."
                    )
                } else {
                    galleryGrid
                }
                manageLimitedAccessButton
            }
        case .denied, .restricted:
            if photoLibrary.galleryAssets.isEmpty {
                EmptyStateCard(
                    systemName: "lock.slash",
                    title: "Photo access is off",
                    message: "Enable Photos access in Settings to see your saved frames.",
                    actionTitle: "Open Settings",
                    action: openSystemSettings
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Showing frames saved by Filmy Camera. Enable Photos read access to browse other library assets.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    galleryGrid
                }
            }
        @unknown default:
            EmptyStateCard(
                systemName: "photo",
                title: "Gallery unavailable",
                message: "Filmy Camera could not read the photo library right now."
            )
        }
    }

    private var manageLimitedAccessButton: some View {
        Button {
            photoLibrary.presentLimitedLibraryPicker()
        } label: {
            Label("Manage selected photos", systemImage: "checkmark.circle")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(FilmyTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHint("Choose which photos Filmy Camera can view")
    }

    private var galleryGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
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
            CGFloat(max(asset.pixelWidth, 1)) / CGFloat(max(asset.pixelHeight, 1)),
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if let metadata = photoLibrary.metadata(for: asset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.recipe.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(metadata.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.72)],
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

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
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
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
