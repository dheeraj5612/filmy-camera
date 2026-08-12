import SwiftUI

struct RecipePickerView: View {
    let recipes: [FilmRecipe]
    @Binding var selectedRecipeID: String
    let onOpenDetail: (FilmRecipe) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(recipes) { recipe in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
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
    let recipe: FilmRecipe
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FilmyTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    RecipeSwatch(recipe: recipe, compact: false)
                        .frame(height: 180)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.base.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(FilmyTheme.accent)

                        Text(recipe.name)
                            .font(.system(size: 31, weight: .black, design: .rounded))
                            .foregroundStyle(FilmyTheme.primary)

                        Text(recipe.detail)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(FilmyTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        ForEach(recipe.controlSummary, id: \.0) { control in
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
        .accessibilityLabel("Recipe details for \(recipe.name)")
    }
}
