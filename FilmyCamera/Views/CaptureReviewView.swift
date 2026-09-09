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
    /// The selected export finish. The rendered review image already includes
    /// the finish, so this control only chooses which result to develop next.
    var finish: PhotoFinish = .photo
    var pendingReviewFinish: PhotoFinish? = nil
    let isRenderingReview: Bool
    let reviewRenderErrorMessage: String?
    let reviewOriginalImage: UIImage?
    let isPreparingReviewOriginal: Bool
    let onSave: () -> Void
    let onRetake: () -> Void
    let onOpenSettings: () -> Void
    let onApplyReviewRecipe: (FilmRecipe) -> Void
    let onPrepareReviewOriginal: () async -> Void
    var onApplyReviewFinish: (PhotoFinish) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingOriginal = false

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            GeometryReader { proxy in
                if usesSidePanel(for: proxy.size) {
                    let sideWidth = sidePanelWidth(for: proxy.size)
                    let photoWidth = max(proxy.size.width - sideWidth - 92, 1)
                    HStack(alignment: .center, spacing: 28) {
                        framePreview(
                            maxWidth: photoWidth,
                            maxHeight: max(proxy.size.height - 48, 160)
                        )
                        .frame(width: photoWidth, alignment: .center)

                        sidePanel(compact: proxy.size.height <= 500)
                            .frame(width: sideWidth, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.vertical, proxy.size.height <= 500 ? 8 : 24)
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

                            reviewControls(wide: isPortraitTablet)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 14)

                            framePreview(
                                maxWidth: max(proxy.size.width - 32, 1),
                                maxHeight: max(previewHeight, 160)
                            )
                            .padding(.horizontal, 16)

                            metadataBlock(widePortrait: isPortraitTablet)
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
        .onChange(of: finish) { _, _ in
            isShowingOriginal = false
        }
        .onChange(of: pendingReviewFinish) { _, _ in
            isShowingOriginal = false
        }
        .onChange(of: reviewOriginalImage != nil) { _, hasOriginal in
            if hasOriginal {
                isShowingOriginal = true
            }
        }
    }

    private func usesSidePanel(for size: CGSize) -> Bool {
        guard size.width > size.height else { return false }

        // Phones in landscape have enough width for a compact control column,
        // but not enough height for the portrait review stack. Keeping the
        // photo and controls side by side prevents the action bar from
        // covering the fitted image. The wider iPad layout uses the same
        // arrangement with a more comfortable column.
        return size.width >= 700 || size.height <= 500
    }

    private func sidePanelWidth(for size: CGSize) -> CGFloat {
        if size.height <= 500 {
            return min(max(size.width * 0.34, 250), 300)
        }
        return min(max(size.width * 0.26, 300), 380)
    }

    private func reviewPreviewHeight(for size: CGSize, isPortraitTablet: Bool) -> CGFloat {
        let idealHeight = size.height * (isPortraitTablet ? 0.78 : 0.64)
        guard !dynamicTypeSize.isAccessibilitySize else { return idealHeight }

        // A wide portrait iPad keeps look, comparison, and finish in one
        // compact row. Reserve that row's actual footprint so the fitted
        // photo can use the width available on the tablet. Smaller layouts
        // retain the taller two-row chooser and scroll naturally at larger
        // Dynamic Type sizes.
        let fixedChromeHeight: CGFloat = isPortraitTablet ? 310 : 396
        return min(idealHeight, max(size.height - fixedChromeHeight, 160))
    }

    private func sidePanel(compact: Bool = false) -> some View {
        let actionsInsideScroll = compact && dynamicTypeSize.isAccessibilitySize

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: compact ? 10 : 18) {
                    header
                    if !compact {
                        metadataBlock()
                    }
                    reviewControls(stacked: !compact, compact: compact)

                    if let saveErrorMessage {
                        saveError(saveErrorMessage)
                    }

                    if actionsInsideScroll {
                        panelActions(compact: true)
                            .padding(.top, 14)
                    }
                }
                .padding(.bottom, compact ? 8 : 18)
            }
            .accessibilityIdentifier("review-controls-scroll")

            if !actionsInsideScroll {
                panelActions(compact: compact)
                    .padding(.top, 14)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(compact ? 12 : 22)
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

        let image = Image(uiImage: displayImage)
            .resizable()
            .scaledToFit()
            .frame(width: fitted.width, height: fitted.height)

        // An Instant Print finish is a real white border in the rendered
        // pixels. Keep its outside edge square so the presentation cannot
        // crop or round the printed frame. Normal photos retain the softer
        // review treatment.
        let finishedImage: AnyView
        if !isShowingOriginal && finish == .instantPrint {
            finishedImage = AnyView(
                image
                    .overlay(Rectangle().strokeBorder(FilmyTheme.lineStrong, lineWidth: 1))
            )
        } else {
            finishedImage = AnyView(
                image
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
                    }
            )
        }

        return finishedImage
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("review-image")
            .accessibilityLabel(
                isShowingOriginal
                    ? "Original source photo, without the Filmy look"
                    : isImported
                        ? "Imported photo with \(recipe.name), \(finishTitle(finish)), \(resolutionCaption)"
                        : "Captured frame with \(recipe.name), \(finishTitle(finish)), \(resolutionCaption)"
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

    private var selectedReviewFinish: PhotoFinish {
        pendingReviewFinish ?? finish
    }

    private func finishTitle(_ finish: PhotoFinish) -> String {
        switch finish {
        case .photo:
            return "Photo"
        case .instantPrint:
            return "Instant Print"
        }
    }

    private func finishDescription(_ finish: PhotoFinish) -> String {
        switch finish {
        case .photo:
            return "Full photo, edge to edge"
        case .instantPrint:
            return "White border, full photo retained"
        }
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

    private func reviewControls(
        stacked: Bool = false,
        compact: Bool = false,
        wide: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if wide && !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 10) {
                    lookPicker
                        .frame(maxWidth: .infinity)
                    compareButton
                    finishPicker(stacked: false)
                        .frame(width: 280, alignment: .leading)
                }
            } else if stacked || dynamicTypeSize.isAccessibilitySize {
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

            if !wide || dynamicTypeSize.isAccessibilitySize {
                finishPicker(stacked: stacked || dynamicTypeSize.isAccessibilitySize)
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

            if !compact {
                Text(isShowingOriginal
                     ? "Original preview · Save keeps \(recipe.name) · \(finishTitle(finish))"
                     : "Save \(recipe.name) to Photos")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func panelActions(compact: Bool) -> some View {
        Group {
            if compact && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    retakeButton
                        .labelStyle(.titleOnly)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    keepFrameButton
                        .labelStyle(.titleOnly)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                VStack(spacing: 10) {
                    retakeButton
                    keepFrameButton
                }
            }
        }
    }

    private func finishPicker(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Finish")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.tertiary)

            Group {
                if stacked {
                    VStack(spacing: 8) {
                        finishButton(.photo)
                        finishButton(.instantPrint)
                    }
                } else {
                    HStack(spacing: 8) {
                        finishButton(.photo)
                        finishButton(.instantPrint)
                    }
                }
            }

            Text(finishDescription(selectedReviewFinish))
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-finish-picker")
    }

    private func finishButton(_ candidate: PhotoFinish) -> some View {
        let isSelected = selectedReviewFinish == candidate
        return Button {
            guard !isSaving, !isPreparingReviewOriginal else { return }
            isShowingOriginal = false
            onApplyReviewFinish(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(finishTitle(candidate))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(candidate == .instantPrint ? "White border" : "Full frame")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(isSelected ? FilmyTheme.background.opacity(0.82) : FilmyTheme.tertiary)
                    .lineLimit(2)
            }
            .foregroundStyle(isSelected ? FilmyTheme.background : FilmyTheme.primary)
            .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                isSelected ? FilmyTheme.filmAccent : FilmyTheme.panel,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? FilmyTheme.filmAccent : FilmyTheme.lineStrong, lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
        .disabled(isSaving || isPreparingReviewOriginal)
        .accessibilityIdentifier(
            candidate == .photo ? "review-finish-photo" : "review-finish-instantPrint"
        )
        .accessibilityLabel("Use \(finishTitle(candidate)) finish")
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityHint(finishDescription(candidate))
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

    private func metadataBlock(widePortrait: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(resolutionCaption)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.secondary)

            if !widePortrait {
                Text(isImported ? "Ready to save to Photos" : "Captured with the current camera settings")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
