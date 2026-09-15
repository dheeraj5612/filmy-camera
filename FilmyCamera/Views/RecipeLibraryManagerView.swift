import SwiftUI

/// Pack operations are explicit bulk changes; recipe toggles are exceptions.
/// This sheet manages menu membership, never edits or replaces saved recipes.
struct RecipeLibraryManagerView: View {
    @Binding var preferences: RecipeLibraryPreferences
    let recipes: [FilmRecipe]
    let selectedRecipeID: String
    let onSelect: (FilmRecipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showsRecipes = false
    @State private var membership: RecipeMembershipFilter = .all
    @State private var undoState: RecipeLibraryPreferences?
    @AppStorage("favoriteRecipeIDs.v1") private var favoriteData = Data()

    private var favorites: Set<String> { LookLibraryIndex.favorites(from: favoriteData) }
    private var activeCount: Int { recipes.reduce(0) { $0 + (preferences.isEnabled($1.id) ? 1 : 0) } }
    private var searchingRecipes: Bool { showsRecipes || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var filtered: [FilmRecipe] {
        RecipeMembershipFilter.results(recipes, query: query, filter: membership, preferences: preferences, favorites: favorites)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Library view", selection: $showsRecipes) {
                    Text("Packs").tag(false)
                    Text("Recipes").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .accessibilityIdentifier("recipe-manager-mode")

                List {
                    if !RecipeCatalog.loadIssues.isEmpty {
                        Section {
                            Label("Some source recipes could not load. Your original looks are available.", systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                        }
                    }
                    if searchingRecipes {
                        Section {
                            Picker("Show", selection: $membership) {
                                ForEach(RecipeMembershipFilter.allCases) { option in Text(option.title).tag(option) }
                            }
                            .accessibilityIdentifier("recipe-membership-filter")
                        }
                        Section {
                            if filtered.isEmpty {
                                ContentUnavailableView("No matching recipes", systemImage: "magnifyingglass",
                                                       description: Text("Change your search or show all recipes."))
                            } else {
                                ForEach(filtered) { recipe in
                                    RecipeManagementRow(recipe: recipe, selectedRecipeID: selectedRecipeID,
                                                        enabled: preferences.isEnabled(recipe.id), onSelect: onSelect) { enabled in
                                        change { $0.setRecipe(recipe.id, enabled: enabled) }
                                    }
                                }
                            }
                        } header: {
                            Text("\(filtered.count) recipes")
                        }
                    } else {
                        Section {
                            Text("Choose what appears in the camera's quick menu. Favorites and edited looks are kept even when hidden.")
                                .font(.subheadline)
                                .foregroundStyle(FilmyTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Section {
                            ForEach(RecipeCatalog.packs) { pack in packRow(pack) }
                        } header: {
                            Text("\(RecipeCatalog.packs.count) packs / \(recipes.count) looks")
                        } footer: {
                            Text("A pack switch enables or hides every recipe in that pack. Open a pack to choose individual recipes. New packs start hidden.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("recipe-manager-list")
            }
            .background(FilmyTheme.background)
            .navigationTitle("Your quick menu")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search stocks, names, cameras")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { bulkMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("recipe-manager-done")
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Text("\(activeCount) of \(recipes.count) active")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .accessibilityIdentifier("recipe-manager-active-count")
                        Spacer()
                        if let undoState {
                            Button("Undo") {
                                preferences = undoState
                                self.undoState = nil
                            }
                            .frame(minWidth: 48, minHeight: 44)
                            .accessibilityIdentifier("recipe-manager-undo")
                        }
                    }
                }
            }
        }
        .tint(FilmyTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("recipe-library-manager")
    }

    private var bulkMenu: some View {
        Menu {
            Button("Enable all \(recipes.count) looks", systemImage: "checkmark.circle") {
                change { $0.setAll(RecipeCatalog.packs, enabled: true) }
            }
            .accessibilityIdentifier("recipe-enable-all")
            Button("Hide all looks", systemImage: "minus.circle") {
                change { $0.setAll(RecipeCatalog.packs, enabled: false) }
            }
            .accessibilityIdentifier("recipe-hide-all")
            Button("Use only my favorites", systemImage: "heart") {
                change { state in
                    state.setAll(RecipeCatalog.packs, enabled: false)
                    for id in favorites { state.setRecipe(id, enabled: true) }
                }
            }
            if searchingRecipes && !filtered.isEmpty {
                Divider()
                Button("Enable \(filtered.count) results") {
                    let ids = filtered.map(\.id)
                    change { state in for id in ids { state.setRecipe(id, enabled: true) } }
                }
                Button("Hide \(filtered.count) results") {
                    let ids = filtered.map(\.id)
                    change { state in for id in ids { state.setRecipe(id, enabled: false) } }
                }
            }
            Divider()
            Button("Restore original quick menu", systemImage: "arrow.counterclockwise") {
                change { $0.restoreDefaults() }
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("recipe-manager-actions")
    }

    private func packRow(_ pack: RecipePack) -> some View {
        let count = preferences.enabledCount(in: pack)
        return HStack(spacing: 12) {
            NavigationLink {
                RecipePackDetailView(preferences: $preferences, pack: pack,
                                     recipes: recipes.filter { RecipeCatalog.packID(for: $0) == pack.id },
                                     selectedRecipeID: selectedRecipeID, onSelect: onSelect)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pack.title).font(.headline)
                    Text(pack.subtitle).font(.caption).foregroundStyle(FilmyTheme.secondary)
                    Text("\(count) of \(pack.recipeIDs.count) active\(preferences.state(of: pack) == .mixed ? " / Mixed" : "")")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(count > 0 ? FilmyTheme.accent : FilmyTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("recipe-pack-\(pack.id)")
            Toggle("Enable \(pack.title)", isOn: Binding(
                get: { preferences.state(of: pack) == .on },
                set: { enabled in change { $0.setPack(pack, enabled: enabled) } }
            ))
            .labelsHidden()
            .frame(minWidth: 52, minHeight: 48)
            .accessibilityIdentifier("recipe-pack-toggle-\(pack.id)")
            .accessibilityValue("\(count) of \(pack.recipeIDs.count) active")
            .accessibilityHint("Changes every recipe in this pack. Mixed packs become fully enabled.")
        }
    }

    private func change(_ edit: (inout RecipeLibraryPreferences) -> Void) {
        undoState = preferences
        var updated = preferences
        edit(&updated)
        preferences = updated
        HapticFeedback.play(.selection)
    }
}

enum RecipeMembershipFilter: String, CaseIterable, Identifiable {
    case all, active, hidden, favorites
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func results(_ recipes: [FilmRecipe], query: String, filter: Self,
                        preferences: RecipeLibraryPreferences, favorites: Set<String>) -> [FilmRecipe] {
        LookLibraryIndex.results(in: recipes, query: query, filter: .all, favorites: favorites).filter { recipe in
            switch filter {
            case .all: return true
            case .active: return preferences.isEnabled(recipe.id)
            case .hidden: return !preferences.isEnabled(recipe.id)
            case .favorites: return favorites.contains(recipe.id)
            }
        }
    }
}

private struct RecipePackDetailView: View {
    @Binding var preferences: RecipeLibraryPreferences
    let pack: RecipePack
    let recipes: [FilmRecipe]
    let selectedRecipeID: String
    let onSelect: (FilmRecipe) -> Void
    @State private var query = ""
    @State private var undoState: RecipeLibraryPreferences?

    private var results: [FilmRecipe] {
        LookLibraryIndex.results(in: recipes, query: query, filter: .all, favorites: [])
    }

    var body: some View {
        List {
            Section {
                Text(pack.subtitle).font(.subheadline).foregroundStyle(FilmyTheme.secondary)
                Text("\(preferences.enabledCount(in: pack)) of \(pack.recipeIDs.count) in your quick menu")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                HStack {
                    Button("Enable pack") { change { $0.setPack(pack, enabled: true) } }
                        .accessibilityIdentifier("recipe-pack-enable")
                    Spacer()
                    Button("Hide pack") { change { $0.setPack(pack, enabled: false) } }
                        .accessibilityIdentifier("recipe-pack-hide")
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
            }
            Section {
                ForEach(results) { recipe in
                    RecipeManagementRow(recipe: recipe, selectedRecipeID: selectedRecipeID,
                                        enabled: preferences.isEnabled(recipe.id), onSelect: onSelect) { enabled in
                        change { $0.setRecipe(recipe.id, enabled: enabled) }
                    }
                }
                if results.isEmpty { Text("No matching recipes in this pack.").foregroundStyle(FilmyTheme.secondary) }
            } footer: {
                Text("Tapping a recipe applies it. Its switch only changes quick-menu visibility; the active camera look is not replaced.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(FilmyTheme.background)
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this pack")
        .toolbar {
            if let undoState {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo") {
                        preferences = undoState
                        self.undoState = nil
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private func change(_ edit: (inout RecipeLibraryPreferences) -> Void) {
        undoState = preferences
        var updated = preferences
        edit(&updated)
        preferences = updated
        HapticFeedback.play(.selection)
    }
}

private struct RecipeManagementRow: View {
    let recipe: FilmRecipe
    let selectedRecipeID: String
    let enabled: Bool
    let onSelect: (FilmRecipe) -> Void
    let onToggle: (Bool) -> Void
    @State private var showingSource = false
    @AppStorage("favoriteRecipeIDs.v1") private var favoriteData = Data()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var favorite: Bool { LookLibraryIndex.favorites(from: favoriteData).contains(recipe.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    RecipeSwatch(recipe: recipe, showsLabel: false)
                        .frame(width: 48, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                Button { onSelect(recipe) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name).font(.subheadline.weight(.semibold)).foregroundStyle(FilmyTheme.primary)
                        Text(recipe.filmBase.officialName).font(.caption).foregroundStyle(FilmyTheme.secondary)
                        if recipe.id == selectedRecipeID {
                            Text(enabled ? "Current look" : "Current look / hidden from menu")
                                .font(.caption.weight(.semibold)).foregroundStyle(FilmyTheme.accent)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("manage-select-\(recipe.id)")
                .accessibilityLabel("Use \(recipe.name)")
                Toggle("\(recipe.name) in quick menu", isOn: Binding(get: { enabled }, set: onToggle))
                    .labelsHidden()
                    .frame(minWidth: 52, minHeight: 48)
                    .accessibilityIdentifier("manage-toggle-\(recipe.id)")
            }
            HStack(spacing: 12) {
                Button { showingSource = true } label: {
                    Label("Details", systemImage: "info.circle").font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("manage-source-\(recipe.id)")
                Spacer(minLength: 4)
                Button {
                    var ids = LookLibraryIndex.favorites(from: favoriteData)
                    if favorite { ids.remove(recipe.id) } else { ids.insert(recipe.id) }
                    favoriteData = LookLibraryIndex.encodeFavorites(ids)
                } label: {
                    Label(favorite ? "Saved" : "Favorite", systemImage: favorite ? "heart.fill" : "heart")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                .accessibilityLabel(favorite ? "Unfavorite \(recipe.name)" : "Favorite \(recipe.name)")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingSource) { RecipeSourceSheet(recipe: recipe) }
    }
}

struct RecipeSourceSheet: View {
    let recipe: FilmRecipe
    @Environment(\.dismiss) private var dismiss

    private var original: FilmRecipe {
        FilmRecipe(id: "source-comparison-neutral", name: "As shot", subtitle: "Neutral processed sample", filmBase: .standard)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        VStack {
                            RecipeSwatch(recipe: original, showsLabel: false).aspectRatio(0.75, contentMode: .fit)
                            Text("As shot").font(.caption)
                        }
                        VStack {
                            RecipeSwatch(recipe: recipe, showsLabel: false).aspectRatio(0.75, contentMode: .fit)
                            Text("Filmy render").font(.caption)
                        }
                    }
                    .frame(maxHeight: 300)
                    .accessibilityLabel("Same sample before and after the Filmy recipe")
                    Text(recipe.name).font(.title2.weight(.bold)).textSelection(.enabled)
                    Text(recipe.provenance.cameraSource == nil ? "Independent approximation / not camera-calibrated" : "Source settings traced / render not camera-calibrated")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(FilmyTheme.accent)
                }
                if let source = recipe.provenance.cameraSource {
                    Section("Original recipe") {
                        LabeledContent("Name", value: source.originalName)
                        LabeledContent("Publisher", value: source.publisher.title)
                        LabeledContent("Source scope", value: source.cameraScope)
                        LabeledContent("Retrieved", value: source.retrievedOn)
                        if let url = source.sourceURL {
                            Link("Read the original recipe and creator credits", destination: url)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("recipe-original-source")
                        }
                    }
                    Section {
                        ForEach(source.settings.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key).font(.caption).foregroundStyle(FilmyTheme.secondary)
                                Text(source.settings[key] ?? "").font(.body).textSelection(.enabled)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                    } header: {
                        Text("Published camera settings")
                    } footer: {
                        Text("These are source-camera values. Filmy's editable controls use a different, normalized scale.")
                    }
                    Section {
                        DisclosureGroup("Rendering differences") {
                            Text("An iPhone image is already processed. Fujifilm sensor color, auto white balance, ISO noise, and highlight headroom cannot be recovered from its JPEG or HEIC pixels.")
                            Text("Exposure compensation is shooting advice, not an extra baked-in exposure. Source recipes start without added halation, vignette, or a second blue tint.")
                            ForEach(source.limitations, id: \.self) { note in Text(note) }
                        }
                        .font(.subheadline)
                    }
                } else {
                    Section("Reference and fidelity") {
                        Text(recipe.id.hasPrefix("camera-")
                             ? "A documented camera mode with neutral menu controls, rendered through an independent approximation. No additional creative finishing is added."
                             : "This existing look has authored controls, not a verified transcription of a particular camera recipe. Use Camera Foundations for clean mode starting points.")
                        ForEach(recipe.provenance.references, id: \.self) { reference in
                            if let url = URL(string: reference.url) { Link(reference.title, destination: url).frame(minHeight: 44) }
                        }
                    }
                }
                Section {
                    Text(recipe.provenance.disclaimer).font(.caption).foregroundStyle(FilmyTheme.secondary)
                    Text("Renderer: \(recipe.provenance.rendererVersion)").font(.caption).textSelection(.enabled)
                    if recipe.provenance.source == .userModified {
                        Text("Your controls are customized. The source settings above still describe the unedited reference.").font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(FilmyTheme.background)
            .navigationTitle("Recipe details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("recipe-source-done")
                }
            }
        }
        .tint(FilmyTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("recipe-source-sheet")
    }
}
