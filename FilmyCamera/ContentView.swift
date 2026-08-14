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
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 7)
            }
            .tint(FilmyTheme.accent)
            .background(FilmyPageBackground())
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

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(.camera, title: "Camera", systemImage: "camera.fill")
            tabButton(.gallery, title: "Roll", systemImage: "square.grid.2x2.fill")
            tabButton(.settings, title: "Settings", systemImage: "slider.horizontal.3")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(FilmyTheme.navBarGradient, in: Capsule())
        .overlay { Capsule().stroke(FilmyTheme.lineStrong, lineWidth: 1) }
        .shadow(color: .black.opacity(0.38), radius: 25, y: 12)
    }

    private func tabButton(_ tab: Tab, title: String, systemImage: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selectedTab == tab ? FilmyTheme.background : FilmyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                selectedTab == tab ? FilmyTheme.accent : Color.white.opacity(0.02),
                in: Capsule()
            )
            .overlay {
                if selectedTab != tab {
                    Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
