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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Review")
                                .font(.system(.caption, design: .default).weight(.semibold))
                                .foregroundStyle(FilmyTheme.accent)
                            Text(recipe.name)
                                .font(.system(.title2, design: .default).weight(.bold))
                                .foregroundStyle(FilmyTheme.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button {
                            onRetake()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(FilmyTheme.primary)
                                .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Discard frame")
                        .disabled(isSaving)
                    }

                    ZStack(alignment: .bottomLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 500)
                            .background(Color.black.opacity(0.3))

                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.74)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        HStack(spacing: 8) {
                            Image(systemName: "camera.aperture")
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(recipe.descriptor)
                                    .font((dynamicTypeSize.isAccessibilitySize ? Font.caption : Font.caption2).weight(.medium))
                                    .foregroundStyle(.white.opacity(0.74))
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        }
                        .padding(14)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Recipe \(recipe.name)")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Captured frame with \(recipe.name)")

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(FilmyTheme.mint)
                        Text("Ready to keep")
                            .font(.subheadline.weight(.bold))
                        Spacer(minLength: 6)
                        Text("Full resolution")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FilmyTheme.secondary)
                    }
                    .foregroundStyle(FilmyTheme.primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(FilmyTheme.panel.opacity(0.8), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(FilmyTheme.line, lineWidth: 1)
                    }
                    .accessibilityElement(children: .combine)

                    if let saveErrorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundStyle(FilmyTheme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isStaticText)

                            Button("Open Photos Settings", action: onOpenSettings)
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(FilmyTheme.accent)
                                .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                                .accessibilityHint("Opens Filmy Camera Photos permissions")
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FilmyTheme.line)
                        .frame(height: 1)
                }
            }
        .interactiveDismissDisabled(isSaving)
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
                .font(.system(.body, design: .default).weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
            .font(.system(.body, design: .default).weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(isSaving ? "Saving frame" : "Keep frame")
        .accessibilityHint("Saves the finished frame to your Photos library")
    }
}
