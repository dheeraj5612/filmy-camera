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
    let onSave: () -> Void
    let onRetake: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            // The frame is sized from the available area so it normally fits
            // without scrolling, but the page still scrolls on short or
            // landscape displays and at accessibility text sizes so the save
            // error and its recovery action can never be pushed offscreen.
            GeometryReader { proxy in
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
            }
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
        .interactiveDismissDisabled(isSaving)
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

            Button {
                HapticFeedback.play(.discard)
                onRetake()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FilmyTheme.primary)
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .background(FilmyTheme.panelRaised, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("review-back-to-camera")
            .accessibilityLabel(isImported ? "Discard imported photo" : "Discard frame")
            .accessibilityHint("Returns to the camera without saving")
            .disabled(isSaving)
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
            .overlay(alignment: .bottomLeading) {
                recipeChip
                    .padding(14)
            }
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isImported
                    ? "Imported photo with \(recipe.name)"
                    : "Captured frame with \(recipe.name)"
            )
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

    private var recipeChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(FilmyTheme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(recipe.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(resolutionCaption)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .viewfinderCapsule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recipe \(recipe.name), full resolution")
    }

    private func saveError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isStaticText)

            Button("Open Photos Settings", action: onOpenSettings)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                .accessibilityHint("Opens Filmy Camera Photos permissions")
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
