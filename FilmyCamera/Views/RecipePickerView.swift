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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
            return dynamicTypeSize.isAccessibilitySize
                ? CGSize(width: 146, height: 90)
                : CGSize(width: 126, height: 88)
        }
        // Regular widths (iPad) have room for a slightly larger swatch.
        return horizontalSizeClass == .regular
            ? CGSize(width: 96, height: 70)
            : CGSize(width: 78, height: 58)
    }

    private var tileSpacing: CGFloat {
        compact ? 10 : 10
    }

    /// Compact tiles keep the name inside the swatch at normal sizes; large
    /// accessibility text moves it below in a two-line caption.
    private var railHeight: CGFloat {
        compact ? swatchSize.height + 12 : swatchSize.height + 30
    }

    /// Put the compact digital profile in the first glance of the rail. Its
    /// identity is different from the Fuji-inspired looks, so a new user can
    /// compare the G7 X option with film recipes without a long horizontal
    /// hunt. IDs and the relative order of every other recipe stay intact.
    private var presentationRecipes: [FilmRecipe] {
        guard let compactProfile = recipes.first(where: { $0.filmBase == .compactDigital }) else {
            return recipes
        }
        return [compactProfile] + recipes.filter { $0.id != compactProfile.id }
    }

    private enum RecipeGroup: String, CaseIterable, Identifiable {
        case compact
        case film
        case monochrome

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact: return "Digital"
            case .film: return "Film"
            case .monochrome: return "Monochrome"
            }
        }

        var symbol: String {
            switch self {
            case .compact: return "camera.fill"
            case .film: return "film"
            case .monochrome: return "circle.lefthalf.filled"
            }
        }
    }

    private struct RecipeGroupSection: Identifiable {
        let group: RecipeGroup
        let recipes: [FilmRecipe]
        var id: String { group.id }
    }

    private var groupedRecipes: [RecipeGroupSection] {
        RecipeGroup.allCases.compactMap { group in
            let groupRecipes = presentationRecipes.filter { recipe in
                switch group {
                case .compact:
                    return recipe.isDigitalCameraStyle
                case .monochrome:
                    return recipe.filmBase.monochromeFilter != nil
                        || recipe.filmBase == .sepia
                case .film:
                    return !recipe.isDigitalCameraStyle
                        && recipe.filmBase.monochromeFilter == nil
                        && recipe.filmBase != .sepia
                }
            }
            return groupRecipes.isEmpty ? nil : RecipeGroupSection(group: group, recipes: groupRecipes)
        }
    }

    var body: some View {
        if compact {
            expandedPicker
        } else {
            standardRail
        }
    }

    private var standardRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(presentationRecipes) { recipe in
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

    /// The drawer is intentionally grouped by the kind of camera decision it
    /// represents. A compact profile and a monochrome look should not be
    /// hidden in one undifferentiated strip of thumbnails.
    private var expandedPicker: some View {
        ScrollViewReader { outerProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedRecipes) { section in
                        let group = section.group
                        let recipes = section.recipes
                        VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Image(systemName: group.symbol)
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(groupAccent(group))
                                .accessibilityHidden(true)
                            Text(group.title.uppercased())
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(groupAccent(group))
                            Text("\(recipes.count)")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(FilmyTheme.tertiary)
                            Spacer(minLength: 0)
                        }

                            ScrollViewReader { rowProxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 10) {
                                        ForEach(recipes) { recipe in
                                            recipeButton(for: recipe)
                                                .id(recipe.id)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                    .padding(.vertical, 2)
                                }
                                .scrollClipDisabled()
                                .accessibilityIdentifier("recipe-group-\(group.id)")
                                .onAppear {
                                    if recipes.contains(where: { $0.id == selectedRecipeID }) {
                                        rowProxy.scrollTo(selectedRecipeID, anchor: .center)
                                    }
                                }
                            }
                        }
                        .id(section.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onAppear {
                if let section = groupedRecipes.first(where: { $0.recipes.contains(where: { $0.id == selectedRecipeID }) }) {
                    outerProxy.scrollTo(section.id, anchor: .center)
                }
            }
        }
        // Landscape phones have very little vertical room once the drawer
        // header and capture controls are accounted for. Keep the drawer
        // bounded and let its grouped rows scroll inside that space.
        .frame(maxHeight: verticalSizeClass == .compact
            ? (dynamicTypeSize.isAccessibilitySize ? 220 : 190)
            : (dynamicTypeSize.isAccessibilitySize ? 390 : 330))
        .accessibilityIdentifier("recipe-picker")
        .accessibilityLabel("Film recipe picker grouped by compact, film, and monochrome looks")
    }

    private func groupAccent(_ group: RecipeGroup) -> Color {
        switch group {
        case .compact: return FilmyTheme.accent
        case .film: return FilmyTheme.filmAccent
        case .monochrome: return FilmyTheme.primary
        }
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

        return VStack(spacing: 6) {
            RecipeSwatch(
                recipe: recipe,
                isSelected: isSelected,
                compact: compact,
                showsLabel: compact && !dynamicTypeSize.isAccessibilitySize
            )
            .frame(width: swatchSize.width, height: swatchSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !compact || dynamicTypeSize.isAccessibilitySize {
                Text(recipe.name)
                    .font(.system(
                        dynamicTypeSize.isAccessibilitySize ? .caption : .caption2,
                        design: .rounded
                    ).weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? FilmyTheme.accent : Color.white.opacity(0.72))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.82 : 0.78)
                    .multilineTextAlignment(.center)
                    .frame(width: swatchSize.width + 8)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }
        // Do not dim unselected photographs: their colors are the decision.
        .opacity(1)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isSelected)
    }
}

/// The camera's current look control. It stays useful in both the bottom dock
/// and the narrow iPad edge column, while exposing the full recipe name to
/// VoiceOver and Dynamic Type.
struct CurrentRecipeButton: View {
    let recipe: FilmRecipe
    let isCustomized: Bool
    let compactLayout: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accentColor: Color {
        recipe.isDigitalCameraStyle ? FilmyTheme.accent : FilmyTheme.filmAccent
    }

    private var semanticSubtitle: String {
        if isCustomized { return "Customized" }
        if recipe.isDigitalCameraStyle { return "Digital style" }
        if recipe.filmBase.monochromeFilter != nil || recipe.filmBase == .sepia {
            return "Monochrome"
        }
        return "Film look"
    }

    private var recipeIcon: some View {
        RecipeSwatch(recipe: recipe, compact: true, showsLabel: false)
            .frame(width: 34, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }

    private var regularLabel: some View {
        HStack(spacing: 8) {
            recipeIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.72)

                Text("\(semanticSubtitle) · Explore")
                    .font(.system(.caption2).weight(.medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .accessibilityHidden(true)
        }
    }

    private var narrowLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                recipeIcon
                Text(recipe.name)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(semanticSubtitle)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
    }

    init(
        recipe: FilmRecipe,
        isCustomized: Bool,
        compactLayout: Bool = false,
        action: @escaping () -> Void
    ) {
        self.recipe = recipe
        self.isCustomized = isCustomized
        self.compactLayout = compactLayout
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if compactLayout {
                    narrowLabel
                } else {
                    regularLabel
                }
            }
            .frame(maxWidth: .infinity, minHeight: compactLayout ? 58 : FilmyTheme.minimumHitTarget, alignment: .leading)
            .padding(.horizontal, 11)
            .background(FilmyTheme.backgroundRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(accentColor.opacity(0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
        .frame(maxWidth: compactLayout ? 136 : 256)
        .accessibilityIdentifier("recipe-menu")
        .accessibilityLabel("Choose look, current recipe \(recipe.name)")
        .accessibilityValue(semanticSubtitle)
        .accessibilityHint("Opens the compact, film, and monochrome look picker")
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
    let onCancel: () -> Void
    let onUpdate: ((FilmRecipe) -> Void)?
    let onReset: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: FilmRecipe
    @State private var expandedSections: Set<EditorSection> = [.tone, .color]
    @State private var isShowingLookInfo = false

    init(
        recipe: FilmRecipe,
        originalRecipe: FilmRecipe,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUpdate: ((FilmRecipe) -> Void)? = nil,
        onReset: (() -> Void)? = nil
    ) {
        self.recipe = recipe
        self.originalRecipe = originalRecipe
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onUpdate = onUpdate
        self.onReset = onReset
        _draft = State(initialValue: recipe)
    }

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    BackToCameraButton(
                        accessibilityIdentifier: "recipe-back-to-camera",
                        action: onCancel
                    )

                    hero

                    if onUpdate != nil {
                        editor
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                                isShowingLookInfo.toggle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle")
                                    .font(.system(.subheadline, weight: .bold))
                                    .foregroundStyle(FilmyTheme.accent)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("About this look")
                                        .font(.system(.headline, design: .rounded).weight(.bold))
                                        .foregroundStyle(FilmyTheme.primary)
                                    Text(isShowingLookInfo ? "Description and camera reference" : "Description, reference, and provenance")
                                        .font(.system(.caption, design: .rounded).weight(.medium))
                                        .foregroundStyle(FilmyTheme.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: isShowingLookInfo ? "chevron.up" : "chevron.down")
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundStyle(FilmyTheme.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recipe-info-toggle")
                        .accessibilityLabel("About this look")
                        .accessibilityValue(isShowingLookInfo ? "Expanded" : "Collapsed")
                        .accessibilityHint("Shows the description, camera reference, and provenance")

                        if isShowingLookInfo {
                            VStack(alignment: .leading, spacing: 18) {
                                identity
                                controlSummary

                                if recipe.filmBase == .compactDigital {
                                    compactDigitalProfileCard
                                }

                                if publicReferenceEntry != nil {
                                    publicReferenceCard
                                }

                                provenanceNote
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(14)
                    .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous)
                            .strokeBorder(FilmyTheme.line, lineWidth: 1)
                    }

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

    private var provenanceNote: some View {
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
                : "Done editing \(recipe.name)"
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
        VStack(alignment: .leading, spacing: 14) {
            RecipeSwatch(recipe: draft, compact: false, showsLabel: false)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: recipe.filmBase.officialName.uppercased(), color: FilmyTheme.accent)
                Text(recipe.name)
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .foregroundStyle(FilmyTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recipe.descriptor)
                    .font(.subheadline)
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if isSelected { FilmyTag(text: "ACTIVE") }
                    if draft != originalRecipe { FilmyTag(text: "EDITED", filled: false) }
                }
            }
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
                        : recipe.creativeCollection.map { "Original Filmy \($0.title) treatment" }
                            ?? "Camera reference · \(recipe.filmBase.officialName)"
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
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            headerLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "ADJUST", color: FilmyTheme.accent)

                    Text("Recipe controls")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 12)
                }

                Button {
                    draft = originalRecipe
                    HapticFeedback.play(.warning)
                } label: {
                    Text("Reset")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.accent)
                        .padding(.horizontal, 14)
                        .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .background(FilmyTheme.accent.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                }
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
                Text("Adjusts tones in the finished look. Auto uses a preset strength; it does not meter the scene or change sensor exposure.")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .color:
            VStack(spacing: 14) {
                if draft.filmBase.monochromeFilter == nil {
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
                } else {
                    Label("Monochrome recipe", systemImage: "circle.lefthalf.filled")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Color saturation and color effects are fixed for this look. Warmth, tint, and the monochromatic axes remain available below.")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RecipeChoiceRow(title: "White balance", selection: whiteBalanceModeBinding) {
                    ForEach(FilmRecipe.WhiteBalanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if [.auto, .whitePriority, .custom1, .custom2, .custom3].contains(draft.whiteBalance.mode) {
                    Text("Auto, White priority, and Custom 1–3 start from the photo’s captured white balance and use the Warmth and Tint shifts below. Custom white measurement is not available.")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FilmyTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Searchable look library

/// Shared by the camera and review. Stable recipe IDs, not names or catalog
/// positions, own favorites. Searching and filtering never apply a recipe.
enum LookLibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, compact, film, monochrome, negative, slide, cinema, instant, experimental

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All looks"
        case .favorites: return "Favorites"
        case .compact: return "Digital"
        case .film: return "Film"
        case .monochrome: return "Monochrome"
        case .negative: return "Negative"
        case .slide: return "Slide"
        case .cinema: return "Cinema"
        case .instant: return "Instant"
        case .experimental: return "Experimental"
        }
    }
}

enum LookLibraryIndex {
    static func favorites(from data: Data) -> Set<String> {
        guard data.count <= 262_144,
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids.prefix(512).filter { !$0.isEmpty && $0.utf8.count <= 256 })
    }

    static func encodeFavorites(_ ids: Set<String>) -> Data {
        let normalized = ids.filter { !$0.isEmpty && $0.utf8.count <= 256 }.sorted().prefix(512)
        return (try? JSONEncoder().encode(Array(normalized))) ?? Data()
    }

    static func results(
        in recipes: [FilmRecipe],
        query: String,
        filter: LookLibraryFilter,
        favorites: Set<String>
    ) -> [FilmRecipe] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let ordered = recipes.filter { $0.filmBase == .compactDigital }
            + recipes.filter { $0.filmBase != .compactDigital }
        return ordered.filter { recipe in
            let monochrome = recipe.filmBase.monochromeFilter != nil || recipe.filmBase == .sepia
            let included: Bool
            switch filter {
            case .all: included = true
            case .favorites: included = favorites.contains(recipe.id)
            case .compact: included = recipe.isDigitalCameraStyle
            case .film: included = !recipe.isDigitalCameraStyle && !monochrome
            case .monochrome: included = monochrome
            case .negative: included = recipe.creativeCollection == .negative
            case .slide: included = recipe.creativeCollection == .slide
            case .cinema: included = recipe.creativeCollection == .cinema
            case .instant: included = recipe.creativeCollection == .instant
            case .experimental: included = recipe.creativeCollection == .experimental
            }
            let searchable = "\(recipe.name) \(recipe.descriptor) \(recipe.creativeCollection?.title ?? "")"
            return included && words.allSatisfy { searchable.localizedStandardContains($0) }
        }
    }
}

/// A single destination for discovery. Card taps apply a look; hearts only
/// change favorites. Sample thumbnails use the existing bounded renderer and
/// its cache, not an additional live camera session or full-resolution render.
struct LookLibraryView: View {
    let recipes: [FilmRecipe]
    let selectedRecipeID: String
    var selectionIdentifierPrefix = "library-recipe"
    var subtitle = "Find a feeling. Make it your own."
    let onSelect: (FilmRecipe) -> Void
    let onClose: () -> Void

    @AppStorage("favoriteRecipeIDs.v1") private var favoriteData = Data()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var filter: LookLibraryFilter = .all
    @FocusState private var searchIsFocused: Bool

    private var favoriteIDs: Set<String> { LookLibraryIndex.favorites(from: favoriteData) }

    private var results: [FilmRecipe] {
        LookLibraryIndex.results(in: recipes, query: query, filter: filter, favorites: favoriteIDs)
    }

    var body: some View {
        GeometryReader { geometry in
            let singleColumn = geometry.size.width < 350 || dynamicTypeSize.isAccessibilitySize
            let compactHeader = geometry.size.height < 480 || dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 0) {
                libraryHeader(compact: compactHeader)
                searchField
                    .padding(.top, compactHeader ? 8 : 18)
                filterStrip
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(results.count) \(results.count == 1 ? "look" : "looks")")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    Text("Sample previews")
                        .font(.caption)
                }
                .foregroundStyle(FilmyTheme.secondary)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("look-library-result-count")

                ScrollView(showsIndicators: false) {
                    if results.isEmpty {
                        emptyResults
                    } else {
                        LazyVGrid(
                            columns: singleColumn
                                ? [GridItem(.flexible())]
                                : [GridItem(.adaptive(minimum: 150, maximum: 270), spacing: 14)],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(results) { recipe in
                                lookCard(recipe)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .id("\(filter.rawValue):\(query)")
                .accessibilityIdentifier("look-library-results")
            }
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(FilmyTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-library")
        .accessibilityAction(.escape, onClose)
    }

    private func libraryHeader(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    if !compact {
                        Eyebrow(text: "THE LOOK LIBRARY", color: FilmyTheme.accent)
                    }
                    Text("Looks")
                        .font(.system(compact ? .title2 : .largeTitle, design: .serif).weight(.medium))
                        .foregroundStyle(FilmyTheme.primary)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FilmyTheme.primary)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 52, minHeight: 48)
                        .background(FilmyTheme.panel, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("look-library-close")
                .accessibilityHint("Closes the library without changing your look")
            }
            if !compact {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, compact ? 12 : 26)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FilmyTheme.secondary)
                .accessibilityHidden(true)
            TextField("Search looks", text: $query)
                .font(.body)
                .foregroundStyle(FilmyTheme.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchIsFocused)
                .onSubmit { searchIsFocused = false }
                .accessibilityIdentifier("look-library-search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FilmyTheme.secondary)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("look-library-clear-search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 2)
        .frame(minHeight: 52)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(FilmyTheme.lineStrong, lineWidth: 1) }
        .padding(.horizontal, 22)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LookLibraryFilter.allCases) { option in
                    Button {
                        HapticFeedback.play(.selection)
                        filter = option
                        searchIsFocused = false
                    } label: {
                        HStack(spacing: 6) {
                            if option == .favorites {
                                Image(systemName: "heart")
                            }
                            Text(option.title)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(filter == option ? FilmyTheme.background : FilmyTheme.secondary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(filter == option ? FilmyTheme.accent : FilmyTheme.panel, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("look-filter-\(option.id)")
                    .accessibilityValue(filter == option ? "Selected" : "Not selected")
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, 22)
        }
        .accessibilityElement(children: .contain)
    }

    private func lookCard(_ recipe: FilmRecipe) -> some View {
        let selected = recipe.id == selectedRecipeID
        let favorite = favoriteIDs.contains(recipe.id)
        return ZStack(alignment: .topTrailing) {
            Button {
                searchIsFocused = false
                HapticFeedback.play(.selection)
                onSelect(recipe)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .aspectRatio(dynamicTypeSize.isAccessibilitySize ? 2 : 4.0 / 3.0, contentMode: .fit)
                        .overlay {
                            RecipeSwatch(recipe: recipe, compact: false, showsLabel: false)
                        }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            if selected {
                                Label("Current", systemImage: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(FilmyTheme.background)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(FilmyTheme.accent, in: Capsule())
                                    .padding(10)
                            }
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recipe.descriptor)
                            .font(.caption)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(selected ? FilmyTheme.accent : FilmyTheme.line, lineWidth: selected ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(selectionIdentifierPrefix)-\(recipe.id)")
            .accessibilityLabel("\(recipe.name), \(recipe.descriptor)")
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Applies this look and closes the library")
            // The favorite button is a sibling overlay, never a nested button in
            // the selection label. Favoriting must not apply or dismiss a look.
            Button {
                var updated = favoriteIDs
                if favorite { updated.remove(recipe.id) } else { updated.insert(recipe.id) }
                favoriteData = LookLibraryIndex.encodeFavorites(updated)
                HapticFeedback.play(.selection)
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(favorite ? FilmyTheme.accent : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.78), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-favorite-\(recipe.id)")
            .accessibilityLabel(favorite ? "Remove \(recipe.name) from favorites" : "Favorite \(recipe.name)")
            .accessibilityValue(favorite ? "Favorite" : "Not favorite")
            .padding(8)
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyResults: some View {
        VStack(spacing: 16) {
            Image(systemName: filter == .favorites && query.isEmpty ? "heart" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FilmyTheme.accent)
                .accessibilityHidden(true)
            Text(filter == .favorites && query.isEmpty ? "Keep your favorites close." : "No looks found.")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(FilmyTheme.primary)
                .accessibilityIdentifier("look-library-empty")
            Text(filter == .favorites && query.isEmpty
                 ? "Tap the heart on any look to find it here."
                 : "Try a different name or switch to All looks.")
                .font(.subheadline)
                .foregroundStyle(FilmyTheme.secondary)
            Button {
                filter = .all
                query = ""
                searchIsFocused = false
            } label: {
                Text("Show all looks")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FilmyTheme.background)
            .background(FilmyTheme.accent, in: Capsule())
            .accessibilityIdentifier("look-library-reset")
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 28)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
    }
}
