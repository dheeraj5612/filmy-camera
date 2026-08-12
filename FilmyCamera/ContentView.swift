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
        TabView(selection: $selectedTab) {
            CameraScreen(
                camera: camera,
                viewModel: cameraViewModel,
                photoLibrary: photoLibrary,
                onOpenGallery: { selectedTab = .gallery }
            )
            .tabItem {
                Label("Camera", systemImage: "camera.fill")
            }
            .tag(Tab.camera)

            GalleryScreen(photoLibrary: photoLibrary)
                .tabItem {
                    Label("Gallery", systemImage: "square.grid.2x2.fill")
                }
                .tag(Tab.gallery)

            SettingsView(camera: camera, photoLibrary: photoLibrary)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.settings)
        }
        .tint(FilmyTheme.accent)
        .background(FilmyTheme.background)
        .preferredColorScheme(.dark)
        .toolbarBackground(FilmyTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
