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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .camera
    @State private var isShowingImporter = false
    @State private var importedPhotoItem: PhotosPickerItem?
    @State private var importTask: Task<Void, Never>?
    @State private var isLoadingImportedPhoto = false

    private var isImportInProgress: Bool {
        isLoadingImportedPhoto || cameraViewModel.isImporting
    }

    /// Navigation and import share the capture/review busy policy so an image
    /// cannot be replaced while it is still being captured, reviewed, or saved.
    private var isCameraBusy: Bool {
        isImportInProgress
            || cameraViewModel.isCapturing
            || cameraViewModel.isSaving
            || cameraViewModel.reviewImage != nil
    }

    var body: some View {
        selectedTabContent
            // The camera screen keeps the session warm across tab switches.
            // Leaving the foreground must still release it at once, even when
            // the Roll or Settings is showing and the camera screen is gone.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    camera.stop()
                }
            }
            .overlay {
                if isImportInProgress {
                    importProgressOverlay
                }
            }
            .photosPicker(isPresented: $isShowingImporter, selection: $importedPhotoItem, matching: .images)
            .tint(FilmyTheme.accent)
            .background {
                // The camera sits on a black body; the Roll and Settings keep
                // the neutral page surface.
                if selectedTab == .camera {
                    FilmyTheme.viewfinderBand.ignoresSafeArea()
                } else {
                    FilmyPageBackground()
                }
            }
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
                        await cameraViewModel.importPhoto(data: data, camera: camera)
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

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .camera:
            CameraScreen(
                camera: camera,
                viewModel: cameraViewModel,
                photoLibrary: photoLibrary,
                isCameraTabActive: selectedTab == .camera,
                onOpenGallery: { open(.gallery) },
                onOpenSettings: { open(.settings) },
                onImportPhoto: {
                    guard !isCameraBusy else { return }
                    isShowingImporter = true
                },
                isImportInProgress: isImportInProgress
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

    private func open(_ destination: Tab) {
        guard !isCameraBusy, selectedTab != destination else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            selectedTab = destination
        }
    }
}
