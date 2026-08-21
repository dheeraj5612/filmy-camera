from pathlib import Path


def replace_once(relative_path: str, old: str, new: str) -> None:
    path = Path(relative_path)
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{relative_path}: expected one replacement target, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "FilmyCamera/Views/RecipePickerView.swift",
    '''import Foundation
import SwiftUI

struct RecipePickerView: View {
    let recipes: [FilmRecipe]
    @Binding var selectedRecipeID: String
    let onOpenDetail: (FilmRecipe) -> Void
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var recipeTileSize: CGSize {
        if compact {
            return CGSize(width: 132, height: 80)
        }

        return dynamicTypeSize.isAccessibilitySize
            ? CGSize(width: 174, height: 138)
            : CGSize(width: 142, height: 86)
    }

    private var selectedRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("CURRENT LOOK")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(FilmyTheme.tertiary)

                    if let selectedRecipe {
                        Text(selectedRecipe.name)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(FilmyTheme.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if recipes.count > 1 {
                        Label("Swipe to browse", systemImage: "arrow.left.and.right")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(FilmyTheme.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 3)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current look")
                .accessibilityValue(selectedRecipe?.name ?? "None selected")

                ZStack {
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

                    HStack {
                        LinearGradient(colors: [FilmyTheme.background, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 14)
                        Spacer()
                        LinearGradient(colors: [.clear, FilmyTheme.background], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
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
            // Compact camera chrome has a deliberately short tile. Passing the
            // compact variant here keeps the descriptor out of that 80pt tile
            // and lets the recipe name use the compact, one-line treatment.
            RecipeSwatch(recipe: recipe, isSelected: isSelected, compact: compact)
                .frame(width: recipeTileSize.width, height: recipeTileSize.height)

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

''',
    '''import Foundation
import SwiftUI

struct RecipePickerView: View {
    let recipes: [FilmRecipe]
    @Binding var selectedRecipeID: String
    let onOpenDetail: (FilmRecipe) -> Void
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var recipeTileSize: CGSize {
        if compact {
            return CGSize(width: 120, height: 76)
        }

        return dynamicTypeSize.isAccessibilitySize
            ? CGSize(width: 160, height: 120)
            : CGSize(width: 142, height: 86)
    }

    private var tileSpacing: CGFloat {
        compact ? 10 : 12
    }

    private var railHeight: CGFloat {
        recipeTileSize.height + 10
    }

    private var selectedRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: compact ? 0 : 8) {
                if !compact {
                    pickerHeader
                }

                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: tileSpacing) {
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

                    HStack {
                        LinearGradient(
                            colors: [FilmyTheme.background, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 12)

                        Spacer()

                        LinearGradient(
                            colors: [.clear, FilmyTheme.background],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: compact ? 18 : 26)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(height: railHeight)
                .accessibilityIdentifier("recipe-rail")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe-picker")
        .accessibilityLabel("Film recipe picker. Swipe left or right to browse looks.")
    }

    private var pickerHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BROWSE LOOKS")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(FilmyTheme.tertiary)

                    if let selectedRecipe {
                        Text(selectedRecipe.name)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(FilmyTheme.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("BROWSE LOOKS")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(FilmyTheme.tertiary)

                    if let selectedRecipe {
                        Text(selectedRecipe.name)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(FilmyTheme.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if recipes.count > 1 {
                        Label("Swipe", systemImage: "arrow.left.and.right")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(FilmyTheme.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Browse looks")
        .accessibilityValue(selectedRecipe?.name ?? "None selected")
    }

    @ViewBuilder
    private func recipeTile(_ recipe: FilmRecipe) -> some View {
        let isSelected = selectedRecipeID == recipe.id
        let cornerRadius: CGFloat = compact ? 16 : 20

        ZStack(alignment: .topTrailing) {
            RecipeSwatch(recipe: recipe, isSelected: isSelected, compact: compact)
                .frame(width: recipeTileSize.width, height: recipeTileSize.height)

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
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? FilmyTheme.accent.opacity(0.72) : Color.white.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .scaleEffect(isSelected ? 1 : 0.965)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isSelected)
    }
}

'''
)

replace_once(
    "FilmyCameraUITests/FilmyCameraUITests.swift",
    '''        XCTAssertTrue(app.staticTexts["Natural Standard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CURRENT LOOK"].waitForExistence(timeout: 5))

        let classicChrome = app.buttons.matching(
''',
    '''        XCTAssertTrue(app.staticTexts["Natural Standard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BROWSE LOOKS"].waitForExistence(timeout: 5))

        let recipePicker = app.descendants(matching: .any)["recipe-picker"]
        XCTAssertTrue(recipePicker.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            recipePicker.frame.height,
            150,
            "The standard recipe picker should remain content-sized"
        )
        attachScreenshot(named: "camera-shell-expanded")

        let classicChrome = app.buttons.matching(
'''
)

replace_once(
    "FilmyCameraUITests/FilmyCameraUITests.swift",
    '''        let tune = accessibilityApp.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Tune '")
        ).firstMatch
        assertMinimumHitTarget(tune, named: "Accessibility-size Tune")

        let captureNotice = accessibilityApp.staticTexts[
''',
    '''        let tune = accessibilityApp.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Tune '")
        ).firstMatch
        assertMinimumHitTarget(tune, named: "Accessibility-size Tune")

        let recipePicker = accessibilityApp.descendants(matching: .any)["recipe-picker"]
        XCTAssertTrue(recipePicker.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            recipePicker.frame.height,
            96,
            "Compact recipe rail should not expand into an empty panel"
        )
        XCTAssertLessThan(
            recipePicker.frame.maxY,
            roll.frame.minY,
            "Compact recipe rail must remain above the camera actions"
        )
        XCTAssertLessThanOrEqual(
            roll.frame.minY - recipePicker.frame.maxY,
            32,
            "The compact recipe rail should remain visually connected to its actions"
        )

        let captureNotice = accessibilityApp.staticTexts[
'''
)

replace_once(
    "FilmyCameraUITests/FilmyCameraUITests.swift",
    '''        attachScreenshot(named: "accessibility-camera-shell")
''',
    '''        attachScreenshot(named: "accessibility-camera-shell-bounded")
'''
)
