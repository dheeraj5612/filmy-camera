import Photos
import SwiftUI
import UIKit

struct GalleryScreen: View {
    @ObservedObject var photoLibrary: PhotoLibraryService

    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingPhoto = false
    @State private var selectedAsset: PHAsset?

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
                        trailing: photoLibrary.assets.isEmpty ? nil : "\(photoLibrary.assets.count) recent"
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
            _ = await photoLibrary.requestAccessIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            photoLibrary.refresh()
            guard photoLibrary.authorizationStatus == .authorized
                    || photoLibrary.authorizationStatus == .limited else {
                selectedAsset = nil
                isShowingPhoto = false
                return
            }

            if let selectedAsset,
               !photoLibrary.assets.contains(where: { $0.localIdentifier == selectedAsset.localIdentifier }) {
                self.selectedAsset = nil
                isShowingPhoto = false
            }
        }
        .onChange(of: photoLibrary.authorizationStatus) { _, status in
            guard status == .authorized || status == .limited else {
                selectedAsset = nil
                isShowingPhoto = false
                return
            }

            if let selectedAsset,
               !photoLibrary.assets.contains(where: { $0.localIdentifier == selectedAsset.localIdentifier }) {
                self.selectedAsset = nil
                isShowingPhoto = false
            }
        }
        .sheet(isPresented: $isShowingPhoto) {
            if let selectedAsset {
                GalleryDetailView(asset: selectedAsset, photoLibrary: photoLibrary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        switch photoLibrary.authorizationStatus {
        case .authorized, .limited:
            if photoLibrary.assets.isEmpty {
                EmptyStateCard(
                    systemName: "photo.on.rectangle.angled",
                    title: "Your frames will live here",
                    message: "Capture a moment with a recipe and it will appear in this quiet little roll."
                )
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(photoLibrary.assets, id: \.localIdentifier) { asset in
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
        case .notDetermined:
            EmptyStateCard(
                systemName: "photo.badge.plus",
                title: "Give your roll a home",
                message: "Allow photo access to show the frames you have made with Filmy Camera."
            )
        case .denied, .restricted:
            EmptyStateCard(
                systemName: "lock.slash",
                title: "Photo access is off",
                message: "Enable Photos access in Settings to see your saved frames.",
                actionTitle: "Open Settings",
                action: openSystemSettings
            )
        @unknown default:
            EmptyStateCard(
                systemName: "photo",
                title: "Gallery unavailable",
                message: "Filmy Camera could not read the photo library right now."
            )
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct GalleryThumbnail: View {
    let asset: PHAsset
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
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.image(for: asset, targetSize: CGSize(width: 360, height: 440))
        }
        .onChange(of: photoLibrary.authorizationStatus) { _, status in
            guard status == .authorized || status == .limited else {
                image = nil
                return
            }
            image = nil
        }
    }
}

private struct GalleryDetailView: View {
    let asset: PHAsset
    @ObservedObject var photoLibrary: PhotoLibraryService

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isShowingShareSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
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
        .sheet(isPresented: $isShowingShareSheet) {
            if let image {
                ShareSheet(items: [image])
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
                isShowingShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .background(FilmyTheme.panel, in: Circle())
            }
            .accessibilityLabel("Share frame")
            .disabled(image == nil || isDeleting)

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
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
