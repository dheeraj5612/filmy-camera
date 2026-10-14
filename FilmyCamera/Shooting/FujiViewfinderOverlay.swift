import SwiftUI

struct FujiViewfinderOverlay: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var camera: CameraService
    /// Value input so SwiftUI re-evaluates the bank chip when the look or its live tuning changes; bankIsDirty reads the same recipe through the controller.
    let selectedRecipe: FilmRecipe
    /// Measured height of the top bar when it overlays the viewfinder (iPad, landscape); nil on iPhone portrait.
    var topChromeHeight: CGFloat? = nil
    private var viewfinderState: FujiViewfinderState? {
        let preferences = controller.preferences
        var bank: Int?
        // Sequences move exposure, focus and look, so the bank is judged only at rest.
        if !controller.settingsLocked, let id = preferences.selectedBank,
           let saved = preferences.banks.first(where: { $0.id == id }) {
            bank = FujiViewfinderState.activeBank(id: id, saved: saved.settings, current: controller.settings,
                                                  lookOrCameraEdited: controller.bankIsDirty(saved))
        }
        return FujiViewfinderState.make(settings: controller.settings, activeBank: bank)
    }

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
                if let state = viewfinderState {
                    // Leading edge, below the measured top bar and the histogram's default corner
                    // (bar + 8 + 8 + 82 + 8; 160 when unmeasured), above the tool rail and zoom row on short finders.
                    let chipTop = CameraPreviewGesturePolicy.fujiChipTop(topChromeHeight: topChromeHeight,
                                                                         viewfinderHeight: proxy.size.height)
                    FujiViewfinderStateChip(state: state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.top, chipTop)
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

private struct FujiViewfinderStateChip: View {
    let state: FujiViewfinderState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.isBlocked ? "exclamationmark.triangle.fill" : "circle.fill")
                .imageScale(.small)
                .foregroundStyle(state.isBlocked ? Color.orange : FilmyTheme.filmAccent)
            Text(state.text).minimumScaleFactor(0.75).lineLimit(2)
        }
        .font(.caption2.weight(.semibold).monospaced())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shooting state")
        .accessibilityValue(state.spoken)
        .accessibilityIdentifier("fuji-viewfinder-state")
    }
}

struct FujiShootingStatusView: View {
    @ObservedObject var controller: FujiShootingController
    let photoLibrary: PhotoLibraryService
    @State private var confirmDiscard = false
    var body: some View {
        let layerNoun: String = controller.multipleCount == 1 ? "layer" : "layers"
        let discardTitle = "Discard \(controller.multipleCount) \(layerNoun)?"
        Group {
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
                    Button("Discard layers", role: .destructive) { confirmDiscard = true }.frame(minHeight: 44)
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
            .confirmationDialog(discardTitle, isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard layers", role: .destructive) { controller.cancel() }
                Button("Keep composing", role: .cancel) {}
            } message: { Text("The blended composite is discarded. Layer sources stay in RAW Develop.") }
        }
        }
        .onChange(of: controller.isComposing) { _, composing in if !composing { confirmDiscard = false } }
    }
}
