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
    @State private var chosenRecipeID: String?
    @State private var isShowingOriginal = false

    private var selectedRecipeID: String { chosenRecipeID ?? initialRecipeID }
    private var featuredRecipes: [FilmRecipe] {
        OnboardingStore.featuredRecipes(from: recipes, selectedRecipeID: initialRecipeID)
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
                        Text("A look. Your eye.")
                            .font(.system(.largeTitle).weight(.bold))
                            .tracking(-1)
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        if let recipe = previewRecipe {
                            sample(recipe, height: max(170, min(360, geometry.size.height * 0.40)))
                        }
                        recipeChooser
                        Text("Camera photos save automatically to Photos. Imported photos save only when you choose.")
                            .font(.footnote)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding-save-explanation")
                        Label("Processed on this device. No account.", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .accessibilityIdentifier("onboarding-content")
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onFinish) {
                HStack {
                    Text("Open camera")
                    Spacer(minLength: 12)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.filmyPrimary)
            .accessibilityIdentifier("onboarding-continue")
            .accessibilityHint("Opens the camera with your selected look. Camera permission is requested there.")
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

            HStack(alignment: .center, spacing: 12) {
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
                Spacer(minLength: 0)
                Button {
                    HapticFeedback.play(.selection)
                    isShowingOriginal.toggle()
                } label: {
                    Label(isShowingOriginal ? "Show look" : "Original", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FilmyTheme.comparison)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-compare")
                .accessibilityLabel("Compare sample with original")
                .accessibilityValue(isShowingOriginal ? "Original" : "Look")
            }
        }
    }

    private var recipeChooser: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(featuredRecipes) { recipe in
                    let selected = selectedRecipeID == recipe.id
                    Button {
                        guard !selected else { return }
                        chosenRecipeID = recipe.id
                        isShowingOriginal = false
                        HapticFeedback.play(.selection)
                        onSelectRecipe(recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RecipeSwatch(recipe: recipe, showsLabel: false)
                                .frame(width: 96, height: 64)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            HStack(alignment: .top, spacing: 4) {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                                Text(recipe.name)
                                    .font(.caption.weight(selected ? .bold : .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(selected ? FilmyTheme.accent : FilmyTheme.primary)
                            .frame(width: 96, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding-recipe-\(recipe.id)")
                    .accessibilityLabel(recipe.name)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-recipe-chooser")
    }
}
