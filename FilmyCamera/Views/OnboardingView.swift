import SwiftUI

enum OnboardingStore {
    static let hasCompletedKey = "hasCompletedRecipeFirstOnboarding"

    /// Stable IDs survive catalog reordering. Use the caller's effective
    /// recipes so onboarding never replaces a saved custom look with stock.
    static func featuredRecipes(from recipes: [FilmRecipe], selectedRecipeID: String) -> [FilmRecipe] {
        let ids = [selectedRecipeID, "g7x-compact", "classic-chrome", "nostalgic-negative", "acros-monochrome"]
        var seen = Set<String>()
        return Array(ids.compactMap { id -> FilmRecipe? in
            guard seen.insert(id).inserted else { return nil }
            return recipes.first { $0.id == id }
        }.prefix(4))
    }
}

/// One interactive photograph, not a slideshow of instructions. Camera and
/// Photos permissions remain owned by the destination workflows.
struct OnboardingView: View {
    var recipes: [FilmRecipe] = FilmRecipe.builtIns
    var initialRecipeID: String = CameraViewModel.defaultRecipeID
    var onSelectRecipe: (FilmRecipe) -> Void = { _ in }
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var selectionIconWidth: CGFloat = 16
    @State private var chosenRecipeID: String?
    @State private var featuredAnchorID: String?
    @State private var isShowingOriginal = false

    private var selectedRecipeID: String { chosenRecipeID ?? initialRecipeID }
    private var featuredRecipes: [FilmRecipe] {
        OnboardingStore.featuredRecipes(from: recipes, selectedRecipeID: featuredAnchorID ?? initialRecipeID)
    }
    private var previewRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID } ?? recipes.first
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(AppConfiguration.isG7X ? "G7X in every frame." : "A look. Your eye.")
                            .font(.system(.largeTitle).weight(.bold))
                            .tracking(-1)
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        if let recipe = previewRecipe {
                            sample(recipe, height: sampleHeight(for: geometry.size.height))
                        }
                        #if !G7_APP
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Choose your starting look")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FilmyTheme.primary)
                                .accessibilityAddTraits(.isHeader)
                            recipeChooser
                        }
                        #endif
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Camera photos save automatically to Photos. Imported photos save only when you choose.")
                                .font(.footnote)
                                .foregroundStyle(FilmyTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("onboarding-save-explanation")
                            permissionNote
                        }
                        Label("Processed on this device. No account.", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("onboarding-content")
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onFinish) {
                HStack {
                    Text("Open camera")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 12)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.filmyPrimary)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityShowsLargeContentViewer {
                Label("Open camera", systemImage: "arrow.right")
            }
            .accessibilityLabel("Open camera")
            .accessibilityValue(previewRecipe?.name ?? "Current look")
            .accessibilityIdentifier("onboarding-continue")
            .accessibilityHint("Opens the camera with your selected look. You may be asked for camera access there.")
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .background(FilmyTheme.background)
        }
        .background(FilmyTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-screen")
    }

    private var permissionNote: some View {
        Text("You may be asked for camera, location and Photos access.")
            .font(.caption)
            .foregroundStyle(FilmyTheme.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("onboarding-permission-note")
    }

    private func sampleHeight(for available: CGFloat) -> CGFloat {
        let fraction: CGFloat = dynamicTypeSize.isAccessibilitySize ? 0.40 : 0.35
        return max(170, min(360, available * fraction))
    }

    private var header: some View {
        HStack {
            FilmyWordmark()
            Spacer(minLength: 12)
            Button(action: onFinish) {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.secondary)
                    .frame(minWidth: 44, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-skip")
            .accessibilityHint("Opens the camera with your current look")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func sample(_ recipe: FilmRecipe, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if isShowingOriginal {
                    Color.clear.overlay {
                        Image("LookPreviewCafe")
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                } else {
                    RecipeSwatch(recipe: recipe, showsLabel: false)
                }
            }
            .frame(height: height)
            .clipped()
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("onboarding-photo")
            .accessibilityLabel("Sample photograph, \(isShowingOriginal ? "original" : recipe.name)")

            comparisonLayout {
                VStack(alignment: .leading, spacing: 4) {
                    FilmRegistration(color: isShowingOriginal ? FilmyTheme.comparison : FilmyTheme.accent)
                    Text(isShowingOriginal ? "Original" : recipe.name)
                        .font(.headline)
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Sample photo")
                        .font(.caption)
                        .foregroundStyle(FilmyTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    HapticFeedback.play(.selection)
                    isShowingOriginal.toggle()
                } label: {
                    Label(isShowingOriginal ? "Show look" : "Original", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FilmyTheme.comparison)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 48)
                        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-compare")
                .accessibilityLabel("Compare sample with original")
                .accessibilityValue(isShowingOriginal ? "Original" : "Look")
                .accessibilityHint(isShowingOriginal ? "Returns to the selected look" : "Shows the unedited sample photograph")
            }
        }
    }

    private var comparisonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private var recipeChooser: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The enclosing page already scrolls. Avoid a narrow horizontal
                // strip that makes long names difficult to compare at large sizes.
                VStack(spacing: 10) {
                    ForEach(featuredRecipes) { recipe in
                        recipeChoice(recipe, expanded: true)
                    }
                }
            } else {
                // Non-lazy grid: every tile exists before any scrolling.
                VStack(spacing: 10) {
                    ForEach(Array(stride(from: 0, to: featuredRecipes.count, by: 2)), id: \.self) { start in
                        recipeGridRow(startingAt: start)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-recipe-chooser")
    }

    private func recipeGridRow(startingAt start: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            recipeChoice(featuredRecipes[start], expanded: false)
            if start + 1 < featuredRecipes.count {
                recipeChoice(featuredRecipes[start + 1], expanded: false)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
    }

    private func recipeChoice(_ recipe: FilmRecipe, expanded: Bool) -> some View {
        let selected = selectedRecipeID == recipe.id
        let layout = expanded
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        let minTileHeight: CGFloat? = expanded ? nil : 48
        let swatchWidth: CGFloat? = expanded ? nil : 48
        let swatchMaxWidth: CGFloat = expanded ? .infinity : 48
        let swatchHeight: CGFloat = expanded ? 64 : 48

        return Button {
            guard !selected else { return }
            if featuredAnchorID == nil { featuredAnchorID = initialRecipeID }
            chosenRecipeID = recipe.id
            isShowingOriginal = false
            HapticFeedback.play(.selection)
            onSelectRecipe(recipe)
        } label: {
            layout {
                RecipeSwatch(recipe: recipe, isSelected: selected && !expanded, showsLabel: false)
                    .frame(width: swatchWidth, height: swatchHeight)
                    .frame(maxWidth: swatchMaxWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 5) {
                        // Reserve the checkmark's space so selection does not
                        // change line wrapping or move the surrounding tiles.
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.caption.weight(.semibold))
                            .frame(width: selectionIconWidth)
                            .accessibilityHidden(true)
                        Text(recipe.name)
                            .font((expanded ? Font.body : Font.caption).weight(.semibold))
                            .minimumScaleFactor(expanded ? 1 : 0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(selected ? FilmyTheme.accent : FilmyTheme.primary)
                    if expanded {
                        Text(recipe.descriptor)
                            .font(.caption)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: minTileHeight, alignment: .leading)
            .padding(expanded ? 12 : 0)
            .background(expanded ? FilmyTheme.panel : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-recipe-\(recipe.id)")
        .accessibilityLabel(recipe.name)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Previews this look and uses it when you open the camera")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
