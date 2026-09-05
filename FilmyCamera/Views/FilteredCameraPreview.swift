import CoreGraphics
import CoreImage
import Metal
import MetalKit
import SwiftUI
import UIKit

/// A SwiftUI bridge for the GPU-backed live camera preview.
public struct FilteredCameraPreview: UIViewRepresentable {
    public typealias UIViewType = FilteredCameraPreviewView

    @ObservedObject private var cameraService: CameraService
    private let recipe: FilmRecipe
    private let quality: FilmRenderer.Quality

    public init(
        cameraService: CameraService,
        recipe: FilmRecipe,
        quality: FilmRenderer.Quality = .preview
    ) {
        _cameraService = ObservedObject(wrappedValue: cameraService)
        self.recipe = recipe
        self.quality = quality
    }

    public init(
        service: CameraService,
        recipe: FilmRecipe,
        quality: FilmRenderer.Quality = .preview
    ) {
        self.init(cameraService: service, recipe: recipe, quality: quality)
    }

    public init(
        camera: CameraService,
        recipe: FilmRecipe,
        quality: FilmRenderer.Quality = .preview
    ) {
        self.init(cameraService: camera, recipe: recipe, quality: quality)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(service: cameraService, recipe: recipe, quality: quality)
    }

    public func makeUIView(context: Context) -> FilteredCameraPreviewView {
        let view = FilteredCameraPreviewView(frame: .zero)
        let coordinator = context.coordinator
        coordinator.previewView = view
        coordinator.previewLayerID = cameraService.installPreviewLayer(view.layer)
        view.update(
            recipe: recipe,
            quality: quality,
            grainSeed: cameraService.previewGrainSeed
        )
        coordinator.installFrameHandlerIfNeeded()
        view.accessibilityLabel = "Live camera preview"
        view.onDrawableSizeChange = { [weak cameraService] size in
            cameraService?.updatePreviewDrawableSize(size)
        }
        return view
    }

    public func updateUIView(
        _ uiView: FilteredCameraPreviewView,
        context: Context
    ) {
        let coordinator = context.coordinator
        coordinator.previewView = uiView
        coordinator.recipe = recipe
        coordinator.quality = quality
        uiView.update(
            recipe: recipe,
            quality: quality,
            grainSeed: cameraService.previewGrainSeed
        )

        // The coordinator owns one callback for the lifetime of the UIKit
        // view. Reinstalling it on every SwiftUI update can multiply frame
        // delivery while a slider or recipe selection is changing.
        coordinator.installFrameHandlerIfNeeded()
    }

    public static func dismantleUIView(
        _ uiView: FilteredCameraPreviewView,
        coordinator: Coordinator
    ) {
        if let frameHandlerID = coordinator.frameHandlerID {
            coordinator.service?.removeFrameHandler(frameHandlerID)
        }
        if let previewLayerID = coordinator.previewLayerID {
            coordinator.service?.removePreviewLayer(previewLayerID)
        }
        coordinator.frameHandlerID = nil
        coordinator.previewLayerID = nil
        coordinator.previewView = nil
        uiView.clearImage()
    }

    public final class Coordinator: @unchecked Sendable {
        fileprivate weak var previewView: FilteredCameraPreviewView?
        fileprivate weak var service: CameraService?
        fileprivate var frameHandlerID: UUID?
        fileprivate var previewLayerID: UUID?
        fileprivate var recipe: FilmRecipe
        fileprivate var quality: FilmRenderer.Quality

        fileprivate init(
            service: CameraService,
            recipe: FilmRecipe,
            quality: FilmRenderer.Quality
        ) {
            self.service = service
            self.recipe = recipe
            self.quality = quality
        }

        fileprivate func installFrameHandlerIfNeeded() {
            guard frameHandlerID == nil, let service else { return }
            frameHandlerID = service.installFrameHandler { [weak self] image in
                self?.receive(image)
            }
        }

        fileprivate func receive(_ image: CIImage) {
            // CameraService documents onFrame as main-queue delivery. Avoid
            // adding another async hop to every captured frame.
            let imageBox = CIImageBox(image)
            if Thread.isMainThread {
                MainActor.assumeIsolated { [weak self] in
                    self?.previewView?.display(image: imageBox.image)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.previewView?.display(image: imageBox.image)
                }
            }
        }
    }
}

/// CIImage is immutable for this use, but its SDK declaration is not Sendable
/// on older Swift 6 toolchains. Boxing is limited to the exceptional off-main
/// fallback so the normal camera path stays synchronous.
private final class CIImageBox: @unchecked Sendable {
    let image: CIImage

    init(_ image: CIImage) {
        self.image = image
    }
}

/// MTKView that renders the filtered CIImage into the current drawable.
public final class FilteredCameraPreviewView: MTKView, MTKViewDelegate {
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue?
    private let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    private var latestImage: CIImage?
    private var recipe = FilmRecipe.builtIns[0]
    private var quality: FilmRenderer.Quality = .preview
    private var grainSeed = FilmRenderer.canonicalGrainSeed
    /// Monotonically identifies the newest frame, recipe, or drawable shape.
    /// If one of these changes while Metal is busy, completion schedules
    /// exactly one redraw for the newest state instead of queuing GPU work.
    private var contentRevision: UInt64 = 0
    private var isRenderInFlight = false

    public override init(frame: CGRect, device: MTLDevice?) {
        let selectedDevice = device ?? FilmRenderer.metalDevice ?? MTLCreateSystemDefaultDevice()
        let resources = Self.makeRenderResources(for: selectedDevice)
        ciContext = resources.context
        commandQueue = resources.commandQueue

        super.init(frame: frame, device: selectedDevice)
        configureView()
    }

    public required init(coder: NSCoder) {
        let selectedDevice = FilmRenderer.metalDevice ?? MTLCreateSystemDefaultDevice()
        let resources = Self.makeRenderResources(for: selectedDevice)
        ciContext = resources.context
        commandQueue = resources.commandQueue

        super.init(coder: coder)
        configureView()
    }

    private static func makeRenderResources(
        for device: MTLDevice?
    ) -> (context: CIContext, commandQueue: MTLCommandQueue?) {
        guard let device else {
            var options: [CIContextOption: Any] = [.useSoftwareRenderer: true]
            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
                options[.workingColorSpace] = colorSpace
                options[.outputColorSpace] = colorSpace
            }
            return (CIContext(options: options), nil)
        }

        let context: CIContext
        if let sharedDevice = FilmRenderer.metalDevice,
           device === sharedDevice {
            context = FilmRenderer.sharedContext
        } else {
            var options: [CIContextOption: Any] = [.cacheIntermediates: false]
            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
                options[.workingColorSpace] = colorSpace
                options[.outputColorSpace] = colorSpace
            }
            context = CIContext(
                mtlDevice: device,
                options: options
            )
        }

        return (context, device.makeCommandQueue())
    }

    /// The viewfinder is rendered at a bounded pixel count and scaled up by
    /// the display. Every filter pass costs in proportion to output pixels,
    /// and a full Retina drawable (3.7 MP on an 11-inch iPad) put a G7 X frame
    /// at ~40 ms on an A12Z; at 1.3 MP the same frame renders in ~14 ms.
    static let previewPixelBudget: CGFloat = 1_300_000

    static func drawableScale(for bounds: CGSize, screenScale: CGFloat) -> CGFloat {
        let points = bounds.width * bounds.height
        guard points > 0, screenScale > 0 else { return max(screenScale, 1) }
        let budgetScale = (previewPixelBudget / points).squareRoot()
        return min(max(screenScale, 1), max(budgetScale, 1))
    }

    private func configureView() {
        delegate = self
        device = device ?? FilmRenderer.metalDevice ?? MTLCreateSystemDefaultDevice()
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 30
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        isOpaque = true
        backgroundColor = .black
        contentMode = .scaleAspectFill
        autoResizeDrawable = false
    }

    /// Reports the drawable size the view really renders into, so captures
    /// can phase their grain against the same pixel grid as the preview.
    var onDrawableSizeChange: ((CGSize) -> Void)?

    public override func layoutSubviews() {
        super.layoutSubviews()
        let screenScale = window?.screen.scale ?? traitCollection.displayScale
        let scale = Self.drawableScale(for: bounds.size, screenScale: screenScale)
        let target = CGSize(
            width: (bounds.width * scale).rounded(),
            height: (bounds.height * scale).rounded()
        )
        if target != drawableSize, target.width > 0, target.height > 0 {
            drawableSize = target
            onDrawableSizeChange?(target)
        }
    }

    func update(
        recipe: FilmRecipe,
        quality: FilmRenderer.Quality,
        grainSeed: UInt32
    ) {
        guard self.recipe != recipe || self.quality != quality || self.grainSeed != grainSeed else { return }
        self.recipe = recipe
        self.quality = quality
        self.grainSeed = grainSeed
        requestDisplay()
    }

    func display(image: CIImage) {
        latestImage = image
        requestDisplay()
    }

    func clearImage() {
        guard latestImage != nil else { return }
        latestImage = nil
        contentRevision &+= 1
    }

    public func draw(in view: MTKView) {
        guard !isRenderInFlight,
              let drawable = currentDrawable,
              let image = latestImage,
              let sRGBColorSpace,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return
        }

        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            return
        }
        let renderedRevision = contentRevision
        isRenderInFlight = true

        let targetRect = CGRect(origin: .zero, size: drawableSize)
        // Frame before rendering so vignette, halation, and grain use the
        // same visible composition as the still path. Rendering the resized
        // frame also keeps preview work proportional to the drawable rather
        // than to the camera sensor's full video dimensions.
        let framed = CameraFrameLayout.aspectFill(image, in: targetRect)
        let filtered = FilmRenderer.render(
            framed,
            recipe: recipe,
            quality: quality,
            grainSeed: grainSeed
        )
            .cropped(to: targetRect)
        ciContext.render(
            filtered,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetRect,
            colorSpace: sRGBColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.finishRender(revision: renderedRevision)
            }
        }
        commandBuffer.commit()
    }

    public func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {
        // Keep the last frame visible and recompute its aspect-fill transform
        // immediately after rotation or another drawable-size change.
        if latestImage != nil {
            requestDisplay()
        }
    }

    private func requestDisplay() {
        contentRevision &+= 1
        guard latestImage != nil, !isRenderInFlight else { return }
        setNeedsDisplay()
    }

    private func finishRender(revision: UInt64) {
        isRenderInFlight = false
        guard latestImage != nil, contentRevision != revision else { return }
        setNeedsDisplay()
    }

}
