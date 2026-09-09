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

struct OnboardingView: View {
    private struct Page: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let message: String
        let icon: String
        let detail: String
    }

    private static let pages = [
        Page(
            id: 0,
            eyebrow: "CHOOSE A RECIPE",
            title: "Start with a feeling.",
            message: "Choose your first look below. It will be ready in the camera, and you can change or tune it anytime.",
            icon: "film.stack",
            detail: "Your look, before the shutter"
        ),
        Page(
            id: 1,
            eyebrow: "COMPOSE IN THE MOOD",
            title: "See the mood as you compose.",
            message: "See your recipe in the live viewfinder. Camera access is only requested when you open the camera. You can also import a photo.",
            icon: "viewfinder",
            detail: "Processed on your device"
        ),
        Page(
            id: 2,
            eyebrow: "KEEP THE FRAME",
            title: "Save the finished photo.",
            message: "Compare with Original, try another look, then save a new copy to Photos. Your original stays unchanged. Nothing saves until you choose.",
            icon: "photo.on.rectangle.angled",
            detail: "No account. No automatic uploads."
        )
    ]

    var recipes: [FilmRecipe] = FilmRecipe.builtIns
    var initialRecipeID: String = CameraViewModel.defaultRecipeID
    var onSelectRecipe: (FilmRecipe) -> Void = { _ in }
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPage = 0
    @State private var chosenRecipeID: String?
    @State private var featuredRecipeID: String?

    private var selectedRecipeID: String { chosenRecipeID ?? initialRecipeID }
    private var featuredRecipes: [FilmRecipe] {
        OnboardingStore.featuredRecipes(from: recipes, selectedRecipeID: featuredRecipeID ?? initialRecipeID)
    }
    private var previewRecipe: FilmRecipe? {
        recipes.first { $0.id == selectedRecipeID } ?? recipes.first
    }

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [FilmyTheme.accent.opacity(0.14), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                TabView(selection: $selectedPage) {
                    ForEach(Self.pages) { page in
                        pageView(page).tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                pageControls
            }
            .frame(maxWidth: 680)
        }
        .preferredColorScheme(.dark)
        // Give the screen its own accessibility node. Without containment,
        // SwiftUI can propagate this identifier into Back, Skip, and Continue.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-screen")
        .onAppear {
            if featuredRecipeID == nil { featuredRecipeID = initialRecipeID }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Filmy Camera", systemImage: "camera.aperture")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
            Spacer(minLength: 8)
            Button(action: onFinish) {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.secondary)
                    .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-skip")
            .accessibilityHint("Open the camera with your current look")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: page.eyebrow, color: FilmyTheme.accent)
                    Text(page.title)
                        .font(.system(.largeTitle, design: .serif).weight(.medium))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.message)
                        .font(FilmyTheme.bodyFont)
                        .foregroundStyle(FilmyTheme.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if page.id == 0 {
                    recipeChooser
                } else {
                    selectedLookVisual(page)
                }

                Label(page.detail, systemImage: page.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recipeChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                ),
                spacing: 12
            ) {
                ForEach(featuredRecipes) { recipe in
                    recipeCard(recipe)
                }
            }
            Text("Sample previews. Your scene will look different in its own light.")
                .font(.caption)
                .foregroundStyle(FilmyTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-recipe-chooser")
    }

    private func recipeCard(_ recipe: FilmRecipe) -> some View {
        let isSelected = selectedRecipeID == recipe.id
        return Button {
            guard !isSelected else { return }
            chosenRecipeID = recipe.id
            onSelectRecipe(recipe)
            HapticFeedback.play(.controlStep)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RecipeSwatch(recipe: recipe, isSelected: isSelected, compact: false, showsLabel: false)
                    .frame(height: 116)
                    .clipped()
                    .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 6) {
                    Text(recipe.name)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? FilmyTheme.accent : FilmyTheme.secondary)
                }
                .foregroundStyle(FilmyTheme.primary)
                Text(recipe.descriptor)
                    .font(.caption)
                    .foregroundStyle(FilmyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? FilmyTheme.accent : FilmyTheme.line, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recipe.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Use this look when you open the camera")
        .accessibilityIdentifier("onboarding-recipe-\(recipe.id)")
    }

    private func selectedLookVisual(_ page: Page) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let recipe = previewRecipe {
                RecipeSwatch(recipe: recipe, compact: false, showsLabel: false)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Label(page.id == 1 ? "YOUR FIRST LOOK" : "REVIEW BEFORE SAVING", systemImage: page.icon)
                        .font(.caption.weight(.semibold))
                    Text(recipe.name).font(.title2.weight(.bold))
                    Text("Sample preview").font(.caption)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .background(FilmyTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityHidden(true)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var pageControls: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        selectedPage = max(0, selectedPage - 1)
                    }
                } label: {
                    Text("Back")
                        .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selectedPage == 0)
                .opacity(selectedPage == 0 ? 0 : 1)
                .accessibilityHidden(selectedPage == 0)
                .accessibilityIdentifier("onboarding-back")
                Spacer()
                Text("\(selectedPage + 1) of \(Self.pages.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Introduction page \(selectedPage + 1) of \(Self.pages.count)")
                Spacer()
                Button(action: onFinish) {
                    Text("Skip for now")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-skip-for-now")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FilmyTheme.secondary)

            Button {
                if selectedPage == Self.pages.count - 1 {
                    onFinish()
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedPage += 1 }
                }
            } label: {
                Label(
                    selectedPage == Self.pages.count - 1 ? "Open camera" : "Continue",
                    systemImage: selectedPage == Self.pages.count - 1 ? "camera.fill" : "arrow.right"
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.filmyPrimary)
            .accessibilityIdentifier("onboarding-continue")
            .accessibilityHint(selectedPage == Self.pages.count - 1 ? "Open the camera with your chosen look" : "Next introduction page")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

#Preview {
    OnboardingView {}
}
