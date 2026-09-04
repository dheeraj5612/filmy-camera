import SwiftUI
import UIKit

struct CaptureReviewView: View {
    let image: UIImage
    let recipe: FilmRecipe
    let source: CameraViewModel.ReviewSource
    var isFullResolution = true
    var flashFired = false
    let isSaving: Bool
    let saveErrorMessage: String?
    var saveErrorRequiresSettings = false
    let onSave: () -> Void
    let onRetake: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            GeometryReader { proxy in
                if usesSidePanel(for: proxy.size) {
                    let sideWidth = min(max(proxy.size.width * 0.26, 300), 380)
                    let photoWidth = max(proxy.size.width - sideWidth - 92, 1)
                    HStack(alignment: .center, spacing: 28) {
                        framePreview(
                            maxWidth: photoWidth,
                            maxHeight: max(proxy.size.height - 48, 160)
                        )
                        .frame(width: photoWidth, alignment: .center)

                        sidePanel
                            .frame(width: sideWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                } else {
                    // Keep the photo and its metadata together in a bounded
                    // scroll view for phone portrait, landscape, and large
                    // Dynamic Type sizes.
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            header
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 12)

                            framePreview(
                                maxWidth: max(proxy.size.width - 32, 1),
                                maxHeight: max(proxy.size.height * 0.64, 160)
                            )
                            .padding(.horizontal, 16)

                            metadataBlock
                                .padding(.horizontal, 20)
                                .padding(.top, 14)

                            if let saveErrorMessage {
                                saveError(saveErrorMessage)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                            }
                        }
                        .padding(.bottom, 16)
                        .frame(maxWidth: FilmyLayout.readableMaxWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBar
                            .frame(maxWidth: FilmyLayout.readableMaxWidth)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                            .background(FilmyTheme.background)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-screen")
        .interactiveDismissDisabled(isSaving)
    }

    private func usesSidePanel(for size: CGSize) -> Bool {
        size.width >= 700 && size.height >= 500
    }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    metadataBlock

                    if let saveErrorMessage {
                        saveError(saveErrorMessage)
                    }
                }
                .padding(.bottom, 18)
            }

            actionBar
                .padding(.top, 14)
        }
        .frame(maxHeight: .infinity)
        .padding(22)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: isImported ? "IMPORTED PHOTO" : "REVIEW", color: FilmyTheme.accent)
                Text(recipe.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
    }

    private var isImported: Bool {
        source == .photoLibrary
    }

    /// Never promise full resolution for an import that was bounded to the
    /// pixel budget; say what actually happened.
    private var resolutionCaption: String {
        switch (isImported, isFullResolution) {
        case (true, true): return "Filter applied · Full resolution"
        case (true, false): return "Filter applied · Resized to fit \(Int(CameraViewModel.importPixelBudget / 1_000_000)) MP"
        case (false, _): return flashFired ? "Full resolution · Flash fired" : "Full resolution"
        }
    }

    private func framePreview(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let fitted = Self.fittedSize(
            for: image.size,
            within: CGSize(width: maxWidth, height: maxHeight)
        )

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("review-image")
            .accessibilityLabel(
                isImported
                    ? "Imported photo with \(recipe.name), \(resolutionCaption)"
                    : "Captured frame with \(recipe.name), \(resolutionCaption)"
            )
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
            .frame(maxWidth: .infinity)
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(resolutionCaption)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.secondary)

            Text(isImported ? "Ready to save to Photos" : "Captured with the current camera settings")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-metadata")
    }

    /// Largest size with the image's aspect ratio that fits inside `bounds`.
    static func fittedSize(for imageSize: CGSize, within bounds: CGSize) -> CGSize {
        let safeBounds = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
        guard imageSize.width > 0, imageSize.height > 0 else { return safeBounds }

        let scale = min(
            safeBounds.width / imageSize.width,
            safeBounds.height / imageSize.height
        )
        return CGSize(
            width: (imageSize.width * scale).rounded(.down),
            height: (imageSize.height * scale).rounded(.down)
        )
    }

    private func saveError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isStaticText)

            if saveErrorRequiresSettings {
                Button("Open Photos Settings", action: onOpenSettings)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                    .accessibilityIdentifier("review-save-error-settings")
                    .accessibilityHint("Opens Filmy Camera Photos permissions")
            } else {
                Button("Try Again", action: onSave)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                    .accessibilityIdentifier("review-save-error-retry")
                    .accessibilityHint("Retries saving this finished photo")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmyTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(FilmyTheme.danger.opacity(0.3), lineWidth: 1)
        }
    }

    private var actionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    retakeButton
                    keepFrameButton
                }
            } else {
                HStack(spacing: 10) {
                    retakeButton
                    keepFrameButton
                }
            }
        }
    }

    private var retakeButton: some View {
        Button {
            HapticFeedback.play(.discard)
            onRetake()
            dismiss()
        } label: {
            Label(
                isImported ? "Cancel" : "Retake",
                systemImage: isImported ? "xmark" : "arrow.counterclockwise"
            )
        }
        .buttonStyle(.filmySecondary)
        .disabled(isSaving)
    }

    private var keepFrameButton: some View {
        Button {
            onSave()
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .tint(FilmyTheme.background)
                } else {
                    Label(isImported ? "Save Photo" : "Keep Frame", systemImage: "checkmark")
                }
            }
        }
        .buttonStyle(.filmyPrimary)
        .disabled(isSaving)
        .accessibilityLabel(
            isSaving
                ? "Saving photo"
                : isImported ? "Save filtered photo" : "Keep frame"
        )
        .accessibilityHint("Saves the finished photo to your Photos library")
    }
}
