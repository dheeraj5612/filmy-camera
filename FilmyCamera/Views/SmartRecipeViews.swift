import CoreImage
import SwiftUI

/// Uses the existing fixed-height indicator row, so recommendations cannot resize the viewfinder.
struct SmartRecipeEntryPoint: View {
    @ObservedObject var store: SmartRecipeStore
    let selectedID: String
    let canApply: Bool
    let onOpen: () -> Void
    let onApply: (String) -> Void
    let onUndo: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text(store.options.first?.recipe.name ?? store.status.title).lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Smart look suggestions")
            .accessibilityValue(store.options.first?.recipe.name ?? store.status.title)
            .accessibilityHint("Compare three scene-matched recipes. Suggestions never change your look automatically.")
            .accessibilityIdentifier("smart-recipes-open")
            if store.undo?.appliedID == selectedID {
                Button("Undo", action: onUndo)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!canApply)
                    .accessibilityLabel("Undo smart look")
                    .accessibilityIdentifier("smart-recipes-undo")
            } else if let option = store.options.first, option.id != selectedID {
                Button("Apply") { onApply(option.id) }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!canApply)
                    .accessibilityLabel("Apply \(option.recipe.name)")
                    .accessibilityIdentifier("smart-recipes-quick-apply")
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(FilmyTheme.accent)
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .background(Color.white.opacity(0.07), in: Capsule())
        .frame(maxWidth: 290, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Freeze the source and catalog when opening. Recommendations must not move beneath a finger or VoiceOver.
struct SmartRecipeSheet: View {
    @ObservedObject var store: SmartRecipeStore
    let snapshot: SmartRecipeSnapshot?
    let selectedID: String
    let canApply: Bool
    let onApply: (String) -> Void
    let onClose: () -> Void
    @State private var showOriginal = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var options: [SmartRecipeOption] {
        guard store.isEnabled else { return [] }
        return snapshot?.options(intent: store.intent) ?? []
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Toggle("Suggest looks as I frame", isOn: Binding(
                        get: { store.isEnabled },
                        set: { isEnabled in store.setEnabled(isEnabled) }
                    ))
                        .accessibilityIdentifier("smart-recipes-enabled")
                    if store.isEnabled {
                        heading
                        Picker("Your direction", selection: Binding(
                            get: { store.intent },
                            set: { intent in store.setIntent(intent) }
                        )) {
                            ForEach(SmartRecipeIntent.allCases, id: \.self) { intent in Text(intent.title).tag(intent) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("smart-recipes-intent")
                        if let snapshot, !options.isEmpty {
                            Toggle("Compare with unfiltered frame", isOn: $showOriginal)
                                .font(.subheadline)
                                .accessibilityIdentifier("smart-recipes-original")
                            ForEach(options) { option in optionCard(option, snapshot: snapshot) }
                            Text("Previews use the same frozen viewfinder frame. Apply changes your live look and the next shot, not photos already saved.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Label("Return to the viewfinder and frame a scene to get suggestions.", systemImage: "viewfinder")
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                                .accessibilityIdentifier("smart-recipes-empty")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("On-device. No uploads or account required.", systemImage: "lock.shield")
                        Text("Scene recognition and light/color measurements suggest starting points, not a single correct look. No face identity is inferred or stored. Turning suggestions off stops analysis.")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(FilmyTheme.background)
            .navigationTitle("Smart looks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
            .tint(FilmyTheme.accent)
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot?.scene.kind.title ?? "Let the scene lead")
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("smart-recipes-scene")
            Text(snapshot?.usedVision == true ? "A few looks for this scene and its light." : "Suggestions based on the frame's light and color.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func optionCard(_ option: SmartRecipeOption, snapshot: SmartRecipeSnapshot) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    SmartRecipeThumbnail(snapshot: snapshot, recipe: option.recipe, showOriginal: showOriginal)
                        .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                    optionDetails(option)
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    SmartRecipeThumbnail(snapshot: snapshot, recipe: option.recipe, showOriginal: showOriginal)
                        .frame(width: 88, height: 120).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                    optionDetails(option)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
    }
    private func optionDetails(_ option: SmartRecipeOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(option.recipe.name).font(.headline)
            Text(option.reason).font(.subheadline).foregroundStyle(.secondary)
            Button { onApply(option.id) } label: {
                Label(option.id == selectedID ? "Already applied" : "Apply this look",
                      systemImage: option.id == selectedID ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply || option.id == selectedID)
            .accessibilityLabel(option.id == selectedID ? "\(option.recipe.name), already applied" : "Apply \(option.recipe.name)")
            .accessibilityIdentifier("smart-recipes-apply-\(option.id)")
        }
    }
}

private struct SmartRecipeThumbnailKey: Hashable {
    let frameID: UUID
    let recipe: FilmRecipe
}
private struct SmartRecipeRenderedThumbnail: @unchecked Sendable { let image: CGImage }

/// Serial rendering with cancellation checks prevents overlapping filter pipelines when intent changes.
private actor SmartRecipeThumbnailRenderer {
    static let shared = SmartRecipeThumbnailRenderer()
    func render(snapshot: SmartRecipeSnapshot, recipe: FilmRecipe) -> SmartRecipeRenderedThumbnail? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            let source = CIImage(cgImage: snapshot.image)
            let filtered = FilmRenderer.render(source, recipe: recipe, quality: .preview, grainSeed: FilmRenderer.canonicalGrainSeed)
            guard !Task.isCancelled,
                  let image = FilmRenderer.sharedContext.createCGImage(filtered, from: source.extent, format: .RGBA8,
                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB), deferred: false) else { return nil }
            return SmartRecipeRenderedThumbnail(image: image)
        }
    }
}

private struct SmartRecipeThumbnail: View {
    let snapshot: SmartRecipeSnapshot
    let recipe: FilmRecipe
    let showOriginal: Bool
    @State private var rendered: CGImage?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(decorative: showOriginal ? snapshot.image : rendered ?? snapshot.image, scale: 1)
                .resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            if showOriginal || rendered == nil {
                Text(showOriginal ? "Unfiltered" : "Preparing preview")
                    .font(.caption.weight(.semibold))
                    .padding(6).background(.ultraThinMaterial, in: Capsule()).padding(4)
            }
        }
        .background(Color.black)
        .task(id: SmartRecipeThumbnailKey(frameID: snapshot.id, recipe: recipe)) {
            rendered = nil
            let result = await SmartRecipeThumbnailRenderer.shared.render(snapshot: snapshot, recipe: recipe)
            guard !Task.isCancelled else { return }
            rendered = result?.image
        }
    }
}
