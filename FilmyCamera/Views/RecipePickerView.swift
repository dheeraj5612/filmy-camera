import Foundation
import SwiftUI

/// The film-strip rail. Each tile is a renderer-backed swatch with the recipe
/// name beneath it, so choosing a recipe reads like choosing a film stock.
struct RecipePickerView: View {
    let recipes: [FilmRecipe]
    @Binding var selectedRecipeID: String
    let onOpenDetail: (FilmRecipe) -> Void
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        recipes: [FilmRecipe],
        selectedRecipeID: Binding<String>,
        onOpenDetail: @escaping (FilmRecipe) -> Void,
        compact: Bool = false
    ) {
        self.recipes = recipes
        _selectedRecipeID = selectedRecipeID
        self.onOpenDetail = onOpenDetail
        self.compact = compact
    }

    private var swatchSize: CGSize {
        if compact {
            return CGSize(width: 108, height: 64)
        }
        // Regular widths (iPad) have room for a slightly larger swatch.
        return horizontalSizeClass == .regular
            ? CGSize(width: 122, height: 78)
            : CGSize(width: 98, height: 64)
    }

    private var tileSpacing: CGFloat {
        compact ? 10 : 12
    }

    /// Compact tiles keep the name inside the swatch; standard tiles add a
    /// caption beneath. Both stay well under the camera chrome's budget.
    private var railHeight: CGFloat {
        compact ? swatchSize.height + 12 : swatchSize.height + 36
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(recipes) { recipe in
                        recipeButton(for: recipe)
                            .id(recipe.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 4, for: .scrollContent)
            .frame(height: railHeight)
            .onAppear {
                proxy.scrollTo(selectedRecipeID, anchor: .center)
            }
            .onChange(of: selectedRecipeID) { _, newValue in
                if reduceMotion {
                    proxy.scrollTo(newValue, anchor: .center)
                } else {
                    withAnimation(.snappy(duration: 0.24)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .accessibilityIdentifier("recipe-rail")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe-picker")
        .accessibilityLabel("Film recipe picker. Swipe left or right to browse looks.")
    }

    private func recipeButton(for recipe: FilmRecipe) -> some View {
        let isSelected = selectedRecipeID == recipe.id

        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                selectedRecipeID = recipe.id
            }
        } label: {
            recipeTile(recipe)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recipe-\(recipe.id)")
        .accessibilityLabel("\(recipe.name), \(recipe.descriptor)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select this look. Use the View recipe details action for more information.")
        .accessibilityAction(named: "View recipe details") {
            onOpenDetail(recipe)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button {
                onOpenDetail(recipe)
            } label: {
                Label("View recipe details", systemImage: "info.circle")
            }
        }
    }

    private func recipeTile(_ recipe: FilmRecipe) -> some View {
        let isSelected = selectedRecipeID == recipe.id

        return VStack(spacing: 7) {
            RecipeSwatch(
                recipe: recipe,
                isSelected: isSelected,
                compact: compact,
                showsLabel: compact
            )
            .frame(width: swatchSize.width, height: swatchSize.height)
            .shadow(
                color: isSelected ? FilmyTheme.accent.opacity(0.38) : Color.black.opacity(0.35),
                radius: isSelected ? 10 : 6,
                y: 3
            )

            if !compact {
                Text(recipe.name)
                    .font(.system(size: 12, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? FilmyTheme.accent : Color.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: swatchSize.width + 6)
            }
        }
        .opacity(isSelected ? 1 : 0.84)
        .scaleEffect(isSelected ? 1 : 0.94)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isSelected)
    }
}

enum RecipeDetailCommitAction: Equatable {
    case none
    case update(FilmRecipe)
    case reset
}

enum RecipeDetailCommitPolicy {
    static func action(
        draft: FilmRecipe,
        current: FilmRecipe,
        original: FilmRecipe
    ) -> RecipeDetailCommitAction {
        guard draft != current else { return .none }
        if draft == original { return .reset }
        return .update(draft)
    }
}

struct RecipeDetailView: View {
    private enum EditorSection: String, CaseIterable, Identifiable {
        case tone
        case color
        case texture
        case finish

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tone: return "Tone"
            case .color: return "Color"
            case .texture: return "Texture"
            case .finish: return "Finish"
            }
        }

        var detail: String {
            switch self {
            case .tone: return "Exposure, contrast, and dynamic range"
            case .color: return "Saturation, white balance, and chrome"
            case .texture: return "Sharpness, clarity, and noise"
            case .finish: return "Grain, vignette, and halation"
            }
        }

        var symbol: String {
            switch self {
            case .tone: return "sun.max"
            case .color: return "paintpalette"
            case .texture: return "square.grid.3x3"
            case .finish: return "sparkles"
            }
        }
    }

    let recipe: FilmRecipe
    let originalRecipe: FilmRecipe
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdate: ((FilmRecipe) -> Void)?
    let onReset: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: FilmRecipe
    @State private var expandedSections: Set<EditorSection> = [.tone, .color]

    init(
        recipe: FilmRecipe,
        originalRecipe: FilmRecipe,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onUpdate: ((FilmRecipe) -> Void)? = nil,
        onReset: (() -> Void)? = nil
    ) {
        self.recipe = recipe
        self.originalRecipe = originalRecipe
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onUpdate = onUpdate
        self.onReset = onReset
        _draft = State(initialValue: recipe)
    }

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    identity
                    controlSummary

                    if recipe.filmBase == .compactDigital {
                        compactDigitalProfileCard
                    }

                    if onUpdate != nil {
                        editor
                    }

                    if publicReferenceEntry != nil {
                        publicReferenceCard
                    }

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "camera.aperture")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(width: 24, height: 24)

                        Text("Original camera-inspired looks, interpreted for Filmy Camera. Results vary with light, exposure, and the device camera.")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(FilmyTheme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: FilmyLayout.readableMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("recipe-detail-scroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primaryAction
                .frame(maxWidth: FilmyLayout.readableMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .background(FilmyTheme.background.opacity(0.75))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FilmyTheme.line)
                        .frame(height: 1)
                }
        }
        .accessibilityElement(children: .contain)
    }

    private var primaryAction: some View {
        Button {
            commitDraft()
            HapticFeedback.play(.success)
            onSelect()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: primaryActionIcon)
                Text(primaryActionTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.filmyPrimary)
        .accessibilityLabel(primaryActionAccessibilityLabel)
        .accessibilityHint(
            hasPendingChanges
                ? "Applies pending changes and returns to the camera"
                : "Returns to the camera"
        )
    }

    private var hasPendingChanges: Bool {
        draft != recipe
    }

    private var primaryActionTitle: String {
        if isSelected {
            return hasPendingChanges ? "Apply to Selected Recipe" : "Done"
        }
        return "Use This Recipe"
    }

    private var primaryActionIcon: String {
        if isSelected {
            return hasPendingChanges ? "checkmark.circle" : "checkmark.circle.fill"
        }
        return "camera.fill"
    }

    private var primaryActionAccessibilityLabel: String {
        if isSelected {
            return hasPendingChanges
                ? "Apply changes to \(recipe.name)"
                : "\(recipe.name) is selected"
        }
        return "Use \(recipe.name) recipe"
    }

    private var detailGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var hero: some View {
        RecipeSwatch(recipe: draft, compact: false, showsLabel: false)
            .frame(maxWidth: .infinity)
            .frame(height: 236)
            .overlay {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.74)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Eyebrow(
                            text: recipe.filmBase == .compactDigital
                                ? "COMPACT PROFILE · \(recipe.filmBase.officialName.uppercased())"
                                : recipe.filmBase.officialName.uppercased(),
                            color: FilmyTheme.accent
                        )

                        if isSelected {
                            FilmyTag(text: "ACTIVE")
                        }

                        if draft != originalRecipe {
                            FilmyTag(text: "EDITED", filled: false)
                        }
                    }

                    Text(recipe.name)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(recipe.descriptor)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        isSelected ? FilmyTheme.accent.opacity(0.6) : FilmyTheme.lineStrong,
                        lineWidth: 1
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(recipe.name). \(recipe.descriptor). Reference \(recipe.filmBase.officialName)")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.detail)
                .font(FilmyTheme.bodyFont)
                .foregroundStyle(FilmyTheme.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(
                    recipe.filmBase == .compactDigital
                        ? "Camera profile · \(recipe.filmBase.officialName)"
                        : "Camera reference · \(recipe.filmBase.officialName)"
                )
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FilmyTheme.accent)
        }
    }

    private var compactDigitalProfileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FilmyTheme.background)
                    .frame(width: 36, height: 36)
                    .background(FilmyTheme.accent, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "G7 X PROFILE", color: FilmyTheme.accent)
                    Text("Dedicated compact-digital pipeline")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                }
            }

            LazyVGrid(
                columns: detailGridColumns,
                alignment: .leading,
                spacing: 10
            ) {
                compactProfileMetric("Picture style", "Standard")
                compactProfileMetric("White balance", "Ambience")
                compactProfileMetric("Tone", "Soft shoulder")
                compactProfileMetric("Texture", "Clean detail")
            }

            Text("Built as an original approximation from Canon’s public G7 X Mark III specifications, guide, and same-scene JPEG/RAW observations: clean neutrals, warm portrait midtones, selective red and blue punch, quieter foliage, protected highlights, and compact-JPEG detail.")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(FilmRecipe.g7XPublicReferences, id: \.self) { reference in
                    if let url = URL(string: reference.url) {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(.caption, weight: .bold))
                                Text(reference.title)
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("This profile does not reproduce Canon sensor calibration, DIGIC processing, lens rendering, flash behavior, or depth of field.")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.accent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("g7x-profile-details")
    }

    private func compactProfileMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title.uppercased())
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 11)
        .background(FilmyTheme.background.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var summaryColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private var controlSummary: some View {
        LazyVGrid(columns: summaryColumns, spacing: 8) {
            ForEach(draft.controlSummary, id: \.0) { control in
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: control.0.uppercased())

                    Text(control.1)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(FilmyTheme.line, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var publicReferenceEntry: FilmRecipeReferenceCatalog.Entry? {
        FilmRecipeReferenceCatalog.entries.first { $0.currentRecipeID == recipe.id }
    }

    private var publicReferenceRows: [(String, String)] {
        guard let controls = publicReferenceEntry?.publicControls else { return [] }

        var rows: [(String, String)] = [
            ("Film simulation", controls.filmSimulation.replacingOccurrences(of: "_", with: " ").uppercased()),
            ("Dynamic range", controls.dynamicRange.uppercased()),
            ("Highlights", signed(controls.highlightTone)),
            ("Shadows", signed(controls.shadowTone)),
            ("Color", signed(controls.color)),
            ("Color Chrome", pretty(controls.colorChromeEffect)),
            ("FX Blue", pretty(controls.colorChromeFXBlue)),
            ("Sharpness", signed(controls.sharpness)),
            ("Noise reduction", signed(controls.noiseReduction)),
            ("Clarity", signed(controls.clarity)),
            ("Grain", "\(pretty(controls.grainEffect)) / \(pretty(controls.grainSize))"),
            ("White balance", pretty(controls.whiteBalance)),
            ("WB shift", "\(signed(controls.whiteBalanceShiftRed))R / \(signed(controls.whiteBalanceShiftBlue))B"),
            ("Exposure", String(format: "%+.1f EV", controls.exposureCompensationEV))
        ]

        if let kelvin = controls.colorTemperatureKelvin {
            rows.append(("Temperature", "\(kelvin) K"))
        }

        return rows
    }

    private var publicReferenceCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "PUBLIC REFERENCE", color: FilmyTheme.accent)

                    Text("\(publicReferenceEntry?.canonicalPublicName ?? recipe.filmBase.officialName) controls")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                }

                Spacer(minLength: 10)

                Text("\(publicReferenceRows.count) values")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(FilmyTheme.tertiary)
            }

            LazyVGrid(
                columns: detailGridColumns,
                alignment: .leading,
                spacing: 1
            ) {
                ForEach(publicReferenceRows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.0.uppercased())
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .tracking(0.6)
                            .foregroundStyle(FilmyTheme.tertiary)

                        Text(row.1)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(FilmyTheme.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 11)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.0): \(row.1)")
                }
            }

            Text("Reference values preserve the public camera-style recipe. Filmy Camera translates them to an original Apple-device rendering; they are not a pixel-identical hardware calibration.")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(FilmyTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.line, lineWidth: 1)
        }
        .accessibilityIdentifier("public-reference-settings")
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "ADJUST", color: FilmyTheme.accent)

                    Text("Recipe controls")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                }

                Spacer(minLength: 12)

                if onUpdate != nil {
                    Button(hasPendingChanges ? "Apply" : "Done") {
                        commitDraft()
                        HapticFeedback.play(.success)
                        dismiss()
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.background)
                    .padding(.horizontal, 12)
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
                    .background(
                        FilmyTheme.accent,
                        in: Capsule()
                    )
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        hasPendingChanges
                            ? "Apply recipe changes"
                            : "Done editing \(recipe.name)"
                    )
                    .accessibilityValue(hasPendingChanges ? "Changes pending" : "No changes")
                    .accessibilityHint(
                        hasPendingChanges
                            ? "Saves the current recipe controls and closes the editor"
                            : "Closes the editor and returns to the camera"
                    )
                }

                Button("Reset") {
                    draft = originalRecipe
                    HapticFeedback.play(.warning)
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel("Reset recipe controls")
            }

            VStack(spacing: 2) {
                ForEach(EditorSection.allCases) { section in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSections.contains(section) },
                            set: { isExpanded in
                                HapticFeedback.play(.selection)
                                if isExpanded {
                                    expandedSections.insert(section)
                                } else {
                                    expandedSections.remove(section)
                                }
                            }
                        )
                    ) {
                        sectionControls(for: section)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.symbol)
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(FilmyTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(FilmyTheme.accent.opacity(0.12), in: Circle())
                                .accessibilityHidden(true)

                            RecipeEditorSectionLabel(title: section.title, detail: section.detail)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .tint(FilmyTheme.accent)
                    .padding(.vertical, 2)

                    if section != EditorSection.allCases.last {
                        Divider().overlay(FilmyTheme.line)
                    }
                }
            }
        }
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                .strokeBorder(FilmyTheme.line, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func sectionControls(for section: EditorSection) -> some View {
        switch section {
        case .tone:
            VStack(spacing: 14) {
                RecipeSliderRow(title: "Exposure", value: binding(\.exposure), range: -2...2, format: "%+.1f EV")
                RecipeSliderRow(title: "Highlights", value: binding(\.tone.highlight), range: -1...1, format: "%+.2f")
                RecipeSliderRow(title: "Shadows", value: binding(\.tone.shadow), range: -1...1, format: "%+.2f")
                RecipeSliderRow(title: "Contrast", value: binding(\.contrast), range: 0.5...1.7, format: "%.2f")
                RecipeChoiceRow(title: "Dynamic range", selection: dynamicRangeBinding) {
                    ForEach(FilmRecipe.DynamicRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                RecipeChoiceRow(title: "D Range Priority", selection: dRangePriorityBinding) {
                    ForEach(FilmRecipe.DRangePriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
            }
        case .color:
            VStack(spacing: 14) {
                RecipeSliderRow(title: "Color", value: binding(\.saturation), range: 0...2, format: "%.2f")
                RecipeChoiceRow(title: "Color Chrome", selection: colorChromeLevelBinding) {
                    ForEach(FilmRecipe.ColorChromeLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                RecipeChoiceRow(title: "FX Blue", selection: fxBlueLevelBinding) {
                    ForEach(FilmRecipe.FXBlueLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                RecipeChoiceRow(title: "White balance", selection: whiteBalanceModeBinding) {
                    ForEach(FilmRecipe.WhiteBalanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if draft.whiteBalance.mode == .colorTemperature {
                    RecipeSliderRow(
                        title: "Color temperature",
                        value: binding(\.whiteBalance.kelvin),
                        range: 2500...10000,
                        format: "%.0f K",
                        step: 10
                    )
                }
                RecipeSliderRow(title: "Warmth", value: binding(\.whiteBalance.temperature), range: -1...1, format: "%+.2f")
                RecipeSliderRow(title: "Tint", value: binding(\.whiteBalance.tint), range: -1...1, format: "%+.2f")

                if draft.filmBase.supportsMonochromaticColorAxes {
                    RecipeSliderRow(
                        title: "Monochromatic warm-cool",
                        value: binding(\.monochromaticColor.warmCool),
                        range: -1...1,
                        format: "%+.2f"
                    )
                    RecipeSliderRow(
                        title: "Monochromatic green-magenta",
                        value: binding(\.monochromaticColor.greenMagenta),
                        range: -1...1,
                        format: "%+.2f"
                    )
                }
            }
        case .texture:
            VStack(spacing: 14) {
                RecipeSliderRow(title: "Sharpness", value: binding(\.sharpness), range: -1...1, format: "%+.2f")
                RecipeSliderRow(title: "Noise reduction", value: binding(\.noiseReduction), range: 0...1, format: "%.2f")
                RecipeSliderRow(title: "Clarity", value: binding(\.clarity), range: -1...1, format: "%+.2f")
            }
        case .finish:
            VStack(spacing: 14) {
                RecipeChoiceRow(title: "Grain Effect", selection: grainEffectLevelBinding) {
                    ForEach(FilmRecipe.GrainEffectLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                RecipeChoiceRow(title: "Grain Size", selection: grainSizeLevelBinding) {
                    ForEach(FilmRecipe.GrainSizeLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                RecipeSliderRow(title: "Vignette", value: binding(\.vignette), range: 0...1, format: "%.2f")
                RecipeSliderRow(title: "Halation", value: binding(\.halation), range: 0...1, format: "%.2f")
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<FilmRecipe, Double>) -> Binding<Double> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue
            }
        )
    }

    private func commitDraft() {
        switch RecipeDetailCommitPolicy.action(
            draft: draft,
            current: recipe,
            original: originalRecipe
        ) {
        case .none:
            return
        case .update(let updatedRecipe):
            onUpdate?(updatedRecipe)
        case .reset:
            onReset?()
        }
    }

    private var dynamicRangeBinding: Binding<FilmRecipe.DynamicRange> {
        Binding(
            get: { draft.dynamicRange },
            set: { newValue in
                draft.dynamicRange = newValue
            }
        )
    }

    private var dRangePriorityBinding: Binding<FilmRecipe.DRangePriority> {
        Binding(
            get: { draft.dRangePriority },
            set: { newValue in
                draft.dRangePriority = newValue
            }
        )
    }

    private var whiteBalanceModeBinding: Binding<FilmRecipe.WhiteBalanceMode> {
        Binding(
            get: { draft.whiteBalance.mode },
            set: { newValue in
                draft.whiteBalance.mode = newValue
            }
        )
    }

    private var fxBlueLevelBinding: Binding<FilmRecipe.FXBlueLevel> {
        Binding(
            get: { draft.fxBlueLevel },
            set: { newValue in
                draft.fxBlueLevel = newValue
            }
        )
    }

    private var colorChromeLevelBinding: Binding<FilmRecipe.ColorChromeLevel> {
        Binding(
            get: { draft.colorChromeLevel },
            set: { newValue in
                draft.colorChromeLevel = newValue
            }
        )
    }

    private var grainEffectLevelBinding: Binding<FilmRecipe.GrainEffectLevel> {
        Binding(
            get: { draft.grainEffectLevel },
            set: { newValue in
                draft.grainEffectLevel = newValue
            }
        )
    }

    private var grainSizeLevelBinding: Binding<FilmRecipe.GrainSizeLevel> {
        Binding(
            get: { draft.grainSizeLevel },
            set: { newValue in
                draft.grainSizeLevel = newValue
            }
        )
    }
}

private struct RecipeChoiceRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    titleLabel
                    picker
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 12) {
                    titleLabel
                    Spacer(minLength: 8)
                    picker
                }
            }
        }
        .frame(minHeight: 52)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var picker: some View {
        Picker(title, selection: $selection, content: content)
            .pickerStyle(.menu)
            .tint(FilmyTheme.accent)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .padding(.vertical, 5)
            .frame(minHeight: FilmyTheme.minimumHitTarget)
            .accessibilityIdentifier(
                title == "FX Blue" ? "fx-blue-control" : "recipe-choice-\(title)"
            )
            .onChange(of: selection) { oldValue, newValue in
                guard oldValue != newValue else { return }
                HapticFeedback.play(.controlStep)
            }
    }
}

private struct RecipeSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let step: Double?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        step: Double? = nil
    ) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
        self.step = step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            valueHeader

            if let step {
                Slider(value: $value, in: range, step: step, onEditingChanged: { isEditing in
                    if !isEditing {
                        HapticFeedback.play(.controlStep)
                    }
                })
                    .tint(FilmyTheme.accent)
                    .accessibilityLabel(title)
                    .accessibilityValue(String(format: format, value))
            } else {
                Slider(value: $value, in: range, onEditingChanged: { isEditing in
                    if !isEditing {
                        HapticFeedback.play(.controlStep)
                    }
                })
                    .tint(FilmyTheme.accent)
                    .accessibilityLabel(title)
                    .accessibilityValue(String(format: format, value))
            }
        }
        .frame(minHeight: 52, alignment: .center)
    }

    @ViewBuilder
    private var valueHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                titleLabel
                valueLabel
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleLabel
                Spacer(minLength: 8)
                valueLabel
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueLabel: some View {
        Text(String(format: format, value))
            .font(FilmyTheme.metadataFont)
            .foregroundStyle(FilmyTheme.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}
