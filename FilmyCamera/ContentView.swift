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

    var body: some View {
        selectedTabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                tabBar
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
            }
            .tint(FilmyTheme.accent)
            .background { FilmyPageBackground() }
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
                isCameraTabActive: selectedTab == .camera,
                onOpenGallery: { selectedTab = .gallery }
            )
        case .gallery:
            GalleryScreen(photoLibrary: photoLibrary)
        case .settings:
            SettingsView(camera: camera, photoLibrary: photoLibrary)
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
