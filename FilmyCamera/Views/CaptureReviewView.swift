import SwiftUI
import UIKit

struct CaptureReviewView: View {
    let image: UIImage
    let recipe: FilmRecipe
    let isSaving: Bool
    let saveErrorMessage: String?
    let onSave: () -> Void
    let onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REVIEW FRAME")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(FilmyTheme.accent)
                        Text(recipe.name)
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundStyle(FilmyTheme.primary)
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
                            .background(FilmyTheme.panel, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard frame")
                    .disabled(isSaving)
                }

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .accessibilityLabel("Captured frame with \(recipe.name)")

                HStack(spacing: 7) {
                    Image(systemName: "camera.aperture")
                    Text(recipe.name)
                        .lineLimit(1)
                }
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(FilmyTheme.panel, in: Capsule())
                .overlay { Capsule().stroke(FilmyTheme.line, lineWidth: 1) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recipe \(recipe.name)")

                if let saveErrorMessage {
                    Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isStaticText)
                }

                HStack(spacing: 10) {
                    Button {
                        onRetake()
                        dismiss()
                    } label: {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(FilmyTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

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
                        .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(FilmyTheme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .accessibilityLabel(isSaving ? "Saving frame" : "Keep frame")
                    .accessibilityHint("Saves the finished frame to your Photos library")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }
}
