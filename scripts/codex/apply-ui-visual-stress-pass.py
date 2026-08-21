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


recipe_picker_path = "FilmyCamera/Views/RecipePickerView.swift"

replace_once(
    recipe_picker_path,
    '''                    .onChange(of: selectedRecipeID) { _, newValue in
                        guard !reduceMotion else { return }
                        withAnimation(.snappy(duration: 0.24)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
''',
    '''                    .onChange(of: selectedRecipeID) { _, newValue in
                        if reduceMotion {
                            proxy.scrollTo(newValue, anchor: .center)
                        } else {
                            withAnimation(.snappy(duration: 0.24)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
'''
)

replace_once(
    recipe_picker_path,
    '''}

struct RecipeDetailView: View {
''',
    '''}

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
'''
)

replace_once(
    recipe_picker_path,
    '''    @Environment(\.dismiss) private var dismiss
    @State private var draft: FilmRecipe
''',
    '''    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: FilmRecipe
'''
)

replace_once(
    recipe_picker_path,
    '''                    Button {
                        commitDraft()
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
''',
    '''                    Button {
                        commitDraft()
                        onSelect()
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: primaryActionIcon)
                            Text(primaryActionTitle)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.center)
                        }
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.background)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            FilmyTheme.accent.opacity(primaryActionDisabled ? 0.55 : 1),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(primaryActionDisabled)
                    .accessibilityLabel(primaryActionAccessibilityLabel)
                    .accessibilityHint(
                        primaryActionDisabled
                            ? "This recipe is already active"
                            : "Applies any pending changes and returns to the camera"
                    )
'''
)

replace_once(
    recipe_picker_path,
    '''        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
''',
    '''        .accessibilityElement(children: .contain)
    }

    private var hasPendingChanges: Bool {
        draft != recipe
    }

    private var primaryActionDisabled: Bool {
        isSelected && !hasPendingChanges
    }

    private var primaryActionTitle: String {
        if isSelected {
            return hasPendingChanges ? "Apply to Selected Recipe" : "Selected Recipe"
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
                : "\(recipe.name) is selected"
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
'''
)

replace_once(
    recipe_picker_path,
    '''        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 1) {
''',
    '''        LazyVGrid(columns: detailGridColumns, spacing: 1) {
'''
)

replace_once(
    recipe_picker_path,
    '''            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                alignment: .leading,
                spacing: 1
            ) {
''',
    '''            LazyVGrid(
                columns: detailGridColumns,
                alignment: .leading,
                spacing: 1
            ) {
'''
)

replace_once(
    recipe_picker_path,
    '''                if onUpdate != nil {
                    Button("Apply") {
                        commitDraft()
                        dismiss()
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.background)
                    .padding(.horizontal, 12)
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
                    .background(FilmyTheme.accent, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply recipe changes")
                    .accessibilityHint("Saves the current recipe controls and closes the editor")
                }

                Button("Reset") {
                    draft = originalRecipe
                    onReset?()
                }
''',
    '''                if onUpdate != nil {
                    Button("Apply") {
                        commitDraft()
                        dismiss()
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(FilmyTheme.background)
                    .padding(.horizontal, 12)
                    .frame(minHeight: FilmyTheme.minimumHitTarget)
                    .background(
                        FilmyTheme.accent.opacity(hasPendingChanges ? 1 : 0.55),
                        in: Capsule()
                    )
                    .buttonStyle(.plain)
                    .disabled(!hasPendingChanges)
                    .accessibilityLabel("Apply recipe changes")
                    .accessibilityValue(hasPendingChanges ? "Changes pending" : "No changes")
                    .accessibilityHint("Saves the current recipe controls and closes the editor")
                }

                Button("Reset") {
                    draft = originalRecipe
                }
'''
)

replace_once(
    recipe_picker_path,
    '''    private func commitDraft() {
        guard draft != recipe else { return }
        onUpdate?(draft)
    }
''',
    '''    private func commitDraft() {
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
'''
)

replace_once(
    recipe_picker_path,
    '''private struct RecipeChoiceRow<Selection: Hashable, Content: View>: View {
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
''',
    '''private struct RecipeChoiceRow<Selection: Hashable, Content: View>: View {
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
    }
}
'''
)

replace_once(
    recipe_picker_path,
    '''private struct RecipeSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let step: Double?
''',
    '''private struct RecipeSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let step: Double?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
'''
)

replace_once(
    recipe_picker_path,
    '''        VStack(alignment: .leading, spacing: 7) {
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

            if let step {
''',
    '''        VStack(alignment: .leading, spacing: 7) {
            valueHeader

            if let step {
'''
)

replace_once(
    recipe_picker_path,
    '''        .frame(minHeight: 52, alignment: .center)
    }
}
''',
    '''        .frame(minHeight: 52, alignment: .center)
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
'''
)

Path("FilmyCameraTests/RecipeDetailCommitPolicyTests.swift").write_text(
    '''import XCTest
@testable import FilmyCamera

final class RecipeDetailCommitPolicyTests: XCTestCase {
    func testUnchangedDraftDoesNotCommit() {
        let recipe = FilmRecipe.builtIns[0]

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: recipe,
                current: recipe,
                original: recipe
            ),
            .none
        )
    }

    func testReturningCustomizedRecipeToOriginalRequestsReset() {
        let original = FilmRecipe.builtIns[1]
        var current = original
        current.exposure = 1
        current.markUserModified(parentRecipeID: original.id)

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: original,
                current: current,
                original: original
            ),
            .reset
        )
    }

    func testEditedDraftRequestsUpdate() {
        let original = FilmRecipe.builtIns[2]
        var draft = original
        draft.contrast = 1.35

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: draft,
                current: original,
                original: original
            ),
            .update(draft)
        )
    }

    func testEditingAfterResetPreviewRequestsUpdateInsteadOfReset() {
        let original = FilmRecipe.builtIns[3]
        var current = original
        current.exposure = 0.7
        current.markUserModified(parentRecipeID: original.id)
        var draft = original
        draft.saturation = 1.3

        XCTAssertEqual(
            RecipeDetailCommitPolicy.action(
                draft: draft,
                current: current,
                original: original
            ),
            .update(draft)
        )
    }
}
''',
    encoding="utf-8"
)
