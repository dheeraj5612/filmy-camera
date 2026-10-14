import Combine
import Photos
import SwiftUI
import UIKit

/// The Roll: a contact sheet of every frame kept with Filmy Camera. Three
/// square columns run nearly edge to edge so the frames, not the chrome, fill
/// the screen.
struct GalleryScreen: View {
    @ObservedObject var photoLibrary: PhotoLibraryService
    let onBackToCamera: () -> Void
    var onImportPhoto: (() -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedAsset: PhotoLibraryGalleryAsset?
    @AppStorage("rollRoomyGrid") private var roomyGrid = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layoutModel = GalleryLayoutModel.empty
    @State private var assetsByID: [String: PhotoLibraryGalleryAsset] = [:]
    @State private var lookFilter: String?
    @State private var isSelecting = false
    @State private var rollSelection = GallerySelection()
    @State private var pendingDeleteIDs: [String] = []
    @State private var isShowingDeleteConfirmation = false
    @State private var isWorking = false
    @State private var batchShareURLs: [URL] = []
    @State private var isShowingBatchShare = false
    @State private var shareNote: String?
    @State private var batchMessage: String?
    // Read-only count and list of Capture modes results. The engine is lazy and
    // this read-only library never touches it.
    @StateObject private var capturesModel = CaptureModesModel(recipe: FilmRecipe.builtIns[0], recipes: [], mode: .photo)
    @State private var isShowingCaptures = false

    /// Three columns on iPhone; iPad widths flow as many ~200pt squares as
    /// fit so the contact sheet does not become three enormous tiles.
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: roomyGrid ? 240 : 168, maximum: roomyGrid ? 360 : 240), spacing: 6)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: roomyGrid || dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        observedContent
            .sheet(isPresented: $isShowingBatchShare, onDismiss: finishBatchShare) {
                ShareSheet(items: batchShareURLs)
                    .presentationDetents([.medium, .large])
            }
            .alert(deleteAlertTitle, isPresented: $isShowingDeleteConfirmation) {
                Button(deleteAlertButtonTitle, role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteAlertMessage)
            }
            .alert("Roll action incomplete", isPresented: batchMessageBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(batchMessage ?? "Try again in a moment.")
            }
            .fullScreenCover(isPresented: detailPresentedBinding) {
                detailPager
            }
    }

    private var batchMessageBinding: Binding<Bool> {
        Binding(
            get: { batchMessage != nil },
            set: { if !$0 { batchMessage = nil } }
        )
    }

    private var detailPresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedAsset != nil },
            set: { if !$0 { selectedAsset = nil } }
        )
    }

    private var pagerVisibleIDs: Set<String>? {
        lookFilter == nil ? nil : Set(layoutModel.visibleIDs)
    }

    private var detailPager: some View {
        GalleryPager(
            selection: $selectedAsset,
            photoLibrary: photoLibrary,
            visibleIDs: pagerVisibleIDs,
            onBackToCamera: onBackToCamera
        )
        .ignoresSafeArea()
        .presentationBackground(.black)
    }

    private var observedContent: some View {
        rootContent
            .task {
                // Keep the Roll useful without prompting for broad Photos read
                // access. It displays frames created by Filmy Camera and its
                // private local fallback cache.
                photoLibrary.refresh()
                capturesModel.refresh()
                rebuildModel()
            }
            .onAppear { rebuildModel() }
            .onChange(of: galleryRebuildKey) { _, _ in
                rebuildModel()
            }
            .onChange(of: photoLibrary.metadataByAssetIdentifier.count) { _, _ in
                rebuildModel()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                photoLibrary.refresh()
                capturesModel.refresh()
                clearSelectionIfUnavailable()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                rebuildModel()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in
                rebuildModel()
            }
            .onChange(of: photoLibrary.authorizationStatus) { _, _ in
                clearSelectionIfUnavailable()
            }
            .onChange(of: photoLibrary.assets.map(\.localIdentifier)) { _, _ in
                clearSelectionIfUnavailable()
            }
            .onChange(of: photoLibrary.localSavedFrames.map(\.assetIdentifier)) { _, _ in
                clearSelectionIfUnavailable()
            }
    }

    private var rootContent: some View {
        NavigationStack {
            ZStack {
                FilmyPageBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        rollHeading
                            .padding(.horizontal, FilmyTheme.pageMargin)

                        if captureCount > 0 {
                            rollCapturesRow
                        }

                        if usesStackedImport && !photoLibrary.galleryAssets.isEmpty {
                            stackedImportButton
                        }

                        if !photoLibrary.galleryAssets.isEmpty {
                            rollHeaderRows
                        }

                        galleryContent

                        if photoLibrary.galleryAssets.isEmpty {
                            startShootingButton
                                .padding(.horizontal, FilmyTheme.pageMargin)
                                .accessibilityIdentifier("roll-start-shooting")
                                .accessibilityHint("Returns to the camera without changing Photos permissions")
                            if usesStackedImport {
                                stackedImportButton
                            }
                            originalsLink
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                rollTopBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    selectionBar
                        .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await photoLibrary.refreshAndWait()
            }
        }
        .sheet(isPresented: $isShowingCaptures, onDismiss: {
            capturesModel.errorMessage = nil
            capturesModel.refresh()
        }) {
            CaptureModesLibrary(model: capturesModel, readOnly: true)
        }
    }

    private var captureCount: Int { capturesModel.captures.count }

    private var usesStackedImport: Bool {
        dynamicTypeSize.isAccessibilitySize && onImportPhoto != nil
    }

    /// Camera and Import share the pinned bar. Accessibility sizes keep the
    /// plain Camera bar and move Import into the page (stackedImportButton).
    @ViewBuilder
    private var rollTopBar: some View {
        if dynamicTypeSize.isAccessibilitySize || onImportPhoto == nil {
            CameraReturnBar(accessibilityIdentifier: "roll-back-to-camera", action: onBackToCamera)
        } else {
            ViewThatFits(in: .horizontal) {
                rollBarRow(iconOnlyImport: false)
                rollBarRow(iconOnlyImport: true)
            }
            .padding(.horizontal, FilmyTheme.pageMargin)
            .padding(.vertical, 6)
            .background(FilmyTheme.background)
        }
    }

    private func rollBarRow(iconOnlyImport: Bool) -> some View {
        HStack(spacing: 8) {
            BackToCameraButton(accessibilityIdentifier: "roll-back-to-camera", action: onBackToCamera)
            Spacer(minLength: 8)
            importCapsule(iconOnly: iconOnlyImport)
        }
    }

    private func importCapsule(iconOnly: Bool) -> some View {
        Button {
            HapticFeedback.play(.selection)
            onImportPhoto?()
        } label: {
            importCapsuleLabel(iconOnly: iconOnly)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .padding(.horizontal, 12)
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.toolControlHeight)
                .background(FilmyTheme.panel.opacity(0.94), in: Capsule())
                .overlay {
                    Capsule().stroke(FilmyTheme.lineStrong, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import photo")
        .accessibilityInputLabels(["Import", "Import photo"])
        .accessibilityHint("Choose a photo and apply the current film recipe")
        .accessibilityIdentifier("roll-import-photo")
    }

    @ViewBuilder
    private func importCapsuleLabel(iconOnly: Bool) -> some View {
        if iconOnly {
            Image(systemName: "photo.badge.plus")
        } else {
            Label("Import", systemImage: "photo.badge.plus")
        }
    }

    private var stackedImportButton: some View {
        Button {
            HapticFeedback.play(.selection)
            onImportPhoto?()
        } label: {
            Label("Import photo", systemImage: "photo.badge.plus")
        }
        .buttonStyle(.filmySecondary)
        .accessibilityLabel("Import photo")
        .accessibilityInputLabels(["Import", "Import photo"])
        .accessibilityHint("Choose a photo and apply the current film recipe")
        .accessibilityIdentifier("roll-import-photo")
        .padding(.horizontal, FilmyTheme.pageMargin)
    }

    private var rollCapturesRow: some View {
        Button {
            HapticFeedback.play(.selection)
            capturesModel.errorMessage = nil
            isShowingCaptures = true
        } label: {
            HStack(spacing: 6) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "square.stack")
                        .accessibilityHidden(true)
                }
                Text("Captures")
                Text("\(captureCount)")
                    .monospacedDigit()
                    .foregroundStyle(FilmyTheme.accent)
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, 12)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .background(FilmyTheme.panel, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Captures")
        .accessibilityValue(captureCount == 1 ? "1 item" : "\(captureCount) items")
        .accessibilityHint("Photos, videos and panoramas saved from Capture modes")
        .accessibilityIdentifier("roll-open-captures")
        .padding(.horizontal, FilmyTheme.pageMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rollSummary: some View {
        HStack(spacing: 8) {
            rollSourceSummary
            Spacer(minLength: 8)
            layoutToggleButton
        }
    }

    private var rollSourceSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
            Text("Newest first")
            Text("·")
            Text(archiveSourceLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(FilmyTheme.secondary)
        .accessibilityElement(children: .contain)
    }

    private var layoutToggleButton: some View {
        Button {
            HapticFeedback.play(.selection)
            roomyGrid.toggle()
        } label: {
            Image(systemName: roomyGrid ? "square.grid.3x3" : "square.grid.2x2")
                .font(.system(.subheadline).weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .frame(width: 48, height: 48)
                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("roll-grid-layout")
        .accessibilityLabel("Change Roll layout")
        .accessibilityValue(roomyGrid ? "Roomy grid" : "Contact sheet")
    }

    private var rollHeading: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text("Roll")
                .font(.system(.title, design: .default).weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            if !photoLibrary.galleryAssets.isEmpty {
                Text("\(photoLibrary.galleryAssets.count) frames")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The camera route stays primary only when there is no access action above it.
    private var emptyRollHasAccessAction: Bool {
        switch photoLibrary.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var startShootingButton: some View {
        if emptyRollHasAccessAction {
            Button(action: onBackToCamera) {
                Label("Make your first frame", systemImage: "camera")
            }
            .buttonStyle(.filmySecondary)
        } else {
            Button(action: onBackToCamera) {
                Label("Make your first frame", systemImage: "camera")
            }
            .buttonStyle(.filmyPrimary)
        }
    }

    private var originalsLink: some View {
        NavigationLink {
            FilmyOriginalsView(photoLibrary: photoLibrary)
        } label: {
            HStack(spacing: 8) {
                Label("Filmy originals · edit again", systemImage: "photo.stack")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(FilmyTheme.accent)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
            .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, FilmyTheme.pageMargin)
        .accessibilityIdentifier("roll-filmy-originals")
    }

    private var showsFilterRow: Bool {
        layoutModel.looks.count >= 2 || lookFilter != nil
    }

    /// Phone sizes fold the sort, source, Select and layout controls into one
    /// row; accessibility sizes keep the stacked rows.
    @ViewBuilder
    private var rollHeaderRows: some View {
        if dynamicTypeSize.isAccessibilitySize {
            rollSummary
                .padding(.horizontal, FilmyTheme.pageMargin)
            if showsFilterRow {
                filterRow
            }
            selectionControls
                .padding(.horizontal, FilmyTheme.pageMargin)
            originalsLink
        } else {
            rollControlRow
                .padding(.horizontal, FilmyTheme.pageMargin)
            if showsFilterRow {
                filterRow
            }
            if isSelecting {
                selectionStatusRow
                    .padding(.horizontal, FilmyTheme.pageMargin)
            } else {
                if !controlsSummary.isEmpty {
                    rollCountLine
                        .padding(.horizontal, FilmyTheme.pageMargin)
                }
                originalsLink
            }
        }
    }

    /// Neither candidate depends on `isSelecting`, so entering select mode never
    /// switches layout and Done sits exactly where Select was.
    private var rollControlRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                rollSourceSummary
                Spacer(minLength: 0)
                selectToggleButton
                layoutToggleButton
            }
            VStack(alignment: .leading, spacing: 8) {
                rollSummary
                HStack {
                    Spacer(minLength: 0)
                    selectToggleButton
                }
            }
        }
    }

    /// The hidden "Select" fixes the width, so the frame is the same in both modes.
    private var selectToggleButton: some View {
        Button(action: toggleSelectionMode) {
            Text("Select")
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(isSelecting ? "Done" : "Select")
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.accent)
                .padding(.horizontal, 6)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelecting ? "Done" : "Select")
        .accessibilityIdentifier("roll-select-toggle")
    }

    private var selectAllButton: some View {
        controlButton(
            title: rollSelection.isAllSelected(in: layoutModel.visibleIDs) ? "Deselect all" : "Select all",
            identifier: "roll-select-all",
            action: toggleSelectAll
        )
    }

    private var rollCountLine: some View {
        Text(controlsSummary)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("roll-count-summary")
    }

    /// Takes the Originals slot in select mode, so the grid does not move.
    private var selectionStatusRow: some View {
        HStack(spacing: 12) {
            rollCountLine
            Spacer(minLength: 8)
            selectAllButton
        }
        .frame(minHeight: FilmyTheme.minimumHitTarget)
    }

    /// Ids plus source: a cached/Photos swap keeps the id but changes what the
    /// grid may offer (delete), so it must rebuild the lookup too.
    private var galleryRebuildKey: [String] {
        photoLibrary.galleryAssets.map { asset in
            asset.isPhotosAsset ? "\(asset.id)|p" : "\(asset.id)|c"
        }
    }

    private var archiveSourceLabel: String {
        let assets = photoLibrary.galleryAssets
        let hasPhotosAssets = assets.contains(where: \.isPhotosAsset)
        let hasCachedAssets = assets.contains(where: { !$0.isPhotosAsset })

        switch (hasPhotosAssets, hasCachedAssets) {
        case (true, true):
            return "Photos and local cache"
        case (true, false):
            return photoLibrary.authorizationStatus == .limited ? "Limited Photos access" : "Photos"
        case (false, true):
            return "Local cache"
        case (false, false):
            return "No source"
        }
    }

    /// Keeps the open detail sheet pointed at the entry the Roll currently
    /// lists for that frame. An authorization change can swap a Photos asset
    /// for its cached fallback (or back); the sheet must follow that swap
    /// rather than keep loading a source that is no longer available.
    private func clearSelectionIfUnavailable() {
        guard let selectedAsset else { return }
        guard let current = photoLibrary.galleryAssets.first(where: { $0.id == selectedAsset.id }) else {
            // The pager coordinator lands on the neighbouring frame (or
            // dismisses when nothing is left); clearing here would close the
            // pager before it can.
            if photoLibrary.galleryAssets.isEmpty {
                self.selectedAsset = nil
            }
            return
        }
        if current.isPhotosAsset != selectedAsset.isPhotosAsset {
            self.selectedAsset = current
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        switch photoLibrary.authorizationStatus {
        case .authorized, .notDetermined:
            if photoLibrary.galleryAssets.isEmpty {
                if photoLibrary.authorizationStatus == .notDetermined {
                    RollEmptyState(
                        systemName: "photo.badge.plus",
                        title: "Give your roll a home",
                        message: "Allow photo access to show the frames you have made with Filmy Camera.",
                        actionTitle: "Allow Photos access",
                        action: requestReadAccess,
                        actionHint: "Shows the system Photos permission prompt"
                    )
                    .padding(.horizontal, FilmyTheme.pageMargin)
                } else {
                    RollEmptyState(
                        systemName: "photo.on.rectangle.angled",
                        title: "Your frames will live here",
                        message: "Photos you take with Filmy Camera save here automatically. You can also import and edit a photo."
                    )
                    .padding(.horizontal, FilmyTheme.pageMargin)
                }
            } else if photoLibrary.authorizationStatus == .notDetermined {
                VStack(alignment: .leading, spacing: 14) {
                    readAccessNotice
                        .padding(.horizontal, FilmyTheme.pageMargin)
                    galleryGrid
                }
            } else {
                galleryGrid
            }
        case .limited:
            VStack(alignment: .leading, spacing: 14) {
                if photoLibrary.galleryAssets.isEmpty {
                    RollEmptyState(
                        systemName: "photo.on.rectangle.angled",
                        title: "Your selected roll is empty",
                        message: "Filmy Camera can only show frames saved by Filmy Camera that you allow it to read."
                    )
                    .padding(.horizontal, FilmyTheme.pageMargin)
                } else {
                    galleryGrid
                }
                limitedAccessControl
                    .padding(.horizontal, FilmyTheme.pageMargin)
            }
        case .denied, .restricted:
            if photoLibrary.galleryAssets.isEmpty {
                RollEmptyState(
                    systemName: "lock.slash",
                    title: "Photo access is off",
                    message: "Enable Photos access in Settings to see your saved frames.",
                    heroLabel: nil,
                    actionTitle: "Open Settings",
                    action: openSystemSettings,
                    actionHint: "Opens Filmy Camera Photos permissions in Settings"
                )
                .padding(.horizontal, FilmyTheme.pageMargin)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    archiveAccessNotice
                        .padding(.horizontal, FilmyTheme.pageMargin)
                    galleryGrid
                }
            }
        @unknown default:
            RollEmptyState(
                systemName: "photo",
                title: "Gallery unavailable",
                message: "Filmy Camera could not read the photo library right now."
            )
            .padding(.horizontal, FilmyTheme.pageMargin)
        }
    }

    private var limitedAccessControl: some View {
        Button {
            photoLibrary.presentLimitedLibraryPicker()
        } label: {
            HStack(spacing: 12) {
                SettingIcon(systemName: "checkmark.circle", tint: FilmyTheme.mint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage access to saved frames")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                    Text("Choose which frames the Roll can see")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityHint("Choose which saved Filmy Camera frames can be viewed in the Roll")
        .accessibilityIdentifier("gallery-manage-limited-access")
    }

    // MARK: Model

    /// Builds the day sections and look counts once per change, never per
    /// body pass.
    private func rebuildModel() {
        let assets = photoLibrary.galleryAssets
        var byID: [String: PhotoLibraryGalleryAsset] = [:]
        var items: [GalleryItem] = []
        items.reserveCapacity(assets.count)
        for asset in assets {
            byID[asset.id] = asset
            items.append(galleryItem(for: asset))
        }
        let calendar = Calendar.current
        var model = GalleryLayoutModel(items: items, lookFilter: lookFilter, calendar: calendar)
        if let filter = lookFilter, !model.looks.contains(where: { $0.name == filter }) {
            lookFilter = nil
            model = GalleryLayoutModel(items: items, lookFilter: nil, calendar: calendar)
        }
        assetsByID = byID
        layoutModel = model
        rollSelection.prune(keeping: Set(byID.keys))
        if assets.isEmpty { isSelecting = false }
    }

    private func galleryItem(for asset: PhotoLibraryGalleryAsset) -> GalleryItem {
        GalleryItem(
            id: asset.id,
            date: photoLibrary.galleryCaptureDate(for: asset),
            lookName: photoLibrary.metadata(for: asset)?.recipe.name
        )
    }

    private func animated(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.18)) { change() }
        }
    }

    private func setLookFilter(_ name: String?) {
        guard name != lookFilter else { return }
        HapticFeedback.play(.selection)
        animated {
            lookFilter = name
            rebuildModel()
            rollSelection.prune(keeping: Set(layoutModel.visibleIDs))
        }
    }

    // MARK: Filter chips

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    title: "All",
                    count: layoutModel.totalCount,
                    isSelected: lookFilter == nil,
                    identifier: "roll-filter-all"
                ) { setLookFilter(nil) }
                ForEach(layoutModel.looks) { look in
                    filterChip(
                        title: look.name,
                        count: look.count,
                        isSelected: lookFilter == look.name,
                        identifier: "roll-filter-\(look.name)"
                    ) { setLookFilter(look.name) }
                }
            }
            .padding(.horizontal, FilmyTheme.pageMargin)
        }
    }

    private func filterChip(
        title: String,
        count: Int,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        let background: Color = isSelected ? FilmyTheme.accent : FilmyTheme.panel
        let foreground: Color = isSelected ? FilmyTheme.background : FilmyTheme.primary
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        return Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .background(background, in: Capsule())
                .overlay { Capsule().strokeBorder(FilmyTheme.line, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(count == 1 ? "1 photo" : "\(count) photos")
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier(identifier)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.largeTitle)
                .foregroundStyle(FilmyTheme.secondary)
                .accessibilityHidden(true)
            Text("No frames with this look")
                .font(.system(.title3, design: .default).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .multilineTextAlignment(.center)
            Text("Show the whole roll to see every frame again.")
                .font(.subheadline)
                .foregroundStyle(FilmyTheme.secondary)
                .multilineTextAlignment(.center)
            Button("Show all") { setLookFilter(nil) }
                .buttonStyle(.filmyPrimary)
                .accessibilityIdentifier("roll-filter-show-all")
        }
        .frame(maxWidth: .infinity)
        .padding(FilmyTheme.pageMargin)
        .accessibilityElement(children: .contain)
    }

    // MARK: Selection controls

    private var selectionControls: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        let stacked = dynamicTypeSize.isAccessibilitySize
        return layout {
            if !stacked || !controlsSummary.isEmpty {
                Text(controlsSummary)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roll-count-summary")
            }
            if !stacked {
                Spacer(minLength: 8)
            }
            selectionControlButtons
        }
    }

    /// One `HStack` so the buttons stay on a single row when the summary stacks above them.
    private var selectionControlButtons: some View {
        HStack(spacing: 12) {
            if isSelecting {
                controlButton(
                    title: rollSelection.isAllSelected(in: layoutModel.visibleIDs) ? "Deselect all" : "Select all",
                    identifier: "roll-select-all",
                    action: toggleSelectAll
                )
            }
            controlButton(
                title: isSelecting ? "Done" : "Select",
                identifier: "roll-select-toggle",
                action: toggleSelectionMode
            )
        }
    }

    private var controlsSummary: String {
        if isSelecting {
            return rollSelection.count == 1 ? "1 selected" : "\(rollSelection.count) selected"
        }
        if lookFilter != nil {
            return "Showing \(layoutModel.visibleIDs.count) of \(layoutModel.totalCount) frames"
        }
        return ""
    }

    private func controlButton(title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.accent)
                .padding(.horizontal, 6)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func toggleSelectionMode() {
        HapticFeedback.play(.selection)
        animated {
            isSelecting.toggle()
            rollSelection.clear()
        }
    }

    private func toggleSelectAll() {
        animated {
            if rollSelection.isAllSelected(in: layoutModel.visibleIDs) {
                rollSelection.clear()
            } else {
                rollSelection.selectAll(layoutModel.visibleIDs)
            }
        }
    }

    private var selectionBar: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        let selectedIDs = rollSelection.ordered(in: layoutModel.visibleIDs)
        let canDeleteAny = selectedIDs.contains { id in
            assetsByID[id].map { photoLibrary.canDelete(asset: $0) } ?? false
        }
        return layout {
            Button {
                shareAssets(selectedIDs.compactMap { assetsByID[$0] })
            } label: {
                Label(selectedIDs.isEmpty ? "Share" : "Share \(selectedIDs.count)", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.filmySecondary)
            .disabled(selectedIDs.isEmpty || isWorking)
            .accessibilityLabel("Share selected frames")
            .accessibilityValue(selectedIDs.count == 1 ? "1 frame" : "\(selectedIDs.count) frames")
            .accessibilityIdentifier("roll-selection-share")

            Button(role: .destructive) {
                requestDelete(selectedIDs)
            } label: {
                Label(selectedIDs.isEmpty ? "Delete" : "Delete \(selectedIDs.count)", systemImage: "trash")
            }
            .buttonStyle(.filmySecondary)
            .disabled(selectedIDs.isEmpty || !canDeleteAny || isWorking)
            .accessibilityLabel("Delete selected frames")
            .accessibilityValue(selectedIDs.count == 1 ? "1 frame" : "\(selectedIDs.count) frames")
            .accessibilityIdentifier("roll-selection-delete")
        }
        .padding(.horizontal, FilmyTheme.pageMargin)
        .padding(.vertical, 10)
        .background(FilmyTheme.backgroundRaised.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(FilmyTheme.line).frame(height: 1)
        }
    }

    // MARK: Batch actions

    private var deleteAlertTitle: String {
        pendingDeleteIDs.count == 1 ? "Delete 1 frame?" : "Delete \(pendingDeleteIDs.count) frames?"
    }

    private var deleteAlertButtonTitle: String {
        pendingDeleteIDs.count == 1 ? "Delete 1 Frame" : "Delete \(pendingDeleteIDs.count) Frames"
    }

    private var deleteAlertMessage: String {
        pendingDeleteIDs.count == 1
            ? "Removes it from Photos and your Roll. Photos may ask you to confirm once more."
            : "Removes them from Photos and your Roll. Photos may ask you to confirm once more."
    }

    /// Only frames the service allows to delete are offered for deletion.
    private func requestDelete(_ ids: [String]) {
        guard !isWorking else {
            batchMessage = "Another Roll action is still running. Try again in a moment."
            return
        }
        let deletable = ids.filter { id in
            assetsByID[id].map { photoLibrary.canDelete(asset: $0) } ?? false
        }
        guard !deletable.isEmpty else {
            batchMessage = "These frames can’t be deleted from the Roll."
            return
        }
        pendingDeleteIDs = deletable
        isShowingDeleteConfirmation = true
    }

    @MainActor
    private func deleteResult(of assets: [PhotoLibraryGalleryAsset]) async -> Result<Void, PhotoLibraryServiceError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, PhotoLibraryServiceError>, Never>) in
            photoLibrary.delete(assets: assets) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Deletes the confirmed frames with one service call (one system
    /// prompt). On failure nothing is removed and the selection stays.
    private func performDelete() {
        let targets = pendingDeleteIDs.compactMap { assetsByID[$0] }
        guard !isWorking else { return }
        guard !targets.isEmpty else {
            pendingDeleteIDs = []
            // Let the confirmation alert finish dismissing before the second
            // alert is requested, or the system can drop it.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                batchMessage = "These frames are no longer in the Roll."
            }
            return
        }
        isWorking = true
        Task { @MainActor in
            let result = await deleteResult(of: targets)
            isWorking = false
            pendingDeleteIDs = []
            switch result {
            case .success:
                let deletedNote = targets.count == 1 ? "Deleted 1 frame" : "Deleted \(targets.count) frames"
                UIAccessibility.post(notification: .announcement, argument: deletedNote)
                HapticFeedback.play(.success)
                animated {
                    isSelecting = false
                    rollSelection.clear()
                }
            case .failure(.cancelled):
                break
            case .failure(let error):
                HapticFeedback.play(.error)
                let count = targets.count
                let summary = count == 1
                    ? "This frame could not be deleted."
                    : "\(count) frames could not be deleted and are still selected."
                batchMessage = "\(summary) \(error.localizedDescription)"
            }
        }
    }

    private func shareAssets(_ assets: [PhotoLibraryGalleryAsset]) {
        guard !isWorking, !assets.isEmpty else { return }
        isWorking = true
        Task { @MainActor in
            var urls: [URL] = []
            for asset in assets {
                if let url = await photoLibrary.shareURL(for: asset) { urls.append(url) }
            }
            isWorking = false
            guard !urls.isEmpty else {
                batchMessage = "The original frames could not be prepared for sharing. Try again in a moment."
                return
            }
            let missing = assets.count - urls.count
            shareNote = missing > 0 ? "\(missing) of \(assets.count) frames could not be prepared and were not shared." : nil
            batchShareURLs = urls
            isShowingBatchShare = true
        }
    }

    private func finishBatchShare() {
        for url in batchShareURLs {
            photoLibrary.removeTemporaryShare(at: url)
        }
        batchShareURLs = []
        if let note = shareNote {
            shareNote = nil
            Task { @MainActor in batchMessage = note }
        }
    }

    // MARK: Sectioned grid

    @ViewBuilder
    private var galleryGrid: some View {
        if layoutModel.sections.isEmpty && lookFilter != nil {
            filteredEmptyState
        } else {
            sectionedGrid
        }
    }

    private var sectionedGrid: some View {
        LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
            ForEach(layoutModel.sections) { section in
                Section {
                    sectionGrid(section)
                } header: {
                    sectionHeader(section)
                }
            }
        }
    }

    private func sectionGrid(_ section: GallerySection) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(section.ids, id: \.self) { id in
                thumbnailCell(id: id)
            }
        }
        .padding(.horizontal, 6)
    }

    private func sectionHeader(_ section: GallerySection) -> some View {
        let title = GallerySectionTitle.title(
            for: section.day,
            now: Date(),
            calendar: Calendar.current,
            locale: Locale.current
        )
        return Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(FilmyTheme.primary)
            .padding(.horizontal, FilmyTheme.pageMargin)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FilmyTheme.background.opacity(0.92))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func thumbnailCell(id: String) -> some View {
        if let asset = assetsByID[id] {
            thumbnailButton(asset)
        }
    }

    private func thumbnailButton(_ asset: PhotoLibraryGalleryAsset) -> some View {
        let isSelected = rollSelection.contains(asset.id)
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        let hint = isSelecting ? "Toggles selection" : "Opens frame details"
        return Button {
            if isSelecting {
                animated { rollSelection.toggle(asset.id) }
            } else {
                selectedAsset = asset
            }
        } label: {
            GalleryThumbnail(asset: asset, photoLibrary: photoLibrary)
                .overlay {
                    if isSelecting {
                        selectionOverlay(isSelected: isSelected)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu { contextMenuItems(for: asset) }
        .accessibilityLabel(
            photoLibrary.metadata(for: asset).map {
                "Photo in your gallery, \($0.recipe.name)"
            } ?? "Photo in your gallery"
        )
        .accessibilityValue("\(asset.pixelWidth)x\(asset.pixelHeight)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("roll-frame-\(asset.id)")
    }

    private func selectionOverlay(isSelected: Bool) -> some View {
        let dim: Color = isSelected ? Color.black.opacity(0.28) : Color.clear
        return ZStack(alignment: .topTrailing) {
            dim
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? FilmyTheme.accent : Color.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(8)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func contextMenuItems(for asset: PhotoLibraryGalleryAsset) -> some View {
        Button {
            shareAssets([asset])
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if photoLibrary.canDelete(asset: asset) {
            Button(role: .destructive) {
                requestDelete([asset.id])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        if let name = photoLibrary.metadata(for: asset)?.recipe.name {
            Button {
                setLookFilter(name)
            } label: {
                Label("Show only this look", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private var archiveAccessNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingIcon(systemName: "lock.open")

            VStack(alignment: .leading, spacing: 6) {
                Text("Showing saved frames only")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text("Enable Photos read access to refresh this roll from your library.")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Photos Settings", action: openSystemSettings)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                    .accessibilityIdentifier("gallery-photos-permission-settings")
                    .accessibilityHint("Opens Filmy Camera Photos permissions")
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(FilmyTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.accent.opacity(0.26), lineWidth: 1)
        }
    }

    private var readAccessNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingIcon(systemName: "lock.open")

            VStack(alignment: .leading, spacing: 6) {
                Text("Showing saved frames only")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.primary)
                Text("Allow Photos access to refresh this roll and delete frames from your library.")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Allow Photos access", action: requestReadAccess)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .frame(minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                    .accessibilityIdentifier("gallery-photos-permission-request")
                    .accessibilityHint("Shows the system Photos permission prompt")
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(FilmyTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.accent.opacity(0.26), lineWidth: 1)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestReadAccess() {
        Task { _ = await photoLibrary.requestAccessIfNeeded() }
    }
}

private struct GalleryThumbnail: View {
    let asset: PhotoLibraryGalleryAsset
    @ObservedObject var photoLibrary: PhotoLibraryService

    @State private var image: UIImage?
    @State private var imageLoadFailed = false

    private var imageRequestKey: PhotoLibraryImageRequestKey {
        PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: asset.assetIdentifier,
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        )
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if imageLoadFailed {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 18, weight: .medium))
                        Text("Unavailable")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(FilmyTheme.secondary)
                } else {
                    FilmyTheme.panel
                        .overlay {
                            ProgressView()
                                .tint(FilmyTheme.accent)
                                .scaleEffect(0.8)
                        }
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let metadata = photoLibrary.metadata(for: asset) {
                    Text(metadata.recipe.name)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .task(id: imageRequestKey) {
                image = nil
                imageLoadFailed = false
                guard PhotoLibraryGalleryImagePolicy.canLoad(
                    isPhotosAsset: asset.isPhotosAsset,
                    authorizationStatus: photoLibrary.authorizationStatus
                ) else {
                    imageLoadFailed = true
                    return
                }

                let loadedImage = await photoLibrary.image(
                    for: asset,
                    targetSize: CGSize(width: 400, height: 400)
                )
                guard !Task.isCancelled else { return }
                image = loadedImage
                imageLoadFailed = loadedImage == nil
            }
    }
}

private struct RollEmptyState: View {
    let systemName: String
    let title: String
    let message: String
    var heroLabel: String? = "NO FRAMES YET"
    var actionTitle: String?
    var action: (() -> Void)?
    var actionHint: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sampleRecipes: [FilmRecipe] {
        Array(FilmRecipe.builtIns.prefix(3))
    }

    /// With an action the card is a short prompt: one symbol, no sample swatches.
    private var hasAction: Bool {
        actionTitle != nil && action != nil
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    FilmyTheme.backgroundRaised

                    if hasAction {
                        Image(systemName: systemName)
                            .font(.system(.title, design: .default).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(width: 72, height: 72)
                            .background(FilmyTheme.accent.opacity(0.14), in: Circle())
                    } else {
                        HStack(spacing: -22) {
                            ForEach(Array(sampleRecipes.enumerated()), id: \.element.id) { index, recipe in
                                RecipeSwatch(recipe: recipe, compact: true, showsLabel: false)
                                    .frame(width: 92, height: 62)
                                    .rotationEffect(.degrees(Double(index - 1) * 7))
                                    .offset(y: index == 1 ? -6 : 4)
                                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                                    .zIndex(index == 1 ? 1 : 0)
                            }
                        }
                        .opacity(0.9)

                        VStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: systemName)
                                    .font(.system(size: 11, weight: .bold))
                                if let heroLabel {
                                    Text(heroLabel)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .tracking(1.2)
                                }
                            }
                            .foregroundStyle(FilmyTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(FilmyTheme.accent.opacity(0.14), in: Capsule())
                            .padding(.bottom, 12)
                        }
                    }
                }
                .frame(height: hasAction ? 112 : 150)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: FilmyTheme.cornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: FilmyTheme.cornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if dynamicTypeSize.isAccessibilitySize {
                            actionControl
                        }
                        Text(message)
                            .font(.system(.subheadline, design: .default).weight(.medium))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !dynamicTypeSize.isAccessibilitySize {
                        actionControl
                    }
                }
                .padding(18)
            }
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .buttonStyle(.filmyPrimary)
                .accessibilityHint(actionHint ?? "")
        }
    }
}

/// Whether the viewer bars are hidden. One instance per pager presentation,
/// so the state survives paging and resets when the viewer reopens.
private final class GalleryChromeState: ObservableObject {
    @Published var isHidden = false
}

/// UIKit owns the interactive horizontal slide and cancellation physics.
/// Selection changes only after a completed transition, not during a drag.
private struct GalleryPager: UIViewControllerRepresentable {
    @Binding var selection: PhotoLibraryGalleryAsset?
    @ObservedObject var photoLibrary: PhotoLibraryService
    /// Restricts paging to the frames the Roll currently shows (look filter).
    let visibleIDs: Set<String>?
    let onBackToCamera: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 16]
        )
        pager.view.backgroundColor = .black
        pager.view.accessibilityIdentifier = "gallery-pager"
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        context.coordinator.pager = pager
        context.coordinator.synchronize(with: self)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.synchronize(with: self)
    }

    static func dismantleUIViewController(_ pager: UIPageViewController, coordinator: Coordinator) {
        pager.dataSource = nil
        pager.delegate = nil
        coordinator.pages.removeAll()
        coordinator.pager = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: GalleryPager
        let chrome = GalleryChromeState()
        weak var pager: UIPageViewController?
        var pages: [String: GalleryPageController] = [:]
        private var assets: [PhotoLibraryGalleryAsset] = []
        private var indices: [String: Int] = [:]
        private var isTransitioning = false
        private var needsSynchronization = false
        private var activeID: String?
        /// Identifiers of the list last shown successfully; the reference for
        /// choosing a neighbour once the selected frame disappears.
        private var settledIDs: [String] = []

        init(parent: GalleryPager) { self.parent = parent }

        func synchronize(with parent: GalleryPager) {
            self.parent = parent
            guard let pager else { return }
            guard !isTransitioning else {
                needsSynchronization = true
                return
            }
            needsSynchronization = false
            guard let selection = parent.selection else {
                pages.removeAll()
                activeID = nil
                return
            }
            let previousIDs = settledIDs
            refreshSnapshot()
            var target = selection
            if indices[target.id] == nil {
                // The selected frame disappeared (deleted, or the Photos
                // source changed). Land on the next surviving frame, else the
                // previous one; dismiss only when nothing is left to show.
                let replacementID = GalleryRemovalPolicy.replacementID(
                    removedID: target.id,
                    previousIDs: previousIDs,
                    currentIDs: assets.map(\.id)
                )
                // A second pass can run before the deferred selection write
                // lands, when `previousIDs` no longer contains the removed
                // frame. Fall back to the page already landed on.
                var landedID = replacementID
                if landedID == nil, let activeID {
                    // The landed frame may itself have vanished since.
                    landedID = assets.contains(where: { $0.id == activeID })
                        ? activeID
                        : GalleryRemovalPolicy.replacementID(
                            removedID: activeID,
                            previousIDs: previousIDs,
                            currentIDs: assets.map(\.id)
                        )
                }
                guard let landedID, let replacement = assets.first(where: { $0.id == landedID }) else {
                    pages.removeAll()
                    setSelectionDeferred(nil)
                    return
                }
                target = replacement
                setSelectionDeferred(replacement)
            }
            guard let index = indices[target.id] else { return }
            let current = pager.viewControllers?.first as? GalleryPageController
            if current?.assetIdentifier != target.id {
                pager.setViewControllers([page(at: index)], direction: .forward, animated: false)
            }
            finishSelection(at: index)
        }

        /// A binding write during `updateUIViewController` would change state
        /// mid view update, so it lands on the next main-actor turn.
        private func setSelectionDeferred(_ asset: PhotoLibraryGalleryAsset?) {
            let binding = parent.$selection
            Task { @MainActor in binding.wrappedValue = asset }
        }

        private func refreshSnapshot() {
            let all = parent.photoLibrary.galleryAssets
            if let visibleIDs = parent.visibleIDs {
                assets = all.filter { visibleIDs.contains($0.id) }
            } else {
                assets = all
            }
            indices = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($0.element.id, $0.offset) })
        }

        private func detail(for asset: PhotoLibraryGalleryAsset) -> GalleryDetailView {
            GalleryDetailView(
                asset: asset,
                photoLibrary: parent.photoLibrary,
                visibleIDs: parent.visibleIDs,
                chrome: chrome,
                onBackToCamera: parent.onBackToCamera,
                onClose: { [weak self] in self?.parent.selection = nil },
                onZoomChanged: { [weak self] zoomed in
                    guard let self,
                          (self.pager?.viewControllers?.first as? GalleryPageController)?.assetIdentifier == asset.id else { return }
                    self.pager?.view.subviews.compactMap { $0 as? UIScrollView }.forEach {
                        $0.isScrollEnabled = !zoomed
                    }
                },
                onPreviousPhoto: { [weak self] in self?.move(by: -1) },
                onNextPhoto: { [weak self] in self?.move(by: 1) }
            )
        }

        private func page(at index: Int) -> GalleryPageController {
            let asset = assets[index]
            if let existing = pages[asset.id] { return existing }
            let controller = GalleryPageController(assetIdentifier: asset.id, rootView: detail(for: asset))
            controller.view.backgroundColor = .black
            controller.view.accessibilityElementsHidden = true
            pages[asset.id] = controller
            return controller
        }

        private func adjacent(to controller: UIViewController, offset: Int) -> UIViewController? {
            guard let controller = controller as? GalleryPageController,
                  let index = indices[controller.assetIdentifier],
                  let next = GalleryPagingPolicy.neighbor(of: index, offset: offset, count: assets.count) else { return nil }
            return page(at: next)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? {
            adjacent(to: controller, offset: -1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? {
            adjacent(to: controller, offset: 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isTransitioning = false
            _ = finished
            _ = completed
            let currentID = (pageViewController.viewControllers?.first as? GalleryPageController)?.assetIdentifier
            synchronizeSelectionAfterTransition(currentID: currentID)
        }

        private func move(by offset: Int) {
            guard !isTransitioning, let pager,
                  let current = pager.viewControllers?.first as? GalleryPageController,
                  let index = indices[current.assetIdentifier],
                  let next = GalleryPagingPolicy.neighbor(of: index, offset: offset, count: assets.count) else { return }
            isTransitioning = true
            pager.setViewControllers(
                [page(at: next)], direction: offset > 0 ? .forward : .reverse,
                animated: !UIAccessibility.isReduceMotionEnabled
            ) { [weak self] finished in
                guard let self else { return }
                self.isTransitioning = false
                _ = finished
                let currentID = (self.pager?.viewControllers?.first as? GalleryPageController)?.assetIdentifier
                self.synchronizeSelectionAfterTransition(currentID: currentID)
            }
        }

        private func synchronizeSelectionAfterTransition(currentID: String?) {
            guard pager != nil else { return }
            refreshSnapshot()
            if let currentID,
               let current = assets.first(where: { $0.id == currentID }) {
                // Resolve the completed page against the latest Photos
                // snapshot. This avoids selecting an asset at a stale index
                // when the source changed while the transition was running.
                parent.selection = current
            } else if let selection = parent.selection,
                      let current = assets.first(where: { $0.id == selection.id }) {
                parent.selection = current
            }
            // A selection that no longer exists is resolved by synchronize,
            // which picks a neighbour or dismisses.
            synchronize(with: parent)
        }

        private func finishSelection(at index: Int) {
            let currentID = assets[index].id
            settledIDs = assets.map(\.id)
            if activeID != currentID {
                pager?.view.subviews.compactMap { $0 as? UIScrollView }.forEach { $0.isScrollEnabled = true }
                activeID = currentID
            }
            let retainedIDs = Set(GalleryPagingPolicy.retainedIndices(around: index, count: assets.count).map { assets[$0].id })
            pages = pages.filter { retainedIDs.contains($0.key) }
            for (id, controller) in pages {
                // Rebuild every retained page from the latest asset. Photos
                // authorization and source changes can replace the backing
                // image while the page controller itself remains cached.
                if let asset = assets.first(where: { $0.id == id }) {
                    controller.rootView = detail(for: asset)
                }
                controller.view.accessibilityElementsHidden = id != currentID
            }
            pager?.view.accessibilityValue = "\(index + 1) of \(assets.count)"
        }
    }
}

@MainActor
private final class GalleryPageController: UIHostingController<GalleryDetailView> {
    let assetIdentifier: String

    init(assetIdentifier: String, rootView: GalleryDetailView) {
        self.assetIdentifier = assetIdentifier
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(assetIdentifier:rootView:)") }
}

private struct GalleryDetailView: View {
    let asset: PhotoLibraryGalleryAsset
    @ObservedObject var photoLibrary: PhotoLibraryService
    let visibleIDs: Set<String>?
    @ObservedObject var chrome: GalleryChromeState
    let onBackToCamera: () -> Void

    let onClose: () -> Void
    let onZoomChanged: (Bool) -> Void
    let onPreviousPhoto: () -> Void
    let onNextPhoto: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var imageLoadFailed = false
    @State private var loadGeneration = 0
    @State private var retryGeneration = 0
    @State private var shareURL: URL?
    @State private var isShowingShareSheet = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var actionErrorMessage: String?
    @State private var zoomScale: CGFloat = 1
    @State private var pinchBaseZoom: CGFloat?
    @State private var imageOffset: CGSize = .zero
    @State private var dragBaseOffset: CGSize = .zero
    @State private var dragStartedZoomed = false
    @State private var isDraggingFrame = false
    @State private var shareGeneration = 0
    @State private var isShowingInfo = false

    /// The frames the pager walks: the Roll, narrowed by the look filter.
    private var pagedAssets: [PhotoLibraryGalleryAsset] {
        let all = photoLibrary.galleryAssets
        guard let visibleIDs else { return all }
        return all.filter { visibleIDs.contains($0.id) }
    }

    private var imageRequestKey: PhotoLibraryImageRequestKey {
        PhotoLibraryGalleryImagePolicy.requestKey(
            assetIdentifier: asset.assetIdentifier,
            isPhotosAsset: asset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                frameContent(in: proxy.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(frameDragGesture(in: proxy.size))
            .clipped()
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: zoomScale) { _, scale in onZoomChanged(scale > 1) }
        .onChange(of: voiceOverEnabled || switchControlEnabled) { _, assistive in
            if assistive { chrome.isHidden = false }
        }
        .onDisappear { onZoomChanged(false) }
        .accessibilityAction(named: "Previous photo") {
            guard !isPagingLocked else { return }
            onPreviousPhoto()
        }
        .accessibilityAction(named: "Next photo") {
            guard !isPagingLocked else { return }
            onNextPhoto()
        }
        .task(id: imageTaskID) {
            await loadImage()
        }
        .onDisappear {
            shareGeneration &+= 1
            if !isShowingShareSheet, let shareURL {
                photoLibrary.removeTemporaryShare(at: shareURL)
                self.shareURL = nil
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            viewerChrome(detailToolbar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            viewerChrome(bottomChrome)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(photoLibrary.metadata(for: asset).map { "Selected gallery photo, \($0.recipe.name)" } ?? "Selected gallery photo")
        .sheet(isPresented: $isShowingShareSheet, onDismiss: {
            if let shareURL {
                photoLibrary.removeTemporaryShare(at: shareURL)
            }
            shareURL = nil
        }) {
            if let shareURL {
                ShareSheet(items: [shareURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert(
            "Delete this frame?",
            isPresented: $isShowingDeleteConfirmation,
        ) {
            Button("Delete Frame", role: .destructive) {
                deleteFrame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it from Photos and your Roll. Photos may ask you to confirm once more.")
        }
        .alert(
            "Couldn’t update frame",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Try again in a moment.")
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if pagedAssets.count > 1 {
                pagingControls
            }
            if let metadata = photoLibrary.metadata(for: asset) {
                metadataCard(metadata)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    /// Controls stay visible for the failed state (Close, Try Again) and for
    /// VoiceOver or Switch Control, which must never lose them.
    private var chromeVisible: Bool {
        !chrome.isHidden || imageLoadFailed || voiceOverEnabled || switchControlEnabled
    }

    private func toggleChrome() {
        if voiceOverEnabled || switchControlEnabled {
            chrome.isHidden = false
            return
        }
        chrome.isHidden.toggle()
    }

    /// Hidden bars keep their size, so the photo never refits or moves; a tap
    /// where a bar was brings the controls back.
    private func viewerChrome<Content: View>(_ content: Content) -> some View {
        content
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)
            .background {
                if !chromeVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { chrome.isHidden = false }
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: chromeVisible)
    }

    @ViewBuilder
    private func frameContent(in viewport: CGSize) -> some View {
        if let image {
            let fittedSize = fittedImageSize(for: image.size, in: viewport)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fittedSize.width, height: fittedSize.height)
                .padding(.vertical, 20)
                .scaleEffect(zoomScale)
                .offset(constrainedOffset(imageOffset, in: viewport))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .accessibilityLabel("Photo")
                .accessibilityValue(zoomScale > 1 ? "Zoomed \(Int(zoomScale * 100)) percent" : "Fit to screen")
                .accessibilityHint("Pinch or double tap to zoom.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        zoomScale = min(zoomScale + 0.5, 4)
                    case .decrement:
                        zoomScale = max(zoomScale - 0.5, 1)
                    @unknown default:
                        break
                    }
                    if zoomScale == 1 {
                        resetImageTransform()
                    } else {
                        imageOffset = constrainedOffset(imageOffset, in: viewport)
                        dragBaseOffset = imageOffset
                    }
                }
                .accessibilityAction(named: "Reset zoom", resetImageTransform)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            dragStartedZoomed = true
                            let baseZoom = pinchBaseZoom ?? zoomScale
                            if pinchBaseZoom == nil { pinchBaseZoom = zoomScale }
                            zoomScale = min(max(baseZoom * value, 1), 4)
                            if zoomScale == 1 {
                                imageOffset = .zero
                                dragBaseOffset = .zero
                            } else {
                                imageOffset = constrainedOffset(imageOffset, in: viewport)
                            }
                        }
                        .onEnded { _ in
                            pinchBaseZoom = nil
                            if zoomScale <= 1.05 {
                                resetImageTransform()
                            } else {
                                imageOffset = constrainedOffset(imageOffset, in: viewport)
                                dragBaseOffset = imageOffset
                            }
                        }
                )
                .gesture(
                    SpatialTapGesture(count: 2)
                        .exclusively(before: SpatialTapGesture())
                        .onEnded { value in
                            switch value {
                            case .first(let tap):
                                toggleZoom(at: tap.location, in: viewport)
                            case .second:
                                toggleChrome()
                            }
                        }
                )
        } else if imageLoadFailed {
            VStack(spacing: 14) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(FilmyTheme.secondary)
                Eyebrow(text: "FRAME COULDN’T LOAD")
                Button("Try Again") {
                    // Keep the bars up while the reload runs; the failure
                    // state that forced them visible clears at load start.
                    chrome.isHidden = false
                    retryGeneration &+= 1
                }
                    .buttonStyle(.filmyPrimary)
                    .disabled(isLoadingImage)
                    .accessibilityIdentifier("gallery-image-retry")
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(FilmyTheme.accent)
                Eyebrow(text: "DEVELOPING FRAME")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { toggleChrome() }
        }
    }

    private var isNavigationLocked: Bool {
        isDeleting || isPreparingShare || isShowingShareSheet || isShowingDeleteConfirmation
    }

    private var isPagingLocked: Bool {
        isNavigationLocked || zoomScale > 1.001 || pinchBaseZoom != nil
    }

    private var pagingControls: some View {
        HStack(spacing: 16) {
            Button { moveFrame(.previous) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous frame")
            .accessibilityIdentifier("gallery-previous-frame")
            .disabled(adjacentAsset(.previous) == nil || isNavigationLocked)

            Text("\(currentFrameNumber) of \(pagedAssets.count)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 80)
                .accessibilityLabel("Frame")
                .accessibilityValue("\(currentFrameNumber) of \(pagedAssets.count)")
                .accessibilityIdentifier("gallery-frame-position")

            Button { moveFrame(.next) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next frame")
            .accessibilityIdentifier("gallery-next-frame")
            .disabled(adjacentAsset(.next) == nil || isNavigationLocked)
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .viewfinderChrome(Capsule())
    }

    private var currentFrameNumber: Int {
        pagedAssets.firstIndex(where: { $0.id == asset.id }).map { $0 + 1 } ?? 0
    }

    private func adjacentAsset(_ direction: GalleryPagingDirection) -> PhotoLibraryGalleryAsset? {
        let assets = pagedAssets
        guard let target = GalleryPagingPolicy.targetIdentifier(
            in: assets.map(\.id), selectedIdentifier: asset.id, direction: direction
        ) else { return nil }
        return assets.first(where: { $0.id == target })
    }

    private func moveFrame(_ direction: GalleryPagingDirection) {
        guard !isNavigationLocked, adjacentAsset(direction) != nil else { return }
        // Reset only the presentation transform before paging. This keeps a
        // cached page fit when the user returns to it, while leaving its
        // loaded image intact if the pager rejects or cancels the move.
        resetImageTransform()
        switch direction {
        case .previous:
            onPreviousPhoto()
        case .next:
            onNextPhoto()
        }
        HapticFeedback.play(.selection)
    }

    private func frameDragGesture(in viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isNavigationLocked else { return }
                if !isDraggingFrame {
                    dragStartedZoomed = zoomScale > 1 || pinchBaseZoom != nil
                    isDraggingFrame = true
                }
                if zoomScale > 1 || pinchBaseZoom != nil { dragStartedZoomed = true }
                guard zoomScale > 1 else { return }
                imageOffset = constrainedOffset(
                    CGSize(
                        width: dragBaseOffset.width + value.translation.width,
                        height: dragBaseOffset.height + value.translation.height
                    ),
                    in: viewport
                )
            }
            .onEnded { value in
                defer {
                    dragStartedZoomed = false
                    isDraggingFrame = false
                }
                dragBaseOffset = imageOffset
                guard !dragStartedZoomed, !isNavigationLocked,
                      let direction = GalleryPagingPolicy.swipeDirection(
                        translation: value.translation,
                        viewportWidth: viewport.width,
                        zoomScale: zoomScale
                      ) else { return }
                moveFrame(direction)
            }
    }

    private var imageTaskID: String {
        "\(imageRequestKey.assetIdentifier)|\(imageRequestKey.authorizationStatusRawValue ?? -1)|\(retryGeneration)"
    }

    /// Cached frames have no Delete; say why. Accessibility sizes carry the
    /// note in Frame info only, so the card never grows there.
    private var cachedFrameNote: String? {
        if asset.isPhotosAsset || dynamicTypeSize.isAccessibilitySize { return nil }
        return dynamicTypeSize > .large ? "Local copy kept in Filmy." : "Local copy kept in Filmy. Share to send or save it."
    }

    private func metadataCard(_ metadata: SavedFrameMetadata) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RecipeSwatch(recipe: metadata.recipe, compact: true, showsLabel: false)
                .frame(width: 52, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata.recipe.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(metadata.capturedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                if let cachedFrameNote {
                    Text(cachedFrameNote)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Text(zoomScale > 1 ? "\(Int(zoomScale * 100))%" : "FIT")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.72))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .viewfinderChrome(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gallery-frame-metadata")
    }

    private var detailToolbar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                toolbarTwoRows
            } else {
                ViewThatFits(in: .horizontal) {
                    toolbarSingleRow
                    toolbarTwoRows
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .sheet(isPresented: $isShowingInfo) {
            GalleryInfoSheet(rows: infoRows)
                .presentationDetents([.medium])
        }
    }

    private var toolbarSingleRow: some View {
        HStack(spacing: 10) {
            toolbarLeadingControls
            Spacer()
            toolbarTrailingControls
        }
    }

    private var toolbarTwoRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                toolbarLeadingControls
            }
            HStack(spacing: 10) {
                Spacer()
                toolbarTrailingControls
            }
        }
    }

    @ViewBuilder
    private var toolbarLeadingControls: some View {
        FilmyIconButton(systemName: "xmark", accessibilityLabel: "Close frame") {
            onClose()
        }

        BackToCameraButton(accessibilityIdentifier: "frame-back-to-camera") {
            onClose()
            onBackToCamera()
        }
    }

    @ViewBuilder
    private var toolbarTrailingControls: some View {
        FilmyIconButton(systemName: "info.circle", accessibilityLabel: "Frame info") {
            isShowingInfo = true
        }
        .accessibilityIdentifier("gallery-info-frame")

        Button {
            shareFrame()
        } label: {
            Group {
                if isPreparingShare {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
            .background { ChromeShapeBackground(shape: Circle()) }
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Share frame")
        .accessibilityIdentifier("gallery-share-frame")
        .disabled(image == nil || isDeleting || isPreparingShare)

        if photoLibrary.canDelete(asset: asset) {
            Button {
                isShowingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FilmyTheme.danger)
                    .frame(width: FilmyTheme.minimumHitTarget, height: FilmyTheme.minimumHitTarget)
                    .background { ChromeShapeBackground(shape: Circle()) }
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Delete frame")
            .accessibilityIdentifier("gallery-delete-frame")
            .disabled(isDeleting || isPreparingShare)
        }
    }

    private var infoRows: [GalleryInfo.Row] {
        var rows = GalleryInfo.rows(
            capturedAt: photoLibrary.galleryCaptureDate(for: asset),
            lookName: photoLibrary.metadata(for: asset)?.recipe.name,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            calendar: .current,
            locale: .current
        )
        if !asset.isPhotosAsset {
            rows.append(GalleryInfo.Row(title: "Storage", value: "Local copy kept in Filmy. Share to send or save it."))
        }
        return rows
    }

    private func deleteFrame() {
        isDeleting = true
        photoLibrary.delete(asset: asset) { result in
            isDeleting = false
            switch result {
            case .success:
                // The pager Coordinator sees the frame disappear and lands on
                // the next (else previous) frame, or dismisses when none is
                // left, so nothing else is needed here.
                break
            case .failure(.cancelled):
                break
            case .failure(let error):
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func shareFrame() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        shareGeneration &+= 1
        let generation = shareGeneration
        let sharingAsset = asset
        let requestKey = imageRequestKey
        Task { @MainActor in
            let url = await photoLibrary.shareURL(for: sharingAsset)
            guard generation == shareGeneration,
                  requestKey == imageRequestKey else {
                if let url { photoLibrary.removeTemporaryShare(at: url) }
                isPreparingShare = false
                return
            }
            isPreparingShare = false
            guard let url else {
                actionErrorMessage = "The original frame could not be prepared for sharing. Try again in a moment."
                return
            }
            shareURL = url
            isShowingShareSheet = true
        }
    }

    /// Each request is stamped with a generation so a replacement load (a
    /// new request key while one is in flight) always supersedes the older
    /// one instead of being rejected by it.
    private func loadImage() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let loadingAsset = asset
        let requestKey = imageRequestKey

        image = nil
        imageLoadFailed = false
        isLoadingImage = true
        resetImageTransform()

        guard PhotoLibraryGalleryImagePolicy.canLoad(
            isPhotosAsset: loadingAsset.isPhotosAsset,
            authorizationStatus: photoLibrary.authorizationStatus
        ) else {
            isLoadingImage = false
            imageLoadFailed = true
            return
        }

        let loadedImage = await photoLibrary.image(
            for: loadingAsset,
            targetSize: CGSize(width: 1600, height: 2200),
            contentMode: .aspectFit
        )
        guard generation == loadGeneration, requestKey == imageRequestKey,
              !Task.isCancelled else { return }

        image = loadedImage
        imageLoadFailed = loadedImage == nil
        isLoadingImage = false
    }

    private func resetImageTransform() {
        var transaction = Transaction()
        transaction.animation = reduceMotion
            ? nil
            : .spring(response: 0.28, dampingFraction: 0.82)
        // A nil animation does not override every animation inherited from a
        // parent transaction. Disable animations explicitly for Reduce Motion
        // so double-tap, VoiceOver, and pinch resets all behave consistently.
        transaction.disablesAnimations = reduceMotion

        withTransaction(transaction) {
            zoomScale = 1
            pinchBaseZoom = nil
            imageOffset = .zero
            dragBaseOffset = .zero
        }
    }

    /// Double tap from fit zooms to 200 percent around the tap; from a zoomed
    /// state it resets. Uses only the pinch state, so paging stays locked
    /// while zoomed through the existing `onChange(of: zoomScale)`.
    private func toggleZoom(at location: CGPoint, in viewport: CGSize) {
        guard zoomScale <= 1 else {
            resetImageTransform()
            return
        }
        let target: CGFloat = 2
        let raw = CGSize(
            width: -(location.x - viewport.width / 2) * (target - 1),
            height: -(location.y - viewport.height / 2) * (target - 1)
        )
        let offset = constrainedOffset(raw, in: viewport, zoom: target)
        var transaction = Transaction()
        transaction.animation = reduceMotion
            ? nil
            : .spring(response: 0.28, dampingFraction: 0.82)
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) {
            zoomScale = target
            pinchBaseZoom = nil
            imageOffset = offset
            dragBaseOffset = offset
        }
    }

    /// Keep at least part of a zoomed image in the viewport. Without this
    /// bound, a long drag could move a frame completely offscreen and leave
    /// the detail sheet looking empty until the user reset zoom.
    private func constrainedOffset(_ offset: CGSize, in viewport: CGSize) -> CGSize {
        constrainedOffset(offset, in: viewport, zoom: zoomScale)
    }

    private func constrainedOffset(_ offset: CGSize, in viewport: CGSize, zoom: CGFloat) -> CGSize {
        // `scaledToFit` receives the viewport after the 20pt vertical padding
        // on each side. Use that actual fitted image size: a portrait or
        // panoramic frame has empty margins in one axis and should not be
        // allowed to drift out of view as though it filled the whole sheet.
        let fittedSize = fittedImageSize(for: image?.size ?? viewport, in: viewport)
        let paddedSize = CGSize(width: fittedSize.width, height: fittedSize.height + 40)
        let maxX = max(0, (paddedSize.width * zoom - viewport.width) / 2)
        let maxY = max(0, (paddedSize.height * zoom - viewport.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func fittedImageSize(for imageSize: CGSize, in viewport: CGSize) -> CGSize {
        let availableImageSize = CGSize(
            width: max(viewport.width, 1),
            height: max(viewport.height - 40, 1)
        )
        let fitScale = min(
            availableImageSize.width / max(imageSize.width, 1),
            availableImageSize.height / max(imageSize.height, 1)
        )
        return CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )
    }
}

fileprivate extension PhotoLibraryService {
    /// Same source order the service sorts by: recorded capture time, then
    /// the Photos creation date. Cached frames without metadata have none.
    func galleryCaptureDate(for asset: PhotoLibraryGalleryAsset) -> Date? {
        if let capturedAt = metadata(for: asset)?.capturedAt { return capturedAt }
        if case .photos(let photo) = asset { return photo.creationDate }
        return nil
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad presents activity sheets as popovers. Give UIKit a stable,
        // centered anchor so sharing never crashes or chooses an off-screen
        // source when the detail view is opened from a narrow split view.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(
                x: controller.view.bounds.midX,
                y: controller.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
