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
    @State private var comparison = ReviewComparisonState()
    @State private var isShowingLookLibrary = false

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

                            // Short screens and accessibility text put tools first;
                            // the photograph must not push Compare below the fold.
                            if proxy.size.width > proxy.size.height || dynamicTypeSize.isAccessibilitySize {
                                reviewControls(wide: isPortraitTablet)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 14)
                            }

                            framePreview(
                                maxWidth: max(proxy.size.width - 32, 1),
                                maxHeight: max(previewHeight, 160)
                            )
                            .padding(.horizontal, 16)

                            if proxy.size.width <= proxy.size.height && !dynamicTypeSize.isAccessibilitySize {
                                reviewControls(wide: isPortraitTablet)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)
                            }

                            metadataBlock
                                .padding(.horizontal, 20)
                                .padding(.top, 12)

                            if let saveErrorMessage {
                                saveError(saveErrorMessage)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                            }
                        }
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("review-content-scroll")
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        actionBar
                            .frame(maxWidth: FilmyLayout.readableMaxWidth)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                            .background(FilmyTheme.background)
                            .overlay(alignment: .top) { FilmyTheme.line.frame(height: 1) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-screen")
        .sheet(isPresented: $isShowingLookLibrary) {
            LookLibraryView(
                recipes: availableRecipes,
                selectedRecipeID: selectedReviewRecipeID,
                selectionIdentifierPrefix: "review-look",
                subtitle: "Choose a treatment for this photo.",
                onSelect: { candidate in
                    guard !isSaving, !isPreparingReviewOriginal else { return }
                    comparison.reset()
                    isShowingLookLibrary = false
                    onApplyReviewRecipe(candidate)
                },
                onClose: { isShowingLookLibrary = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(FilmyTheme.background)
            .presentationCornerRadius(28)
        }
        .onAppear {
            comparison.reset()
        }
        .onChange(of: recipe.id) { _, _ in
            comparison.reset()
        }
        .onChange(of: pendingReviewRecipeID) { _, _ in
            comparison.reset()
        }
        .onChange(of: finish) { _, _ in
            comparison.reset()
        }
        .onChange(of: pendingReviewFinish) { _, _ in
            comparison.reset()
        }
        .onChange(of: reviewOriginalImage != nil) { _, hasOriginal in
            if hasOriginal { comparison.originalDidLoad(splitSupported: supportsSplit) }
        }
        .onChange(of: isPreparingReviewOriginal) { _, preparing in
            if !preparing && reviewOriginalImage == nil { comparison.preparationFailed() }
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

        // A wide portrait iPad keeps look, comparison, and finish in one row.
        // Reserve that row (or the taller phone chooser) plus the pinned save
        // disclosure so the photo and controls fit without covering each other.
        let fixedChromeHeight: CGFloat = isPortraitTablet ? 360 : 446
        return min(idealHeight, max(size.height - fixedChromeHeight, 160))
    }

    private func sidePanel(compact: Bool = false) -> some View {
        let actionsInsideScroll = compact && dynamicTypeSize.isAccessibilitySize

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: compact ? 10 : 18) {
                    header
                    if !compact {
                        metadataBlock
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
            Text(isImported ? "Edit photo" : "Review")
                .font(.title2.weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("review-heading")
            Spacer(minLength: 8)
            Label("New copy", systemImage: "square.on.square")
                .font(.caption.weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
        }
    }

    private var isShowingOriginal: Bool { comparison.mode == .original }

    private var supportsSplit: Bool {
        guard let original = reviewOriginalImage else { return finish == .photo }
        return ReviewComparisonGeometry.supportsSplit(original: original.size, edited: image.size, finish: finish)
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

        return VStack(spacing: 8) {
            ZStack {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: fitted.width, height: fitted.height)

                if comparison.mode == .split, let original = reviewOriginalImage, supportsSplit {
                    Image(uiImage: original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fitted.width, height: fitted.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: fitted.width * comparison.originalFraction)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    comparisonDivider(in: fitted)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .coordinateSpace(name: "review-comparison-space")
            .accessibilityElement(children: comparison.mode == .split ? .contain : .ignore)
            .accessibilityIdentifier("review-image")
            .accessibilityLabel(
                comparison.mode == .split
                    ? "Original on the left, \(recipe.name) on the right"
                    : isShowingOriginal
                        ? "Original source photo, without the Filmy look"
                        : isImported
                            ? "Imported photo with \(recipe.name), \(finishTitle(finish)), \(resolutionCaption)"
                            : "Captured frame with \(recipe.name), \(finishTitle(finish)), \(resolutionCaption)"
            )

            if comparison.mode != .look {
                HStack(spacing: 8) {
                    Text("Original")
                    Spacer(minLength: 0)
                    if comparison.mode == .split { Text(recipe.name) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(FilmyTheme.comparison)
                .frame(width: fitted.width)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonDivider(in size: CGSize) -> some View {
        let splitX = size.width * comparison.originalFraction
        let handleX = min(max(splitX, 22), max(size.width - 22, 22))
        return ZStack {
            Rectangle()
                .fill(Color.black)
                .frame(width: 4, height: size.height)
                .overlay { Rectangle().fill(Color.white).frame(width: 2) }
                .position(x: splitX, y: size.height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FilmyTheme.background)
                .frame(width: 44, height: 44)
                .background(FilmyTheme.comparison, in: Circle())
                .overlay { Circle().strokeBorder(.black, lineWidth: 2) }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("review-comparison-space"))
                        .onChanged { value in
                            comparison.moveDivider(to: value.location.x / max(size.width, 1))
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("review-comparison-divider")
                .accessibilityLabel("Before and after divider")
                .accessibilityValue("Original \(Int((comparison.originalFraction * 100).rounded())) percent")
                .accessibilityHint("Drag left or right, or swipe up or down to adjust. Double tap to center.")
                .accessibilityAdjustableAction { direction in
                    comparison.stepDivider(increasing: direction == .increment)
                    HapticFeedback.play(.controlStep)
                }
                .accessibilityAction { comparison.moveDivider(to: 0.5) }
                .offset(x: handleX - size.width / 2, y: size.height * 0.15)
        }
        .frame(width: size.width, height: size.height)
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
                    comparisonControls
                    finishPicker(stacked: false)
                        .frame(width: 280, alignment: .leading)
                }
            } else if stacked || dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    lookPicker
                    comparisonControls
                }
            } else {
                // Preserve readable names on small iPhones. Comparison has
                // two explicit actions; it must not squeeze the active look.
                VStack(alignment: .leading, spacing: 10) {
                    lookPicker
                    comparisonControls
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


        }
    }

    private func panelActions(compact: Bool) -> some View {
        VStack(spacing: 10) {
            saveDisclosure
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

            if selectedReviewFinish == .instantPrint {
                Text(finishDescription(selectedReviewFinish))
                    .font(.caption)
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-finish-picker")
    }

    private func finishButton(_ candidate: PhotoFinish) -> some View {
        let isSelected = selectedReviewFinish == candidate
        return Button {
            guard !isSaving, !isPreparingReviewOriginal else { return }
            comparison.reset()
            onApplyReviewFinish(candidate)
        } label: {
            Label(finishTitle(candidate), systemImage: candidate == .instantPrint ? "rectangle.inset.filled" : "rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? FilmyTheme.background : FilmyTheme.secondary)
                .lineLimit(2)
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
        Button {
            HapticFeedback.play(.selection)
            isShowingLookLibrary = true
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
                Image(systemName: "square.grid.2x2")
                    .font(.system(.caption2, weight: .bold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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

    private var comparisonControls: some View {
        HStack(spacing: 8) {
            compareButton
            if supportsSplit {
                Button {
                    requestComparison(comparison.mode == .split ? .look : .split)
                } label: {
                    Label(comparison.mode == .split ? "Done" : "Split", systemImage: "rectangle.lefthalf.filled")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(comparison.mode == .split ? FilmyTheme.background : FilmyTheme.comparison)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(comparison.mode == .split ? FilmyTheme.comparison : FilmyTheme.panel, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(isSaving || isRenderingReview || isPreparingReviewOriginal)
                .accessibilityIdentifier("review-compare-split")
                .accessibilityLabel("Split comparison")
                .accessibilityValue(comparison.mode == .split ? "On" : "Off")
                .accessibilityHint("Compare original and look at the same position. Drag the divider on the photo.")
            }
        }
    }

    private func requestComparison(_ mode: ReviewComparisonState.Mode) {
        guard !isSaving, !isRenderingReview, !isPreparingReviewOriginal else { return }
        HapticFeedback.play(.selection)
        if comparison.select(mode, originalAvailable: reviewOriginalImage != nil, splitSupported: supportsSplit) {
            Task { await onPrepareReviewOriginal() }
        }
    }

    private var compareButton: some View {
        Button {
            requestComparison(isShowingOriginal ? .look : .original)
        } label: {
            HStack(spacing: 7) {
                if isPreparingReviewOriginal {
                    ProgressView().tint(FilmyTheme.comparison)
                } else {
                    Image(systemName: "circle.lefthalf.filled")
                }
                Text(isShowingOriginal ? "Show look" : "Original")
                    .lineLimit(1)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(isShowingOriginal ? FilmyTheme.background : FilmyTheme.comparison)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(isShowingOriginal ? FilmyTheme.comparison : FilmyTheme.panel, in: Capsule())
            .contentShape(Capsule())
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
        Label(resolutionCaption, systemImage: "photo")
            .font(.system(.caption).weight(.medium))
            .foregroundStyle(FilmyTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 10) {
            saveDisclosure
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-action-bar")
    }

    private var saveDisclosure: some View {
        Text(comparison.mode != .look
             ? "Saves \(recipe.name) · \(finishTitle(finish)), not the original preview."
             : isImported
                ? "Save a new copy. Your original stays unchanged."
                : "Only the finished photo is saved to Photos.")
            .font(.caption)
            .foregroundStyle(FilmyTheme.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityIdentifier("review-cancel")
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
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }
        }
        .buttonStyle(.filmyPrimary)
        .accessibilityIdentifier("review-save")
        .disabled(isSaving || isRenderingReview || isPreparingReviewOriginal)
        .accessibilityLabel(keepFrameAccessibilityLabel)
        .accessibilityHint("Saves the finished photo to your Photos library")
    }
}
