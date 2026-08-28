import PhotosUI
import SwiftUI

struct ContentView: View {
    enum Tab: Hashable {
        case camera
        case gallery
        case settings
    }

    @ObservedObject var camera: CameraService
    @ObservedObject var cameraViewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: Tab = .camera
    @State private var importedPhotoItem: PhotosPickerItem?
    @State private var importTask: Task<Void, Never>?
    @State private var isLoadingImportedPhoto = false

    private var isImportInProgress: Bool {
        isLoadingImportedPhoto || cameraViewModel.isImporting
    }

    var body: some View {
        selectedTabContent
            .overlay {
                if isImportInProgress {
                    importProgressOverlay
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    tabBar
                    importPhotoButton
                }
                .padding(.horizontal, FilmyLayout.compactHorizontalMargin)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .disabled(isImportInProgress)
            }
            .tint(FilmyTheme.accent)
            .background { FilmyPageBackground() }
            .preferredColorScheme(.dark)
            .onChange(of: importedPhotoItem) { _, item in
                guard let item else { return }
                importTask?.cancel()
                selectedTab = .camera
                isLoadingImportedPhoto = true
                importTask = Task {
                    defer {
                        isLoadingImportedPhoto = false
                        importedPhotoItem = nil
                    }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              !Task.isCancelled else {
                            if !Task.isCancelled {
                                cameraViewModel.reportImportFailure()
                            }
                            return
                        }
                        await cameraViewModel.importPhoto(data: data)
                    } catch {
                        guard !Task.isCancelled else { return }
                        cameraViewModel.reportImportFailure()
                    }
                }
            }
            .onDisappear {
                importTask?.cancel()
            }
    }

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                    .tint(FilmyTheme.accent)
                Text("Applying \(cameraViewModel.selectedRecipe.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .viewfinderChrome(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Applying \(cameraViewModel.selectedRecipe.name) to imported photo")
    }

    /// Opens the system photo picker; the chosen image is rendered with the
    /// current recipe at full resolution and lands in the same review flow as
    /// a capture.
    private var importPhotoButton: some View {
        PhotosPicker(selection: $importedPhotoItem, matching: .images) {
            HStack(spacing: 7) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 15, weight: .bold))

                Text("Import")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(FilmyTheme.background)
            .padding(.horizontal, 16)
            .frame(minWidth: 54, minHeight: 54)
            .background(FilmyTheme.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
        .disabled(isImportInProgress)
        .accessibilityLabel("Import photo")
        .accessibilityHint("Choose a photo and apply the current film recipe")
        .accessibilityIdentifier("import-photo")
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .camera:
            CameraScreen(
                camera: camera,
                viewModel: cameraViewModel,
                photoLibrary: photoLibrary,
                isCameraTabActive: selectedTab == .camera,
                onOpenGallery: { selectedTab = .gallery }
            )
        case .gallery:
            GalleryScreen(
                photoLibrary: photoLibrary,
                onBackToCamera: returnToCamera
            )
        case .settings:
            SettingsView(
                camera: camera,
                photoLibrary: photoLibrary,
                onBackToCamera: returnToCamera
            )
        }
    }

    private func returnToCamera() {
        guard selectedTab != .camera else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            selectedTab = .camera
        }
    }

    /// A compact floating pill. The active destination expands to show its
    /// name; the others stay icon-only so the camera keeps the screen.
    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton(.camera, title: "Camera", systemImage: "camera.fill")
            tabButton(.gallery, title: "Roll", systemImage: "square.grid.3x3.fill")
            tabButton(.settings, title: "Settings", systemImage: "gearshape.fill")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(FilmyTheme.panel.opacity(0.88), in: Capsule())
        .overlay {
            Capsule().strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
    }

    private func tabButton(_ tab: Tab, title: String, systemImage: String) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            guard selectedTab != tab else { return }
            HapticFeedback.play(.selection)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))

                if isSelected {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? FilmyTheme.background : FilmyTheme.secondary)
            .padding(.horizontal, isSelected ? 18 : 15)
            .frame(minWidth: 54, minHeight: 46)
            .background(isSelected ? FilmyTheme.accent : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

private extension ContentView.Tab {
    var accessibilityIdentifier: String {
        switch self {
        case .camera: "camera-tab"
        case .gallery: "roll-tab"
        case .settings: "settings-tab"
        }
    }
}
