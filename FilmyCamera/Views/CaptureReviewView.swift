import SwiftUI
import UIKit

struct CaptureReviewView: View {
    let image: UIImage
    let recipe: FilmRecipe
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

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                framePreview
                    .padding(.horizontal, 16)

                if let saveErrorMessage {
                    saveError(saveErrorMessage)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }
            }
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
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
                Eyebrow(text: "REVIEW", color: FilmyTheme.accent)
                Text(recipe.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
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
            .accessibilityLabel("Discard frame")
            .disabled(isSaving)
        }
    }

    private var framePreview: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
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
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Captured frame with \(recipe.name)")
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
                Text("Full resolution")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
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
            onRetake()
            dismiss()
        } label: {
            Label("Retake", systemImage: "arrow.counterclockwise")
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
                    Label("Keep Frame", systemImage: "checkmark")
                }
            }
        }
        .buttonStyle(.filmyPrimary)
        .disabled(isSaving)
        .accessibilityLabel(isSaving ? "Saving frame" : "Keep frame")
        .accessibilityHint("Saves the finished frame to your Photos library")
    }
}
