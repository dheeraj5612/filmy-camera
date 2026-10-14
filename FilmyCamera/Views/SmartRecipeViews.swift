import CoreImage
import SwiftUI

/// One source for both Smart looks entry forms (`SmartRecipeEntryPoint`, `CompactSmartRecipeEntry`).
enum SmartRecipeEntryCopy {
    static let openerLabel = "Smart looks"
    static let openerHint = "See three looks matched to this scene."
    static func quickApplyTitle(_ name: String) -> String { "Use \(name)" }
}

/// Uses the existing fixed-height indicator row, so recommendations cannot resize the viewfinder.
struct SmartRecipeEntryPoint: View {
    @ObservedObject var store: SmartRecipeStore
    let selectedID: String
    let canApply: Bool
    let onOpen: () -> Void
    let onApply: (String) -> Void
    let onUndo: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isUndoShowing: Bool { store.undo?.appliedID == selectedID }
    private var quickApplyOption: SmartRecipeOption? {
        guard !isUndoShowing, let option = store.options.first, option.id != selectedID else { return nil }
        return option
    }
    private var hasAction: Bool { isUndoShowing || quickApplyOption != nil }

    var body: some View {
        if dynamicTypeSize <= .large {
            entry(named: true)
        } else {
            // Larger text: the name needs room for itself plus a 44 pt action slot whether or not a
            // suggestion is showing, so the form never changes with the suggestion.
            ViewThatFits(in: .horizontal) {
                entry(named: true)
                entry(named: false)
            }
        }
    }

    private func entry(named: Bool) -> some View {
        HStack(spacing: 0) {
            capsule(named: named)
            if !hasAction {
                // Holds the action slot's ideal width for the fit test only; invisible, takes no taps.
                Color.clear
                    .frame(width: FilmyTheme.minimumHitTarget, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 290, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func capsule(named: Bool) -> some View {
        HStack(spacing: 0) {
            opener(named: named)
            action
        }
        .font(.caption2.weight(.bold))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(FilmyTheme.accent)
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private func opener(named: Bool) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                if named {
                    Text(SmartRecipeEntryCopy.openerLabel).lineLimit(1)
                }
            }
            .font(.caption2.weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, named ? 10 : 0)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(SmartRecipeEntryCopy.openerLabel)
        .accessibilityValue(store.status.entryValue)
        .accessibilityHint(SmartRecipeEntryCopy.openerHint)
        .accessibilityIdentifier("smart-recipes-open")
        .layoutPriority(1)
    }

    @ViewBuilder private var action: some View {
        if isUndoShowing {
            undoButton
        } else if let option = quickApplyOption {
            quickApplyButton(option)
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Text("Undo")
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .disabled(!canApply)
        .accessibilityLabel("Undo smart look")
        .accessibilityIdentifier("smart-recipes-undo")
    }

    private func quickApplyButton(_ option: SmartRecipeOption) -> some View {
        let title = SmartRecipeEntryCopy.quickApplyTitle(option.recipe.name)
        return Button { onApply(option.id) } label: {
            Text(title).lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(minWidth: FilmyTheme.minimumHitTarget, idealWidth: FilmyTheme.minimumHitTarget,
                       minHeight: FilmyTheme.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .disabled(!canApply)
        .accessibilityLabel(title)
        .accessibilityIdentifier("smart-recipes-quick-apply")
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
        let options = self.options
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
                        Picker("Style", selection: Binding(
                            get: { store.intent },
                            set: { intent in store.setIntent(intent) }
                        )) {
                            ForEach(SmartRecipeIntent.allCases, id: \.self) { intent in Text(intent.title).tag(intent) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("smart-recipes-intent")
                        if let snapshot, !options.isEmpty {
                            Toggle("Show the original frame", isOn: $showOriginal)
                                .font(.subheadline)
                                .accessibilityIdentifier("smart-recipes-original")
                            ForEach(options) { option in optionCard(option, snapshot: snapshot) }
                            Text("Previews use the frame from when you opened this. Applying a look changes the next photo, not saved ones.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            emptyState
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("On your phone. No account or uploads.", systemImage: "lock.shield")
                        Text("No face identity is inferred or stored. Turning suggestions off stops analysis.")
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
    private static var isPhoneWarm: Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        return thermal == .serious || thermal == .critical
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("No suggestions yet. Point the camera at a scene, then reopen.", systemImage: "viewfinder")
                .fixedSize(horizontal: false, vertical: true)
            if Self.isPhoneWarm {
                Label(SmartRecipeStore.Status.cooling.title, systemImage: "thermometer.high")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button(action: onClose) {
                Label("Back to camera", systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("smart-recipes-empty-close")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-recipes-empty")
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
                Text(showOriginal ? "Original" : "Preparing preview")
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
