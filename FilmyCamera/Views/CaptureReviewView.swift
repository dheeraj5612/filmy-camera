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
    let availableRecipes: [FilmRecipe]
    let pendingReviewRecipeID: String?
    let isRenderingReview: Bool
    let reviewRenderErrorMessage: String?
    let reviewOriginalImage: UIImage?
    let isPreparingReviewOriginal: Bool
    let onSave: () -> Void
    let onRetake: () -> Void
    let onOpenSettings: () -> Void
    let onApplyReviewRecipe: (FilmRecipe) -> Void
    let onPrepareReviewOriginal: () async -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingOriginal = false

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
                    let isPortraitTablet = proxy.size.width >= 700 && proxy.size.height > proxy.size.width
                    let previewHeight = reviewPreviewHeight(
                        for: proxy.size,
                        isPortraitTablet: isPortraitTablet
                    )
                    // Keep the photo and its metadata together in a bounded
                    // scroll view for phone portrait, landscape, and large
                    // Dynamic Type sizes.
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            header
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 12)

                            reviewControls()
                                .padding(.horizontal, 20)
                                .padding(.bottom, 14)

                            framePreview(
                                maxWidth: max(proxy.size.width - 32, 1),
                                maxHeight: max(previewHeight, 160)
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
        .onAppear {
            isShowingOriginal = false
        }
        .onChange(of: recipe.id) { _, _ in
            isShowingOriginal = false
        }
        .onChange(of: pendingReviewRecipeID) { _, _ in
            isShowingOriginal = false
        }
        .onChange(of: reviewOriginalImage != nil) { _, hasOriginal in
            if hasOriginal {
                isShowingOriginal = true
            }
        }
    }

    private func usesSidePanel(for size: CGSize) -> Bool {
        size.width > size.height && size.width >= 700 && size.height >= 500
    }

    private func reviewPreviewHeight(for size: CGSize, isPortraitTablet: Bool) -> CGFloat {
        let idealHeight = size.height * (isPortraitTablet ? 0.78 : 0.64)
        guard !dynamicTypeSize.isAccessibilitySize else { return idealHeight }

        // Reserve the fixed review chrome: header (76), chooser (68),
        // metadata (54), pinned actions (82), and their surrounding gaps
        // (20). This keeps the fitted photo in the normal viewport while
        // accessibility sizes retain the larger hero and scroll naturally.
        let fixedChromeHeight: CGFloat = 76 + 68 + 54 + 82 + 20
        return min(idealHeight, max(size.height - fixedChromeHeight, 160))
    }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    metadataBlock
                    reviewControls(stacked: true)

                    if let saveErrorMessage {
                        saveError(saveErrorMessage)
                    }
                }
                .padding(.bottom, 18)
            }

            VStack(spacing: 10) {
                retakeButton
                keepFrameButton
            }
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
            for: displayImage.size,
            within: CGSize(width: maxWidth, height: maxHeight)
        )

        return Image(uiImage: displayImage)
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
                isShowingOriginal
                    ? "Original source photo, without the Filmy look"
                    : isImported
                        ? "Imported photo with \(recipe.name), \(resolutionCaption)"
                        : "Captured frame with \(recipe.name), \(resolutionCaption)"
            )
            .overlay(alignment: .topLeading) {
                if isShowingOriginal {
                    Text("ORIGINAL")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.72), in: Capsule())
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
            .frame(maxWidth: .infinity)
    }

    private var displayImage: UIImage {
        if isShowingOriginal, let reviewOriginalImage {
            return reviewOriginalImage
        }
        return image
    }

    private var selectedReviewRecipeID: String {
        pendingReviewRecipeID ?? recipe.id
    }

    private var pendingReviewRecipeName: String {
        availableRecipes.first(where: { $0.id == pendingReviewRecipeID })?.name
            ?? recipe.name
    }

    private struct ReviewRecipeGroup: Identifiable {
        let title: String
        let recipes: [FilmRecipe]

        var id: String { title }
    }

    private var groupedReviewRecipes: [ReviewRecipeGroup] {
        let compact = availableRecipes.filter { $0.filmBase == .compactDigital }
        let monochrome = availableRecipes.filter {
            $0.filmBase.monochromeFilter != nil || $0.filmBase == .sepia
        }
        let film = availableRecipes.filter {
            $0.filmBase != .compactDigital
                && $0.filmBase.monochromeFilter == nil
                && $0.filmBase != .sepia
        }

        return [
            ReviewRecipeGroup(title: "Compact", recipes: compact),
            ReviewRecipeGroup(title: "Film", recipes: film),
            ReviewRecipeGroup(title: "Monochrome", recipes: monochrome)
        ].filter { !$0.recipes.isEmpty }
    }

    private func reviewControls(stacked: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if stacked || dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    lookPicker
                    compareButton
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    lookPicker
                    compareButton
                }
            }

            if isRenderingReview || isPreparingReviewOriginal {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(FilmyTheme.filmAccent)
                    Text(
                        isRenderingReview
                            ? "Developing \(pendingReviewRecipeName)…"
                            : "Preparing original…"
                    )
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(FilmyTheme.secondary)
                }
                .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review-render-status")
            }

            if let reviewRenderErrorMessage, !reviewRenderErrorMessage.isEmpty {
                Label(reviewRenderErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(FilmyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("review-render-error")
            }

            Text(isShowingOriginal
                 ? "Original preview · Save keeps \(recipe.name)"
                 : "Save \(recipe.name) to Photos")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lookPicker: some View {
        Menu {
            ForEach(groupedReviewRecipes) { group in
                Section(group.title) {
                    ForEach(group.recipes) { candidate in
                        let isSelected = candidate.id == selectedReviewRecipeID
                        Button {
                            guard !isSaving, !isPreparingReviewOriginal else { return }
                            isShowingOriginal = false
                            onApplyReviewRecipe(candidate)
                        } label: {
                            Label(
                                candidate.name,
                                systemImage: isSelected ? "checkmark" : "film"
                            )
                        }
                        .accessibilityIdentifier("review-look-\(candidate.id)")
                        .accessibilityLabel("Use \(candidate.name) look")
                        .accessibilityValue(isSelected ? "Selected" : "Available")
                        .accessibilityHint("Applies this look to the reviewed photo")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Look")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.tertiary)
                    Text(pendingReviewRecipeName)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .bold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
            .padding(.horizontal, 12)
            .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isSaving || isPreparingReviewOriginal)
        .accessibilityIdentifier("review-look-picker")
        .accessibilityLabel("Choose review look")
        .accessibilityValue(pendingReviewRecipeName)
        .accessibilityHint("Choose a Compact, Film, or Monochrome look for this photo")
        .frame(maxWidth: .infinity)
    }

    private var compareButton: some View {
        Button {
            if reviewOriginalImage != nil {
                isShowingOriginal.toggle()
            } else if !isPreparingReviewOriginal {
                Task {
                    await onPrepareReviewOriginal()
                }
            }
        } label: {
            HStack(spacing: 7) {
                if isPreparingReviewOriginal {
                    ProgressView()
                        .tint(FilmyTheme.primary)
                } else {
                    Image(systemName: isShowingOriginal ? "photo" : "photo.on.rectangle")
                }
                Text(isShowingOriginal ? "Look" : "Original")
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            .background(FilmyTheme.backgroundRaised, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    isShowingOriginal ? FilmyTheme.filmAccent : FilmyTheme.lineStrong,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.pressable)
        .disabled(isSaving || isRenderingReview || isPreparingReviewOriginal)
        .accessibilityIdentifier("review-compare-original")
        .accessibilityLabel("Compare with original")
        .accessibilityValue(isShowingOriginal ? "Original" : "Look")
        .accessibilityHint(
            reviewOriginalImage == nil
                ? "Loads the original source photo for comparison"
                : "Switches between the original source photo and the applied look"
        )
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
                    .disabled(isSaving || isRenderingReview || isPreparingReviewOriginal)
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
        } label: {
            Label(
                isImported ? "Cancel" : "Retake",
                systemImage: isImported ? "xmark" : "arrow.counterclockwise"
            )
        }
        .buttonStyle(.filmySecondary)
        .disabled(isSaving)
    }

    private var keepFrameAccessibilityLabel: String {
        if isSaving { return "Saving photo" }
        if isPreparingReviewOriginal { return "Preparing original" }
        if isRenderingReview { return "Rendering selected look" }
        return isImported ? "Save filtered photo" : "Keep frame"
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
        .disabled(isSaving || isRenderingReview || isPreparingReviewOriginal)
        .accessibilityLabel(keepFrameAccessibilityLabel)
        .accessibilityHint("Saves the finished photo to your Photos library")
    }
}
