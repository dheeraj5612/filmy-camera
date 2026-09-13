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

/// First use is a single, optional visual decision — not a three-page tour.
/// The system owns permission prompts, requested only at the point of use.
struct OnboardingView: View {
    var recipes: [FilmRecipe] = FilmRecipe.builtIns
    var initialRecipeID: String = CameraViewModel.defaultRecipeID
    var onSelectRecipe: (FilmRecipe) -> Void = { _ in }
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var chosenRecipeID: String?
    @State private var isShowingOriginal = false
    @State private var isShowingPrivacy = false

    private var selectedRecipeID: String { chosenRecipeID ?? initialRecipeID }
    private var featuredRecipes: [FilmRecipe] {
        OnboardingStore.featuredRecipes(from: recipes, selectedRecipeID: initialRecipeID)
    }
    private var previewRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID } ?? recipes.first
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Text("Start with a look.")
                        .font(.title.weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .accessibilityAddTraits(.isHeader)
                    if let previewRecipe {
                        RecipeSwatch(recipe: previewRecipe, showsLabel: false,
                                     showsOriginal: isShowingOriginal)
                            .frame(height: dynamicTypeSize.isAccessibilitySize ? 140 : min(geometry.size.height * 0.34, 320))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel("Sample photo, \(isShowingOriginal ? "original" : previewRecipe.name)")
                            .accessibilityIdentifier("onboarding-sample")
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(previewRecipe.name)
                                    .font(.headline)
                                    .foregroundStyle(FilmyTheme.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Sample · not live")
                                    .font(.caption)
                                    .foregroundStyle(FilmyTheme.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                HapticFeedback.play(.selection)
                                isShowingOriginal.toggle()
                            } label: {
                                Label("Original", systemImage: "circle.lefthalf.filled")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minWidth: 44, minHeight: 48)
                                    .background(isShowingOriginal ? FilmyTheme.accent : FilmyTheme.panel,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(isShowingOriginal ? FilmyTheme.background : FilmyTheme.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding-compare")
                            .accessibilityLabel("Compare sample with original")
                            .accessibilityValue(isShowingOriginal ? "Original" : "Look")
                            .accessibilityHint("Changes only the sample preview, not your selected look")
                        }
                    }
                    recipeChooser
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("onboarding-content")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button(action: onFinish) {
                        HStack {
                            Text("Open camera")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(.filmyPrimary)
                    .accessibilityIdentifier("onboarding-continue")
                    .accessibilityHint("Open the camera with your selected look. Camera shots save automatically to Photos.")
                    Button { isShowingPrivacy = true } label: {
                        Text("Camera shots save to Photos. How it works")
                            .font(.caption)
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding-privacy")
                    .accessibilityHint("Learn about permissions and saving")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .background(FilmyTheme.background)
            }
        }
        .background(FilmyTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-screen")
        .sheet(isPresented: $isShowingPrivacy) {
            NavigationStack {
                List {
                    Section("Camera") {
                        Text("Camera access is requested when you open the camera. Each shot saves automatically to Photos.")
                    }
                    Section("Photos") {
                        Text("Import only the photo you choose. Edits save as a new copy when you tap Save to Photos; your original is unchanged.")
                    }
                    Section("Processing") {
                        Text("Looks are processed on your device. Filmy does not upload your photos. Your system Photos and iCloud settings still apply.")
                    }
                }
                .navigationTitle("Your photos")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingPrivacy = false }
                            .accessibilityIdentifier("onboarding-privacy-close")
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            FilmyBrand()
            Spacer()
            Button("Skip", action: onFinish)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("onboarding-skip")
                .accessibilityHint("Open the camera with your current look")
        }
    }

    private var recipeChooser: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(featuredRecipes) { recipe in
                    Button {
                        chosenRecipeID = recipe.id
                        isShowingOriginal = false
                        onSelectRecipe(recipe)
                        HapticFeedback.play(.selection)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            RecipeSwatch(recipe: recipe, compact: true, showsLabel: false)
                                .frame(height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .accessibilityHidden(true)
                            Rectangle()
                                .fill(selectedRecipeID == recipe.id ? FilmyTheme.accent : FilmyTheme.lineStrong)
                                .frame(height: 3)
                            Text(recipe.name)
                                .font(.caption.weight(selectedRecipeID == recipe.id ? .bold : .medium))
                                .foregroundStyle(selectedRecipeID == recipe.id ? FilmyTheme.accent : FilmyTheme.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 144 : 84, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding-recipe-\(recipe.id)")
                    .accessibilityLabel(recipe.name)
                    .accessibilityValue(selectedRecipeID == recipe.id ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selectedRecipeID == recipe.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("onboarding-look-strip")
    }
}
