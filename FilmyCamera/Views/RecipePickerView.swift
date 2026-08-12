import SwiftUI

struct RecipePickerView: View {
    let recipes: [FilmRecipe]
    @Binding var selectedRecipeID: String
    let onOpenDetail: (FilmRecipe) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(recipes) { recipe in
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                            selectedRecipeID = recipe.id
                        }
                    } label: {
                        RecipeSwatch(recipe: recipe, isSelected: selectedRecipeID == recipe.id)
                            .frame(width: 132, height: 80)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(recipe.name), \(recipe.descriptor)")
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
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Film recipe picker")
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
                VStack(alignment: .leading, spacing: 22) {
                    RecipeSwatch(recipe: draft, compact: false)
                        .frame(height: 180)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.base.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(FilmyTheme.accent)

                        Text(recipe.name)
                            .font(.system(size: 31, weight: .black, design: .rounded))
                            .foregroundStyle(FilmyTheme.primary)

                        Text(draft.detail)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        ForEach(draft.controlSummary, id: \.0) { control in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(control.0.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(FilmyTheme.tertiary)
                                Text(control.1)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(FilmyTheme.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                    .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(FilmyTheme.line, lineWidth: 1) }

                    if onUpdate != nil {
                        editor
                    }

                    Button {
                        onSelect()
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "camera.fill")
                            Text(isSelected ? "Selected recipe" : "Use this recipe")
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? "\(recipe.name) is selected" : "Use \(recipe.name) recipe")

                    Text("Public Fujifilm-style vocabulary, interpreted for Filmy Camera. Results vary with light, exposure, and the iPhone sensor.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(FilmyTheme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAKE IT YOURS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(FilmyTheme.accent)
                    Text("Recipe controls")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)
                }

                Spacer()

                Button("Reset") {
                    draft = originalRecipe
                    onReset?()
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(FilmyTheme.accent)
                .buttonStyle(.plain)
                .accessibilityLabel("Reset recipe controls")
            }

            VStack(spacing: 4) {
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
                        RecipeEditorSectionLabel(title: section.title, detail: section.detail)
                    }
                    .tint(FilmyTheme.accent)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 8)

                    if section != EditorSection.allCases.last {
                        Divider().overlay(FilmyTheme.line)
                    }
                }
            }
        }
        .padding(16)
        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(FilmyTheme.line, lineWidth: 1) }
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
                RecipeSliderRow(title: "FX Blue", value: binding(\.fxBlue), range: -1...1, format: "%+.2f")
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
}

private struct RecipeChoiceRow<Content: View>: View {
    let title: String
    @Binding var selection: FilmRecipe.DynamicRange
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(FilmyTheme.primary)
            Spacer()
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.menu)
                .tint(FilmyTheme.accent)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }
}

private struct RecipeSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(FilmyTheme.primary)
                Spacer()
                Text(String(format: format, value))
                    .font(FilmyTheme.metadataFont)
                    .foregroundStyle(FilmyTheme.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range)
                .tint(FilmyTheme.accent)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: format, value))
        }
        .frame(minHeight: 52, alignment: .center)
    }
}
