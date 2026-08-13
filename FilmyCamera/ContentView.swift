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

    @State private var selectedTab: Tab = .camera

    var body: some View {
        selectedTabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                tabBar
            }
            .tint(FilmyTheme.accent)
            .background(FilmyTheme.background)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .camera:
            CameraScreen(
                camera: camera,
                viewModel: cameraViewModel,
                photoLibrary: photoLibrary,
                isCameraTabActive: true,
                onOpenGallery: { selectedTab = .gallery }
            )
        case .gallery:
            GalleryScreen(photoLibrary: photoLibrary)
        case .settings:
            SettingsView(camera: camera, photoLibrary: photoLibrary)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.camera, title: "Camera", systemImage: "camera.fill")
            tabButton(.gallery, title: "Roll", systemImage: "square.grid.2x2.fill")
            tabButton(.settings, title: "Settings", systemImage: "slider.horizontal.3")
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .background(FilmyTheme.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FilmyTheme.line)
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: Tab, title: String, systemImage: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(FilmyTheme.metadataFont)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? FilmyTheme.accent : FilmyTheme.secondary)
        .accessibilityLabel(title)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : [.isButton])
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
