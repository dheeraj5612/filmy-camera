import Combine
import CoreImage
import CoreGraphics
import SwiftUI

/// A small, upright snapshot of what the camera currently sees, used so that
/// every recipe swatch can show the actual scene rendered through that recipe
/// instead of a synthetic test pattern. `version` changes whenever the
/// snapshot is refreshed so views can re-render only when needed.
public struct RecipePreviewScene: Equatable, @unchecked Sendable {
    public let image: CIImage
    public let version: Int

    public static func == (lhs: RecipePreviewScene, rhs: RecipePreviewScene) -> Bool {
        lhs.version == rhs.version
    }
}

private struct RecipePreviewSceneKey: EnvironmentKey {
    static let defaultValue: RecipePreviewScene? = nil
}

extension EnvironmentValues {
    /// The live scene recipe swatches should render themselves over. Nil
    /// falls back to the renderer's built-in sample scene.
    var recipePreviewScene: RecipePreviewScene? {
        get { self[RecipePreviewSceneKey.self] }
        set { self[RecipePreviewSceneKey.self] = newValue }
    }
}

/// Samples the live viewfinder at a gentle cadence and publishes a reduced
/// snapshot for recipe previews. Rendering happens off the main thread and a
/// snapshot is only taken when the previous one has finished, so the rail can
/// never queue GPU work behind the viewfinder.
@MainActor
final class LiveRecipePreviewStore: ObservableObject {
    static let snapshotSize = CGSize(width: 264, height: 176)
    static let snapshotInterval: TimeInterval = 2.0

    @Published private(set) var scene: RecipePreviewScene?

    private weak var camera: CameraService?
    private var frameHandlerID: UUID?
    private var lastSnapshotTime: TimeInterval = 0
    private var isRendering = false
    private var version = 0
    /// Bumped by `detach()` and `clear()`; a render that started under an
    /// older generation discards its result instead of publishing it.
    private var generation = 0

    func attach(to camera: CameraService) {
        guard frameHandlerID == nil || self.camera !== camera else { return }
        detach()
        self.camera = camera
        frameHandlerID = camera.installFrameHandler { [weak self] image in
            guard let self else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { self.receive(image) }
            } else {
                let box = FrameBox(image)
                Task { @MainActor in self.receive(box.image) }
            }
        }
    }

    func detach() {
        if let frameHandlerID, let camera {
            camera.removeFrameHandler(frameHandlerID)
        }
        frameHandlerID = nil
        camera = nil
        invalidatePendingRenders()
    }

    /// Clears the live scene so swatches fall back to the sample scene, e.g.
    /// while a review sheet is up and the session is stopped. A render still
    /// in flight is discarded so it cannot republish the old scene.
    func clear() {
        scene = nil
        invalidatePendingRenders()
    }

    private func invalidatePendingRenders() {
        generation &+= 1
        isRendering = false
    }

    private func receive(_ image: CIImage) {
        let now = CACurrentMediaTime()
        guard !isRendering, now - lastSnapshotTime >= Self.snapshotInterval else { return }
        isRendering = true
        lastSnapshotTime = now

        let box = FrameBox(image)
        let size = Self.snapshotSize
        let startedGeneration = generation
        Task.detached(priority: .utility) { [weak self] in
            let target = CGRect(origin: .zero, size: size)
            let framed = CameraFrameLayout.aspectFill(box.image, in: target)
            let rendered = FilmRenderer.outputCGImage(framed, from: target)
            await MainActor.run { [weak self] in
                guard let self, self.generation == startedGeneration else { return }
                self.isRendering = false
                guard let rendered else { return }
                self.version += 1
                self.scene = RecipePreviewScene(
                    image: CIImage(cgImage: rendered),
                    version: self.version
                )
            }
        }
    }
}

/// CIImage is immutable here but not declared Sendable on every supported
/// toolchain; box it for the hop between the capture callback and rendering.
private final class FrameBox: @unchecked Sendable {
    let image: CIImage

    init(_ image: CIImage) {
        self.image = image
    }
}
