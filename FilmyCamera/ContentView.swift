import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Identity, not task completion order, owns the import UI. A provider may
/// finish after cancellation, including after the user starts another import.
struct PhotoImportSession {
    enum Phase: Equatable {
        case idle
        case loading
        case applying
        case cancelling
    }

    private(set) var phase: Phase = .idle
    private var operationID: UUID?

    var isBusy: Bool { phase != .idle }

    mutating func begin() -> UUID? {
        guard !isBusy else { return nil }
        let id = UUID()
        operationID = id
        phase = .loading
        return id
    }

    func isCurrent(_ id: UUID) -> Bool { operationID == id }

    mutating func beginApplying(_ id: UUID) -> Bool {
        guard isCurrent(id), phase == .loading else { return false }
        phase = .applying
        return true
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        operationID = nil
        phase = .idle
        return true
    }

    mutating func cancel() {
        switch phase {
        case .loading:
            // Downloads can be abandoned immediately. Late results must not
            // render or clear the state of a newer request.
            operationID = nil
            phase = .idle
        case .applying:
            // Core Image work may not stop immediately. Keep the controls
            // locked until the view model has drained that render.
            phase = .cancelling
        case .idle, .cancelling:
            break
        }
    }
}

enum PhotoImportFailure: LocalizedError {
    case unavailable
    case emptyFile
    case tooLarge

    /// Transferable can wrap a provider error. Preserve our actionable size
    /// message without exposing provider paths or opaque system diagnostics.
    static func message(for error: Error) -> String {
        var current = error
        for _ in 0..<5 {
            if let failure = current as? PhotoImportFailure, let message = failure.errorDescription { return message }
            guard let underlying = (current as NSError).userInfo[NSUnderlyingErrorKey] as? Error else { break }
            current = underlying
        }
        return PhotoImportFailure.unavailable.errorDescription ?? "Choose another photo and try again."
    }

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This photo could not be opened. For an iCloud photo, check your connection and try again, or choose another photo."
        case .emptyFile:
            return "This file has no photo data. Choose another photo."
        case .tooLarge:
            return "This photo is larger than the 100 MB import limit. Export a smaller JPEG or HEIC copy, then try again."
        }
    }
}

/// Bound encoded input before allocating it, separately from the renderer's
/// decoded-pixel budget. Recheck while reading in case the file changes size.
enum PhotoImportPolicy {
    static let maximumBytes = 100_000_000

    static func read(from url: URL, byteLimit: Int = maximumBytes) throws -> Data {
        try Task.checkCancellation()
        guard byteLimit > 0 else { throw PhotoImportFailure.tooLarge }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize else {
            throw PhotoImportFailure.unavailable
        }
        guard fileSize > 0 else { throw PhotoImportFailure.emptyFile }
        guard fileSize <= byteLimit else { throw PhotoImportFailure.tooLarge }
        guard let stream = InputStream(url: url) else { throw PhotoImportFailure.unavailable }
        stream.open()
        defer { stream.close() }

        let bufferSize = min(65_536, byteLimit)
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var data = Data()
        data.reserveCapacity(fileSize)
        while true {
            try Task.checkCancellation()
            let count = stream.read(&buffer, maxLength: bufferSize)
            guard count >= 0 else { throw stream.streamError ?? PhotoImportFailure.unavailable }
            if count == 0 { break }
            guard count <= byteLimit - data.count else { throw PhotoImportFailure.tooLarge }
            data.append(buffer, count: count)
        }
        guard !data.isEmpty else { throw PhotoImportFailure.emptyFile }
        return data
    }
}

private struct ImportedPhoto: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            // Read within the provider file's lifetime, but not on the UI
            // actor. Do not retain its temporary URL after this closure.
            let url = received.file
            let readTask = Task.detached(priority: .userInitiated) {
                try PhotoImportPolicy.read(from: url)
            }
            return try await withTaskCancellationHandler {
                ImportedPhoto(data: try await readTask.value)
            } onCancel: {
                readTask.cancel()
            }
        }
    }
}

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
    @State private var importSession = PhotoImportSession()
    @State private var importErrorMessage: String?

    private var isImportInProgress: Bool {
        importSession.isBusy || cameraViewModel.isImporting
    }

    private var isCameraBusy: Bool {
        isShowingImporter || isImportInProgress
            || cameraViewModel.isCapturing
            || cameraViewModel.isSaving
            || cameraViewModel.reviewImage != nil
    }

    var body: some View {
        selectedTabContent
            .allowsHitTesting(!isImportInProgress)
            .accessibilityHidden(isImportInProgress)
            // Release hardware even when the camera screen is not mounted.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { camera.stop() }
            }
            .overlay {
                if isImportInProgress { importProgressOverlay }
            }
            .photosPicker(
                isPresented: $isShowingImporter,
                selection: $importedPhotoItem,
                matching: .images,
                preferredItemEncoding: .current
            )
            .alert("Could not import photo", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("Choose Another Photo") { isShowingImporter = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "Choose another photo and try again.")
            }
            .tint(FilmyTheme.accent)
            .background {
                if selectedTab == .camera {
                    FilmyTheme.viewfinderBand.ignoresSafeArea()
                } else {
                    FilmyPageBackground()
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: importedPhotoItem) { _, item in
                guard let item else { return }
                // Clear this selection immediately, not from a task's defer.
                // A cancelled provider must not clear a newer selection.
                importedPhotoItem = nil
                startImport(item)
            }
            .onDisappear { cancelImport() }
    }

    private func startImport(_ item: PhotosPickerItem) {
        guard !cameraViewModel.isCapturing, !cameraViewModel.isSaving,
              !cameraViewModel.isImporting, cameraViewModel.reviewImage == nil,
              let id = importSession.begin() else { return }
        selectedTab = .camera
        importErrorMessage = nil
        importTask = Task {
            defer {
                if importSession.finish(id) { importTask = nil }
            }
            do {
                guard let photo = try await item.loadTransferable(type: ImportedPhoto.self) else {
                    throw PhotoImportFailure.unavailable
                }
                try Task.checkCancellation()
                guard importSession.beginApplying(id) else { return }
                await cameraViewModel.importPhoto(data: photo.data, camera: camera)
            } catch {
                guard !Task.isCancelled, importSession.isCurrent(id) else { return }
                importErrorMessage = PhotoImportFailure.message(for: error)
            }
        }
    }

    private func cancelImport() {
        importTask?.cancel()
        importSession.cancel()
        if !importSession.isBusy { importTask = nil }
    }

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(FilmyTheme.accent)
                Text(importTitle)
                    .font(.headline)
                    .foregroundStyle(FilmyTheme.primary)
                    .accessibilityIdentifier("photo-import-status")
                Text(importDetail)
                    .font(.subheadline)
                    .foregroundStyle(FilmyTheme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancel import", action: cancelImport)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
                    .disabled(importSession.phase == .cancelling)
                    .accessibilityIdentifier("photo-import-cancel")
            }
            .padding(24)
            .frame(maxWidth: 360)
            .viewfinderChrome(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .accessibilityIdentifier("photo-import-progress")
    }

    private var importTitle: String {
        switch importSession.phase {
        case .loading: return "Opening your photo"
        case .cancelling: return "Cancelling import"
        case .idle, .applying: return "Applying \(cameraViewModel.selectedRecipe.name)"
        }
    }

    private var importDetail: String {
        switch importSession.phase {
        case .loading: return "Photos may need to download the original from iCloud. You can cancel at any time."
        case .cancelling: return "Finishing the current image operation safely. Nothing will be saved."
        case .idle, .applying: return "Your original stays unchanged. Review the look before saving a new copy."
        }
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
                isImportInProgress: isImportInProgress || isShowingImporter
            )
        case .gallery:
            GalleryScreen(photoLibrary: photoLibrary, onBackToCamera: returnToCamera)
        case .settings:
            SettingsView(camera: camera, photoLibrary: photoLibrary, onBackToCamera: returnToCamera)
        }
    }

    private func returnToCamera() {
        guard selectedTab != .camera else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) { selectedTab = .camera }
    }

    private func open(_ destination: Tab) {
        guard !isCameraBusy, selectedTab != destination else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) { selectedTab = destination }
    }
}
