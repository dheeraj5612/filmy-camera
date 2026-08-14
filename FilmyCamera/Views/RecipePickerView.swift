import SwiftUI

struct RecipePickerView: View {
    let recipes: [FilmRecipe]
    @Binding var selectedRecipeID: String
    let onOpenDetail: (FilmRecipe) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(recipes) { recipe in
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                                selectedRecipeID = recipe.id
                            }
                        } label: {
                            recipeTile(recipe)
                        }
                        .id(recipe.id)
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(recipe.name), \(recipe.descriptor)")
                        .accessibilityValue(selectedRecipeID == recipe.id ? "Selected" : "Not selected")
                        .accessibilityHint("Double tap to select this look. Use the View recipe details action for more information.")
                        .accessibilityAction(named: "View recipe details") {
                            onOpenDetail(recipe)
                        }
                        .accessibilityAddTraits(selectedRecipeID == recipe.id ? .isSelected : [])
                        .contextMenu {
                            Button {
                                onOpenDetail(recipe)
                            } label: {
                                Label("View recipe details", systemImage: "info.circle")
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 3)
                .padding(.vertical, 5)
            }
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 3, for: .scrollContent)
            .onAppear {
                proxy.scrollTo(selectedRecipeID, anchor: .center)
            }
            .onChange(of: selectedRecipeID) { _, newValue in
                guard !reduceMotion else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Film recipe picker. Swipe left or right to browse looks.")
    }

    @ViewBuilder
    private func recipeTile(_ recipe: FilmRecipe) -> some View {
        let isSelected = selectedRecipeID == recipe.id

        ZStack(alignment: .topTrailing) {
            RecipeSwatch(recipe: recipe, isSelected: isSelected)
                .frame(width: 142, height: 86)

            if isSelected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                }
                    .foregroundStyle(FilmyTheme.background)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 26)
                    .background(FilmyTheme.accent, in: Capsule())
                    .padding(7)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .background(
            isSelected ? FilmyTheme.accent.opacity(0.14) : Color.white.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isSelected ? FilmyTheme.accent.opacity(0.72) : Color.white.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .scaleEffect(isSelected ? 1 : 0.965)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isSelected)
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
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    identity
                    controlSummary

                    if onUpdate != nil {
                        editor
                    }

                    Button {
                        onSelect()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "camera.fill")
                            Text(isSelected ? "Selected recipe" : "Use this recipe")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.background)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? "\(recipe.name) is selected" : "Use \(recipe.name) recipe")

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "camera.aperture")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(FilmyTheme.accent)
                            .frame(width: 24, height: 24)

                        Text("Original camera-inspired looks, interpreted for Filmy Camera. Results vary with light, exposure, and the iPhone sensor.")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(FilmyTheme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeSwatch(recipe: draft, compact: false, showsLabel: false)
                .frame(maxWidth: .infinity)
                .frame(height: 232)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.56)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOOK / \(recipe.base.uppercased())")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.78))

                    Text("\(draft.controlSummary.count) controls ready")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer(minLength: 12)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "camera.aperture")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(isSelected ? FilmyTheme.accent : .white)
                    .accessibilityHidden(true)
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? FilmyTheme.accent.opacity(0.7) : FilmyTheme.line, lineWidth: isSelected ? 1.5 : 1)
        }
        .shadow(color: isSelected ? FilmyTheme.accent.opacity(0.18) : .clear, radius: 22, y: 10)
        .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(recipe.base.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.black))
                    .tracking(1.5)
                    .foregroundStyle(FilmyTheme.accent)

                if isSelected {
                    Text("ACTIVE")
                        .font(.system(.caption2, design: .rounded).weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(FilmyTheme.background)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 24)
                        .background(FilmyTheme.accent, in: Capsule())
                }
            }

            Text(recipe.name)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(draft.detail)
                .font(FilmyTheme.bodyFont)
                .foregroundStyle(FilmyTheme.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controlSummary: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 1) {
            ForEach(draft.controlSummary, id: \.0) { control in
                VStack(alignment: .leading, spacing: 5) {
                    Text(control.0.uppercased())
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(FilmyTheme.tertiary)

                    Text(control.1)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 58, alignment: .leading)
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 8)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(FilmyTheme.line, lineWidth: 1)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAKE IT YOURS")
                        .font(.system(.caption2, design: .rounded).weight(.black))
                        .tracking(1.3)
                        .foregroundStyle(FilmyTheme.accent)

                    Text("Recipe controls")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                }

                Spacer(minLength: 12)

                Button("Reset") {
                    draft = originalRecipe
                    onReset?()
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
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(FilmyTheme.line, lineWidth: 1)
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
            }
        case .color:
            VStack(spacing: 14) {
                RecipeSliderRow(title: "Color", value: binding(\.saturation), range: 0...2, format: "%.2f")
                RecipeSliderRow(title: "Color Chrome", value: binding(\.colorChrome), range: 0...1, format: "%.2f")
                RecipeChoiceRow(title: "FX Blue", selection: fxBlueLevelBinding) {
                    ForEach(FilmRecipe.FXBlueLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                RecipeSliderRow(title: "Warmth", value: binding(\.whiteBalance.temperature), range: -1...1, format: "%+.2f")
                RecipeSliderRow(title: "Tint", value: binding(\.whiteBalance.tint), range: -1...1, format: "%+.2f")
            }
        case .texture:
            VStack(spacing: 14) {
                RecipeSliderRow(title: "Sharpness", value: binding(\.sharpness), range: -1...1, format: "%+.2f")
                RecipeSliderRow(title: "Noise reduction", value: binding(\.noiseReduction), range: 0...1, format: "%.2f")
                RecipeSliderRow(title: "Clarity", value: binding(\.clarity), range: -1...1, format: "%+.2f")
            }
        case .finish:
            VStack(spacing: 14) {
                RecipeSliderRow(title: "Grain", value: binding(\.grain), range: 0...1, format: "%.2f")
                RecipeSliderRow(title: "Grain size", value: binding(\.grainSize), range: 0.35...2.5, format: "%.2f")
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
                onUpdate?(draft)
            }
        )
    }

    private var dynamicRangeBinding: Binding<FilmRecipe.DynamicRange> {
        Binding(
            get: { draft.dynamicRange },
            set: { newValue in
                draft.dynamicRange = newValue
                onUpdate?(draft)
            }
        )
    }

    private var fxBlueLevelBinding: Binding<FilmRecipe.FXBlueLevel> {
        Binding(
            get: { draft.fxBlueLevel },
            set: { newValue in
                draft.fxBlueLevel = newValue
                onUpdate?(draft)
            }
        )
    }
}

private struct RecipeChoiceRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Picker(title, selection: $selection, content: content)
                .pickerStyle(.menu)
                .tint(FilmyTheme.accent)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.vertical, 5)
                .frame(minHeight: FilmyTheme.minimumHitTarget)
                .accessibilityIdentifier(title == "FX Blue" ? "fx-blue-control" : "recipe-choice-\(title)")
        }
        .frame(minHeight: 52)
    }
}

private struct RecipeSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(String(format: format, value))
                    .font(FilmyTheme.metadataFont)
                    .foregroundStyle(FilmyTheme.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Slider(value: $value, in: range)
                .tint(FilmyTheme.accent)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: format, value))
        }
        .frame(minHeight: 52, alignment: .center)
    }
}
