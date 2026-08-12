import SwiftUI

@main
struct FilmyCameraApp: App {
    @StateObject private var camera = CameraService()
    @StateObject private var cameraViewModel = CameraViewModel()
    @StateObject private var photoLibrary = PhotoLibraryService()

    var body: some Scene {
        WindowGroup {
            ContentView(
                camera: camera,
                cameraViewModel: cameraViewModel,
                photoLibrary: photoLibrary
            )
        }
    }
}
