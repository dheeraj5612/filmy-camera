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
    @State private var isConfirmingRetake = false
    @State private var openingRecipeID: String?
    @State private var openingFinish: PhotoFinish?
    @GestureState private var isPeekingOriginal = false
    /// Interface state only: the hold-to-peek hint retires once a hold has
    /// really shown the original.
    @AppStorage("reviewPeekHintSeen.v1") private var peekHintSeen = false

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
                            header(showsMetadata: true)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .padding(.bottom, 8)

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
                                reviewControls(wide: isPortraitTablet, tight: !isPortraitTablet)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                            }

                            if dynamicTypeSize.isAccessibilitySize {
                                saveDisclosure()
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                            }
                        }
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("review-content-scroll")
                    .onChange(of: saveErrorMessage) { oldValue, newValue in
                        if let newValue, oldValue != nil {
                            UIAccessibility.post(notification: .announcement, argument: newValue)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        pinnedBottomArea
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
            if openingRecipeID == nil {
                openingRecipeID = recipe.id
                openingFinish = finish
            }
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

    /// Save error, Cancel and Save stay on screen at every text size. The text
    /// is capped at accessibility1 so the bar stays one row.
    private var pinnedBottomArea: some View {
        VStack(spacing: 10) {
            if let saveErrorMessage {
                saveError(saveErrorMessage, pinned: true)
            }
            actionBar(showsDisclosure: !dynamicTypeSize.isAccessibilitySize)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: FilmyLayout.readableMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(FilmyTheme.background)
        .overlay(alignment: .top) { FilmyTheme.line.frame(height: 1) }
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

    /// Fixed chrome below the photo box on a phone in portrait, in points:
    /// header 44, controls 172, bottom padding 8, pinned bar 96. These are
    /// arithmetic from font metrics, measured by the review UI tests.
    private static let phoneChromeHeight: CGFloat = 320
    private static let tabletChromeHeight: CGFloat = 360
    /// Extra height when a render error row shows under the controls.
    private static let renderErrorAllowance: CGFloat = 56
    private static let xLargeChromeAllowance: CGFloat = 48
    private static let xxLargeChromeAllowance: CGFloat = 56
    private static let xxxLargeChromeAllowance: CGFloat = 76

    /// Stacked header, two-line disclosure and wrapped Finish titles at the
    /// three sizes above Large that are not accessibility sizes.
    private var largeTextChromeAllowance: CGFloat {
        switch dynamicTypeSize {
        case .xLarge: return Self.xLargeChromeAllowance
        case .xxLarge: return Self.xxLargeChromeAllowance
        case .xxxLarge: return Self.xxxLargeChromeAllowance
        default: return 0
        }
    }

    private func reviewPreviewHeight(for size: CGSize, isPortraitTablet: Bool) -> CGFloat {
        let idealHeight = size.height * (isPortraitTablet ? 0.78 : 0.64)
        guard !dynamicTypeSize.isAccessibilitySize else { return idealHeight }

        // A wide portrait iPad keeps look, comparison, and finish in one row.
        if isPortraitTablet {
            return min(idealHeight, max(size.height - Self.tabletChromeHeight, 160))
        }
        var chrome = Self.phoneChromeHeight + largeTextChromeAllowance
        if let reviewRenderErrorMessage, !reviewRenderErrorMessage.isEmpty {
            chrome += Self.renderErrorAllowance
        }
        return min(idealHeight, max(size.height - chrome, 160))
    }

    private func sidePanel(compact: Bool = false) -> some View {
        let actionsInsideScroll = compact && dynamicTypeSize.isAccessibilitySize

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: compact ? 10 : 18) {
                    header(showsMetadata: false)
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

    private var reviewTitle: some View {
        Text(isImported ? "Edit photo" : "Review")
            .font(.title2.weight(.bold))
            .foregroundStyle(FilmyTheme.primary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("review-heading")
    }

    @ViewBuilder
    private func header(showsMetadata: Bool) -> some View {
        if showsMetadata && dynamicTypeSize <= .large {
            HStack(alignment: .center, spacing: 12) {
                reviewTitle
                    .fixedSize()
                metadataBlock(trailing: true)
            }
        } else if showsMetadata {
            VStack(alignment: .leading, spacing: 4) {
                reviewTitle
                metadataBlock()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            reviewTitle
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isPeekShowingOriginal: Bool { isPeekingOriginal && reviewOriginalImage != nil }

    private var showsOriginalFrame: Bool { isShowingOriginal || isPeekShowingOriginal }

    private var canPeekOriginal: Bool { comparison.mode == .look && !isSaving }

    private var showsPeekHint: Bool { !peekHintSeen && canPeekOriginal }

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
        // The box follows the look image, so Original, Split and a peek never
        // change its size or move a control.
        let fitted = Self.fittedSize(
            for: image.size,
            within: CGSize(width: maxWidth, height: maxHeight)
        )

        return photoStack(fitted: fitted)
            .frame(maxWidth: .infinity)
    }

    private func photoLayers(fitted: CGSize) -> some View {
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
    }

    private var reviewImageLabel: String {
        if comparison.mode == .split {
            return "Original on the left, \(recipe.name) on the right"
        }
        if showsOriginalFrame {
            return "Original source photo, without the Filmy look"
        }
        if isImported {
            return "Imported photo with \(recipe.name), \(finishTitle(finish)), \(resolutionCaption)"
        }
        return "Captured frame with \(recipe.name), \(finishTitle(finish)), \(resolutionCaption)"
    }

    private func photoStack(fitted: CGSize) -> some View {
        photoLayers(fitted: fitted)
            .overlay(alignment: .bottom) {
                comparisonBadges(width: fitted.width)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(peekGesture, including: canPeekOriginal ? .all : .subviews)
            .onChange(of: isPeekingOriginal) { _, peeking in
                if peeking { beginOriginalPeek() }
            }
            .onChange(of: isPeekShowingOriginal) { _, shown in
                if shown { peekHintSeen = true }
            }
            .coordinateSpace(name: "review-comparison-space")
            .accessibilityElement(children: comparison.mode == .split ? .contain : .ignore)
            .accessibilityIdentifier("review-image")
            .accessibilityLabel(reviewImageLabel)
            .accessibilityHint(canPeekOriginal ? "Double tap and hold to see the original" : "")
    }

    /// Hold the photo for about 0.3 s to see the original while the finger is
    /// down. View state only: it never selects a comparison mode.
    private var peekGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isPeekingOriginal) {
                (value: SequenceGesture<LongPressGesture, DragGesture>.Value, state: inout Bool, _: inout Transaction) in
                if case .second(true, _) = value { state = true }
            }
    }

    private func beginOriginalPeek() {
        HapticFeedback.play(.selection)
        if reviewOriginalImage == nil, !isPreparingReviewOriginal, !isRenderingReview {
            Task { await onPrepareReviewOriginal() }
        }
    }

    @ViewBuilder
    private func comparisonBadges(width: CGFloat) -> some View {
        let split = comparison.mode == .split
        HStack(alignment: .bottom, spacing: 0) {
            if showsOriginalFrame || (split && comparison.originalFraction >= 0.25) {
                comparisonBadge("Original")
            }
            Spacer(minLength: 0)
            if split && comparison.originalFraction <= 0.75 {
                comparisonBadge(recipe.name)
                    .frame(maxWidth: width * 0.5, alignment: .trailing)
            }
        }
    }

    private func comparisonBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(FilmyTheme.background)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(FilmyTheme.comparison, in: Capsule())
            .overlay { Capsule().strokeBorder(.black, lineWidth: 1) }
            .padding(8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
        if showsOriginalFrame, let reviewOriginalImage {
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
        wide: Bool = false,
        tight: Bool = false
    ) -> some View {
        let usesAccessibleControlStack = dynamicTypeSize.isAccessibilitySize && !compact
        let rowSpacing: CGFloat = tight ? 8 : 10

        return VStack(alignment: .leading, spacing: rowSpacing) {
            if wide && !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 10) {
                    lookPicker
                        .frame(maxWidth: .infinity)
                    comparisonControls
                    finishPicker(stacked: false)
                        .frame(width: 280, alignment: .leading)
                }
            } else if usesAccessibleControlStack {
                // Full-width rows keep accessibility text readable. The review
                // and its actions share a scroll view so every control fits.
                lookPicker
                comparisonControlGroup(stacked: true)
                finishPicker(stacked: true)
            } else if stacked {
                VStack(alignment: .leading, spacing: 10) {
                    lookPicker
                    comparisonControls
                }
            } else {
                // Preserve readable names on small iPhones. Comparison has
                // two explicit actions; it must not squeeze the active look.
                VStack(alignment: .leading, spacing: rowSpacing) {
                    lookPicker
                    if tight {
                        HStack(spacing: 8) {
                            comparisonControls
                            compareRowNote
                        }
                    } else {
                        comparisonControls
                    }
                }
            }

            if (!wide || dynamicTypeSize.isAccessibilitySize) && !usesAccessibleControlStack {
                finishPicker(
                    stacked: stacked || dynamicTypeSize.isAccessibilitySize,
                    showsCaption: !tight
                )
            }

            if !tight && (isRenderingReview || isPreparingReviewOriginal) {
                renderStatusRow
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

    private var renderStatusRow: some View {
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
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review-render-status")
    }

    /// The slot beside Original and Split in the phone portrait layout. It
    /// holds one thing at a time, so the row never changes height.
    @ViewBuilder
    private var compareRowNote: some View {
        if isRenderingReview || isPreparingReviewOriginal {
            renderStatusRow
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if selectedReviewFinish == .instantPrint {
            finishNote
        } else if showsPeekHint {
            peekHint
        } else {
            Spacer(minLength: 0)
        }
    }

    private var finishNote: some View {
        // Short on purpose: the slot beside Original and Split is about 127 pt
        // wide on a 375 pt phone and shrinks at larger text.
        Text("\(finishTitle(selectedReviewFinish)): white border")
            .font(.caption)
            .foregroundStyle(FilmyTheme.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var peekHint: some View {
        Text("Hold photo for original")
            .font(.caption)
            .foregroundStyle(FilmyTheme.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("review-peek-hint")
    }

    private func panelActions(compact: Bool) -> some View {
        VStack(spacing: 10) {
            saveDisclosure()
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

    private func finishPicker(stacked: Bool, showsCaption: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsCaption {
                Text("Finish")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }

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

            if showsCaption && selectedReviewFinish == .instantPrint {
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
        #if G7_APP
        HStack(spacing: 8) {
            Image(systemName: "film")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Look")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.tertiary)
                Text("G7X Compact")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
            }
            Spacer(minLength: 4)
            Image(systemName: "lock.fill")
                .font(.system(.caption2, weight: .bold))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("review-look-locked")
        .accessibilityLabel("G7X Compact look")
        .accessibilityHint("G7X Camera uses one fixed look")
        .frame(maxWidth: .infinity)
        #else
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
        #endif
    }

    private var comparisonControls: some View {
        comparisonControlGroup(stacked: false)
    }

    private func comparisonControlGroup(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
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

    @ViewBuilder
    private func metadataBlock(trailing: Bool = false) -> some View {
        if trailing {
            Label(resolutionCaption, systemImage: "photo")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("review-metadata")
        } else {
            Label(resolutionCaption, systemImage: "photo")
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("review-metadata")
        }
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

    private func saveError(_ message: String, pinned: Bool = false) -> some View {
        let sideBySide = pinned && !saveErrorRequiresSettings && !dynamicTypeSize.isAccessibilitySize
        let layout = sideBySide
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: pinned ? 4 : 10))
        return layout {
            saveErrorMessageLabel(message)
            saveErrorAction
        }
        .id("review-save-error")
        .onAppear { UIAccessibility.post(notification: .announcement, argument: message) }
        .padding(pinned ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmyTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(FilmyTheme.danger.opacity(0.3), lineWidth: 1)
        }
    }

    private func saveErrorMessageLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var saveErrorAction: some View {
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

    private func actionBar(showsDisclosure: Bool) -> some View {
        VStack(spacing: 8) {
            if showsDisclosure {
                saveDisclosure(lineLimit: dynamicTypeSize > .large ? 2 : 1)
            }
            actionButtonRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-action-bar")
    }

    @ViewBuilder
    private var actionButtonRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 10) {
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
            HStack(spacing: 10) {
                retakeButton
                keepFrameButton
            }
        }
    }

    private func saveDisclosure(lineLimit: Int? = nil) -> some View {
        Text(comparison.mode != .look
             ? "Saves \(recipe.name) · \(finishTitle(finish)), not the original preview."
             : isImported
                ? "New copy in Photos. Your original stays unchanged."
                : "Only the finished photo is saved to Photos.")
            .font(.caption)
            .foregroundStyle(FilmyTheme.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(lineLimit)
            .minimumScaleFactor(lineLimit == nil ? 1 : 0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hasUnsavedLookChanges: Bool {
        guard !isImported else { return false }
        return recipe.id != openingRecipeID || finish != openingFinish
    }

    private var retakeButton: some View {
        Button {
            if hasUnsavedLookChanges {
                isConfirmingRetake = true
            } else {
                HapticFeedback.play(.discard)
                onRetake()
            }
        } label: {
            Label(
                isImported ? "Cancel" : "Retake",
                systemImage: isImported ? "xmark" : "arrow.counterclockwise"
            )
        }
        .buttonStyle(.filmySecondary)
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier("review-cancel")
        .disabled(isSaving)
        .confirmationDialog("Discard this photo?", isPresented: $isConfirmingRetake, titleVisibility: .visible) {
            Button("Discard and retake", role: .destructive) {
                HapticFeedback.play(.discard)
                onRetake()
            }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your look and finish choices for this photo will be lost.")
        }
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
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
        }
        .buttonStyle(.filmyPrimary)
        .accessibilityShowsLargeContentViewer()
        .accessibilityIdentifier("review-save")
        .disabled(isSaving || isRenderingReview || isPreparingReviewOriginal)
        // The spoken name starts with the visible word "Save" (label in name).
        .accessibilityLabel(keepFrameAccessibilityLabel)
        .accessibilityInputLabels(["Save", "Save to Photos", "Keep frame", "Save filtered photo"])
        .accessibilityHint("Saves the finished photo to your Photos library")
    }
}
