import SwiftUI

struct FujiViewfinderOverlay: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var camera: CameraService
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = controller.ghostImage, controller.isComposing {
                    // Layer guides are view-only; the processor composites the
                    // original images, never a screenshot of this overlay.
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width / (controller.settings.viewfinder == .electronic ? 1 : controller.settings.digitalCrop),
                               height: proxy.size.height / (controller.settings.viewfinder == .electronic ? 1 : controller.settings.digitalCrop))
                        .clipped().opacity(0.32)
                }
                if controller.settings.viewfinder != .electronic {
                    let factor = CGFloat(controller.settings.digitalCrop)
                    Rectangle().strokeBorder(.white, lineWidth: 1.5)
                        .frame(width: max(proxy.size.width / factor - 8, 1), height: max(proxy.size.height / factor - 8, 1))
                        .shadow(color: .black.opacity(0.6), radius: 1)
                    VStack {
                        HStack {
                            Text("\(controller.settings.viewfinder.title) · DIGITAL")
                                .font(.caption2.weight(.semibold).monospaced()).padding(8).background(.black.opacity(0.5), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }.padding(10)
                }
                if let image = controller.focusImage, controller.settings.focusAssist != .off, !controller.isBusy {
                    VStack(spacing: 4) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 112, height: 112)
                            .clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 1))
                        Text("RELATIVE CONTRAST \(Int(controller.focusContrast * 100))%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(4).background(.black.opacity(0.6), in: Capsule())
                    }
                    .accessibilityLabel("\(controller.settings.focusAssist.title), contrast-based visual aid")
                }
                if let image = controller.hybridImage, controller.settings.viewfinder == .hybrid {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: min(proxy.size.width * 0.3, 140))
                                .overlay(Rectangle().stroke(.white, lineWidth: 1))
                                .shadow(radius: 4)
                                .accessibilityLabel("Processed crop inset")
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 70)
                }
                if controller.settings.preShotSeconds > 0 && !controller.isBusy {
                    VStack { HStack { Spacer(); Text("PRE \(controller.bufferedCount)").font(.caption.monospaced())
                        .padding(7).background(.black.opacity(0.55), in: Capsule()) }; Spacer() }.padding(10)
                }
            }
            .foregroundStyle(.white).allowsHitTesting(false)
        }
    }
}

struct FujiShootingStatusView: View {
    @ObservedObject var controller: FujiShootingController
    let photoLibrary: PhotoLibraryService
    var body: some View {
        if controller.isBusy || controller.isComposing || controller.errorMessage != nil || controller.pendingExportCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                if controller.isBusy {
                    ProgressView(value: controller.progress)
                    HStack {
                        Text(controller.status).font(.caption).lineLimit(2)
                        Spacer()
                        Button("Cancel") { controller.cancel() }.frame(minWidth: 60, minHeight: 44)
                    }
                } else if controller.isComposing {
                    Text(controller.status).font(.caption).lineLimit(3)
                    Button("Discard layers", role: .destructive) { controller.cancel() }.frame(minHeight: 44)
                }
                if let error = controller.errorMessage {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Dismiss") { controller.errorMessage = nil }.font(.caption).frame(minWidth: 44, minHeight: 44)
                    }
                }
                if !controller.isBusy && controller.pendingExportCount > 0 {
                    Button("Retry \(controller.pendingExportCount) Photos saves") { controller.retryExports(photoLibrary: photoLibrary) }
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12).accessibilityIdentifier("fuji-shooting-status")
        }
    }
}
