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
        view.update(recipe: recipe, quality: quality)
        cameraService.onFrame = { [weak coordinator] image in
            coordinator?.receive(image)
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
        uiView.update(recipe: recipe, quality: quality)

        // SwiftUI can recreate the callback after another view has used the
        // service. Reinstalling this tiny forwarding closure keeps the preview
        // attached to the current representable instance.
        cameraService.onFrame = { [weak coordinator] image in
            coordinator?.receive(image)
        }
    }

    public static func dismantleUIView(
        _ uiView: FilteredCameraPreviewView,
        coordinator: Coordinator
    ) {
        coordinator.service?.onFrame = nil
        coordinator.previewView = nil
        uiView.clearImage()
    }

    public final class Coordinator: @unchecked Sendable {
        fileprivate weak var previewView: FilteredCameraPreviewView?
        fileprivate weak var service: CameraService?
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

        fileprivate func receive(_ image: CIImage) {
            DispatchQueue.main.async { [weak self] in
                self?.previewView?.display(image: image)
            }
        }
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

    public override init(frame: CGRect, device: MTLDevice?) {
        let selectedDevice = device ?? MTLCreateSystemDefaultDevice()
        if let selectedDevice {
            ciContext = CIContext(
                mtlDevice: selectedDevice,
                options: [.cacheIntermediates: false]
            )
            commandQueue = selectedDevice.makeCommandQueue()
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: true])
            commandQueue = nil
        }

        super.init(frame: frame, device: selectedDevice)
        configureView()
    }

    public required init(coder: NSCoder) {
        let selectedDevice = MTLCreateSystemDefaultDevice()
        if let selectedDevice {
            ciContext = CIContext(
                mtlDevice: selectedDevice,
                options: [.cacheIntermediates: false]
            )
            commandQueue = selectedDevice.makeCommandQueue()
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: true])
            commandQueue = nil
        }

        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        delegate = self
        device = device ?? MTLCreateSystemDefaultDevice()
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 30
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        isOpaque = true
        backgroundColor = .black
        contentMode = .scaleAspectFill
    }

    func update(recipe: FilmRecipe, quality: FilmRenderer.Quality) {
        self.recipe = recipe
        self.quality = quality
        setNeedsDisplay()
    }

    func display(image: CIImage) {
        latestImage = image
        setNeedsDisplay()
    }

    func clearImage() {
        latestImage = nil
        setNeedsDisplay()
    }

    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let image = latestImage,
              let sRGBColorSpace,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return
        }

        let targetRect = CGRect(origin: .zero, size: drawableSize)
        let filtered = FilmRenderer.render(image, recipe: recipe, quality: quality)
        let fitted = aspectFill(filtered, in: targetRect)
        ciContext.render(
            fitted,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: targetRect,
            colorSpace: sRGBColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {
        // The current drawable is sized by MTKView; the next frame naturally
        // recomputes the aspect-fill transform for the new bounds.
    }

    private func aspectFill(_ image: CIImage, in target: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0,
              extent.height > 0,
              target.width > 0,
              target.height > 0 else {
            return image
        }

        let normalized = image.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        let scale = max(target.width / extent.width, target.height / extent.height)
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let offset = CGAffineTransform(
            translationX: target.midX - scaledExtent.midX,
            y: target.midY - scaledExtent.midY
        )
        return scaled.transformed(by: offset).cropped(to: target)
    }
}
