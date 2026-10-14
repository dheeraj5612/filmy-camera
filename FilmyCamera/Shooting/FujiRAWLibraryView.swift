import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private struct FujiDecodedPreview: @unchecked Sendable { let image: UIImage }

/// Kind filter for the RAW library. Foundation-only so unit tests can call it.
enum FujiOriginalFilter: String, CaseIterable, Identifiable, Sendable {
    case all, raw, sources
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .raw: return "RAW"
        case .sources: return "Source JPEGs"
        }
    }
    func apply(_ records: [FujiOriginalRecord]) -> [FujiOriginalRecord] {
        switch self {
        case .all: return records
        case .raw: return records.filter { $0.isRAW }
        case .sources: return records.filter { !$0.isRAW }
        }
    }
    /// Offered only when the library holds both kinds; otherwise every filter equals All.
    static func isOffered(for records: [FujiOriginalRecord]) -> Bool {
        records.contains { $0.isRAW } && records.contains { !$0.isRAW }
    }
    static func summary(_ records: [FujiOriginalRecord]) -> String {
        let raw: Int = records.filter { $0.isRAW }.count
        let sources: Int = records.count - raw
        return "\(raw) RAW, \(sources) source " + (sources == 1 ? "JPEG" : "JPEGs")
    }
    /// Q-menu tile value: RAW state in words, plus the kept-RAW count once the library holds any.
    static func tileValue(captureRAW: Bool, records: [FujiOriginalRecord]) -> String {
        let state: String = captureRAW ? "On" : "Off"
        let kept: Int = records.filter { $0.isRAW }.count
        return kept == 0 ? state : "\(state) · \(kept) kept"
    }
}

/// Value text for the RAW development sliders, in units. Clamps to the slider range before formatting.
enum FujiRAWSliderFormat: Sendable {
    case exposure, temperature, tint, percent
    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return -5...5
        case .temperature: return 2000...12000
        case .tint: return -150...150
        case .percent: return 0...1
        }
    }
    func text(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "\u{2013}" }
        let v: Double = min(max(value, range.lowerBound), range.upperBound)
        switch self {
        case .exposure:
            let r: Double = (v * 10).rounded() / 10
            let style = FloatingPointFormatStyle<Double>(locale: locale)
                .precision(.fractionLength(1))
                .sign(strategy: .always(includingZero: false))
            return (r == 0 ? 0 : r).formatted(style) + " EV"
        case .temperature:
            let style = FloatingPointFormatStyle<Double>(locale: locale)
                .precision(.fractionLength(0))
                .grouping(.never)
            return v.rounded().formatted(style) + " K"
        case .tint:
            let r: Double = v.rounded()
            let style = FloatingPointFormatStyle<Double>(locale: locale)
                .precision(.fractionLength(0))
                .sign(strategy: .always(includingZero: false))
            return (r == 0 ? 0 : r).formatted(style)
        case .percent:
            let style = FloatingPointFormatStyle<Double>.Percent(locale: locale)
                .precision(.fractionLength(0))
            return ((v * 100).rounded() / 100).formatted(style)
        }
    }
}

/// Icon plus word, so the kind is never carried by colour alone.
private struct FujiOriginalKindBadge: View {
    let isRAW: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRAW ? "camera.aperture" : "photo").accessibilityHidden(true)
            Text(isRAW ? "RAW" : "Source JPEG").lineLimit(1)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(FilmyTheme.primary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(FilmyTheme.panelRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(FilmyTheme.lineStrong, lineWidth: 1))
    }
}

/// Library folders kept on disk whose record.json cannot be read. No delete action; an original with only a missing record can be restored.
private struct FujiUnreadableRow: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        let count: Int = controller.unreadableEntries.count
        let title: String = count == 1 ? "1 capture needs repair" : "\(count) captures need repair"
        let restorable: [FujiUnreadableEntry] = controller.unreadableEntries.filter { $0.collection == "originals" && $0.reason == "missing record.json" }
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("Their files are still on this device but their records cannot be read. Nothing was deleted.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Check again") { Task { await controller.reloadLibrary() } }
                .buttonStyle(.borderless)
                .disabled(controller.isBusy).frame(minHeight: 44)
            ForEach(restorable) { entry in
                let label: String = "Restore capture " + String(entry.id.uuidString.prefix(8))
                Button(label) {
                    Task { await controller.repairOriginal(entry, recipe: viewModel.selectedRecipe) }
                }
                .buttonStyle(.borderless)
                .disabled(controller.isBusy).frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fuji-library-unreadable")
    }
}

struct FujiRAWLibraryView: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    @State private var importing = false
    @State private var reading = false
    @State private var error: String?
    @State private var deletion: FujiOriginalRecord?
    @State private var kindFilter: FujiOriginalFilter = .all
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section {
                Toggle("Capture RAW + developed JPEG", isOn: Binding(get: { controller.settings.captureRAW },
                    set: { controller.change(\.captureRAW, to: $0) })).disabled(controller.settingsLocked)
                Button(reading ? "Reading RAW…" : "Import a RAW file") { importing = true }
                    .frame(minHeight: 44).disabled(reading || controller.isBusy)
                Text("Originals kept here stay on this device, not in Photos or Roll. Development never overwrites their bytes. Export an unchanged original for backup before deleting it or uninstalling Filmy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if controller.pendingExportCount > 0 {
                Section("Recoverable exports") {
                    Button("Retry \(controller.pendingExportCount) Photos saves") { controller.retryExports(photoLibrary: photoLibrary) }
                        .disabled(controller.isBusy).frame(minHeight: 44)
                }
            }
            if !controller.unreadableEntries.isEmpty {
                Section("Needs repair") { FujiUnreadableRow(controller: controller, viewModel: viewModel) }
            }
            if let error { Section { FilmyNoticeLabel(message: error, kind: .error) } }
            if let message = controller.errorMessage { Section { FilmyNoticeLabel(message: message, kind: .error) } }
            originalsSection
        }
        .navigationTitle("RAW develop").navigationBarTitleDisplayMode(.inline)
        .task { await controller.reloadLibrary() }
        .onChange(of: FujiOriginalFilter.isOffered(for: controller.originals)) { _, isOffered in
            if !isOffered { kindFilter = .all }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.rawImage], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                reading = true; error = nil
                Task {
                    defer { reading = false }
                    do { try await controller.importRAW(url, recipe: viewModel.selectedRecipe) }
                    catch { self.error = error.localizedDescription }
                }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("Delete the original from this device?", isPresented: Binding(get: { deletion != nil },
            set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("Delete original permanently", role: .destructive) {
                guard let deletion else { return }
                Task {
                    do { try await controller.deleteOriginal(deletion) }
                    catch { self.error = error.localizedDescription }
                    self.deletion = nil
                }
            }
        } message: { Text("Developed copies in Photos are not deleted. This cannot be undone; export the original first to keep a backup.") }
    }

    @ViewBuilder private var originalsSection: some View {
        let offered: Bool = FujiOriginalFilter.isOffered(for: controller.originals)
        let activeFilter: FujiOriginalFilter = offered ? kindFilter : .all
        let shown: [FujiOriginalRecord] = activeFilter.apply(controller.originals)
        Section {
            if offered {
                Picker("Show", selection: $kindFilter) {
                    ForEach(FujiOriginalFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("fuji-raw-filter")
            }
            if controller.originals.isEmpty {
                ContentUnavailableView("No originals yet", systemImage: "camera.aperture",
                    description: Text("Enable RAW on a supported lens or import a supported RAW file. Failed or retained composite sources also appear here."))
            }
            ForEach(shown) { record in
                NavigationLink {
                    FujiRAWDevelopView(controller: controller, viewModel: viewModel, photoLibrary: photoLibrary, original: record)
                } label: {
                    originalLabel(record)
                }
                .swipeActions {
                    Button("Delete original", role: .destructive) { deletion = record }.disabled(controller.isBusy || controller.isComposing)
                }
            }
        } header: {
            Text("Your originals")
        } footer: {
            if !controller.originals.isEmpty { Text(FujiOriginalFilter.summary(controller.originals)) }
        }
    }

    private func originalLabel(_ record: FujiOriginalRecord) -> some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 6) {
            layout {
                FujiOriginalKindBadge(isRAW: record.isRAW).layoutPriority(1)
                Text(record.dynamicRange.title).font(.caption2.monospaced()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(record.capturedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
            Text(record.recipe.name).font(.headline)
            Text(record.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical, 6)
    }
}

/// Pinned Develop preview height. Pinned only on tall default-text screens; nil keeps the preview inside the Form.
enum FujiDevelopLayout {
    /// 16 padding + 1 divider + 100 save bar worst case.
    static let chromeBudget: CGFloat = 117
    /// Smallest Form viewport worth pinning for.
    static let minimumFormHeight: CGFloat = 320

    static func pinnedPreviewHeight(available: CGFloat, accessibilitySize: Bool) -> CGFloat? {
        guard !accessibilitySize, available.isFinite else { return nil }
        let height: CGFloat = min(340, (available * 0.38).rounded())
        guard available - height - chromeBudget >= minimumFormHeight else { return nil }
        return height
    }
}

struct FujiRAWDevelopView: View {
    @ObservedObject var controller: FujiShootingController
    @ObservedObject var viewModel: CameraViewModel
    @ObservedObject var photoLibrary: PhotoLibraryService
    let original: FujiOriginalRecord
    @State private var draft: FujiOriginalRecord
    @State private var image: UIImage?
    @State private var isRendering = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var originalURL: URL?
    @State private var editingRecipe = false
    @State private var renderGeneration = UUID()
    @State private var savedMessage: String?
    @State private var saveError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(controller: FujiShootingController, viewModel: CameraViewModel, photoLibrary: PhotoLibraryService, original: FujiOriginalRecord) {
        self.controller = controller; self.viewModel = viewModel; self.photoLibrary = photoLibrary; self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            developContent(available: proxy.size.height)
        }
        .navigationTitle("Develop original").navigationBarTitleDisplayMode(.inline)
        .task {
            do { originalURL = try await controller.originalURL(original) }
            catch { self.error = error.localizedDescription }
        }
        .task(id: draft) {
            savedMessage = nil
            saveError = nil
            let generation = UUID(); renderGeneration = generation
            isRendering = true
            do {
                try await Task.sleep(for: .milliseconds(220))
                let data = try await controller.developPreview(draft)
                try Task.checkCancellation()
                let decoded = await ImageDecodeQueue.shared.value { () -> FujiDecodedPreview? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1200,
                            kCGImageSourceShouldCacheImmediately: true
                          ] as CFDictionary) else { return nil }
                    return FujiDecodedPreview(image: UIImage(cgImage: thumbnail))
                }
                try Task.checkCancellation()
                guard generation == renderGeneration else { return }
                guard let decoded else { throw FujiShootingError.processingFailed }
                image = decoded.image; isRendering = false
            } catch is CancellationError {
                if generation == renderGeneration { isRendering = false }
            } catch {
                if generation == renderGeneration { self.error = error.localizedDescription; isRendering = false }
            }
        }
        .onChange(of: savedMessage) { _, new in
            if let new { UIAccessibility.post(notification: .announcement, argument: new) }
        }
        .onChange(of: saveError) { _, new in
            if let new { UIAccessibility.post(notification: .announcement, argument: new) }
        }
        .sheet(isPresented: $editingRecipe) {
            RecipeDetailView(recipe: draft.recipe, originalRecipe: viewModel.originalRecipe(for: draft.recipe.id),
                isSelected: true, onSelect: { editingRecipe = false }, onCancel: { editingRecipe = false },
                onUpdate: { draft.recipe = $0; editingRecipe = false },
                onReset: { draft.recipe = viewModel.originalRecipe(for: draft.recipe.id) })
        }
    }

    private func developContent(available: CGFloat) -> some View {
        let pinned: CGFloat? = FujiDevelopLayout.pinnedPreviewHeight(available: available, accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        return VStack(spacing: 0) {
            if let pinned {
                previewPane(height: pinned)
                    .frame(height: pinned)
                    .padding(.horizontal, FilmyLayout.compactHorizontalMargin)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemGroupedBackground))
                Divider()
            }
            developForm(pinnedHeight: pinned)
        }
    }

    private func previewPane(height: CGFloat?) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: height ?? 340)
                    .accessibilityLabel("RAW development preview")
            } else { Color.clear.frame(height: height ?? 240) }
            if isRendering { ProgressView("Developing preview").padding().background(.regularMaterial, in: Capsule()) }
        }.frame(maxWidth: .infinity)
    }

    private var resetSlidersButton: some View {
        Button {
            draft.adjustment = FujiRAWAdjustment()
        } label: {
            Text("Reset sliders").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .disabled(isSaving || draft.adjustment == FujiRAWAdjustment())
        .accessibilityHint("Returns exposure, white balance and tone to defaults. The original is not changed.")
        .accessibilityIdentifier("fuji-develop-reset")
    }

    private func developForm(pinnedHeight: CGFloat?) -> some View {
        Form {
            Section {
                if pinnedHeight == nil { previewPane(height: nil) }
                Text("\(original.isRAW ? "RAW" : "Processed source") · \(original.dynamicRange.title) · Original unchanged")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                if let exposure = original.captureExposure {
                    let capturedLine = "Captured ISO \(Int(exposure.iso)) · \(FujiMath.shutterText(exposure.seconds)) · protection \(exposure.protectedStops.formatted()) EV"
                    Text(capturedLine)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if let error { FilmyNoticeLabel(message: error, kind: .error) }
                if dynamicTypeSize.isAccessibilitySize {
                    if let saveError { FilmyNoticeLabel(message: saveError, kind: .error) }
                    if let savedMessage { Text(savedMessage).font(.footnote) }
                }
            }
            Section("Development recipe") {
                Picker("Film recipe", selection: Binding(get: { draft.recipe.id }, set: { draft.recipe = viewModel.recipe(for: $0) })) {
                    ForEach(viewModel.recipes) { Text($0.name).tag($0.id) }
                }
                Button("Edit film, tone, grain and color") { editingRecipe = true }.frame(minHeight: 44)
            }
            if original.isRAW {
                Section("RAW exposure and white balance") {
                    control("Exposure", value: $draft.adjustment.exposure, format: .exposure)
                    Toggle("As-shot white balance", isOn: Binding(
                        get: { draft.adjustment.useAsShotWhiteBalance },
                        set: { asShot in
                            draft.adjustment.useAsShotWhiteBalance = asShot
                            let defaults = FujiRAWAdjustment()
                            let untouched = draft.adjustment.temperature == defaults.temperature && draft.adjustment.tint == defaults.tint
                            guard !asShot, untouched else { return }
                            // Start the sliders at the as-shot balance instead of jumping to the 5600 K default.
                            Task {
                                guard let shot = await controller.asShotWhiteBalance(original) else { return }
                                let stillUntouched = draft.adjustment.temperature == defaults.temperature && draft.adjustment.tint == defaults.tint
                                guard !draft.adjustment.useAsShotWhiteBalance, stillUntouched else { return }
                                draft.adjustment.temperature = shot.0; draft.adjustment.tint = shot.1
                            }
                        }))
                    if !draft.adjustment.useAsShotWhiteBalance {
                        control("Temperature", value: $draft.adjustment.temperature, format: .temperature)
                        control("Tint", value: $draft.adjustment.tint, format: .tint)
                    }
                    control("Highlight shoulder", value: $draft.adjustment.highlightRecovery, format: .percent)
                    control("Shadow lift", value: $draft.adjustment.shadowLift, format: .percent)
                    resetSlidersButton
                    FujiHint(short: "Recovers highlight detail the original holds; clipped areas stay clipped.",
                             long: "Highlight development can use information present in the original. It cannot recover sensor-clipped detail. Capture DR protection is fixed by the original exposure, not applied retroactively.",
                             topic: "highlight development", identifier: "fuji-hint-rawDevelop")
                }
            }
            Section {
                if dynamicTypeSize.isAccessibilitySize { saveButton(inBar: false) }
                Button("Revert to saved development") { draft = original }.disabled(isSaving).frame(minHeight: 44)
                if let originalURL {
                    ShareLink(item: originalURL) { Label("Export unchanged original", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                }
                Text("Development settings are stored as a sidecar when you save. Your shooting recipe and C banks are not changed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize { saveBar }
        }
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = saveError ?? savedMessage {
                Label(status, systemImage: saveError == nil ? "checkmark.circle" : "exclamationmark.triangle.fill")
                    .font(.footnote).lineLimit(2)
                    .foregroundStyle(saveError == nil ? FilmyTheme.primary : FilmyTheme.danger)
            }
            saveButton(inBar: true)
        }
        .padding(.horizontal, FilmyLayout.compactHorizontalMargin)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder private func saveButton(inBar: Bool) -> some View {
        let title: String = isSaving ? "Saving development…" : "Save development to Photos"
        if inBar {
            Button(title) { save() }
                .buttonStyle(.filmyPrimary)
                .disabled(isSaving || controller.isBusy)
                .accessibilityIdentifier("fuji-develop-save")
        } else {
            Button { save() } label: {
                Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(isSaving || controller.isBusy)
            .accessibilityIdentifier("fuji-develop-save")
        }
    }

    private func save() {
        error = nil; saveError = nil; savedMessage = nil
        isSaving = true
        let snapshot = draft
        Task {
            defer { isSaving = false }
            do {
                try await controller.saveDevelopment(snapshot, photoLibrary: photoLibrary)
                if snapshot == draft { savedMessage = "Saved a developed copy. Original unchanged." }
            } catch is CancellationError {
                self.saveError = "Development canceled. The original is unchanged."
            } catch { self.saveError = error.localizedDescription }
        }
    }

    private func control(_ title: String, value: Binding<Double>, format: FujiRAWSliderFormat) -> some View {
        let text: String = format.text(value.wrappedValue)
        return VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(text).monospacedDigit() }
            Slider(value: value, in: format.range).accessibilityLabel(title).accessibilityValue(text)
        }
    }
}
