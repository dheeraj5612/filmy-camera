import SwiftUI

/// Compact details for one Roll frame. Rows come from `GalleryInfo.rows`, so
/// only data the model really has is listed.
struct GalleryInfoSheet: View {
    let rows: [GalleryInfo.Row]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            FilmyPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    content
                }
                .padding(FilmyTheme.pageMargin)
            }
        }
        .accessibilityIdentifier("gallery-info-sheet")
    }

    private var header: some View {
        HStack {
            Text("Frame info")
                .font(.system(.title3, design: .default).weight(.bold))
                .foregroundStyle(FilmyTheme.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Done") { dismiss() }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.accent)
                .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
                .accessibilityIdentifier("gallery-info-done")
        }
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            Text("No details are stored for this frame.")
                .font(.subheadline)
                .foregroundStyle(FilmyTheme.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    infoRow(row)
                }
            }
            .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: FilmyTheme.cornerRadius, style: .continuous))
        }
    }

    private func infoRow(_ row: GalleryInfo.Row) -> some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(row.title)
                .font(.subheadline)
                .foregroundStyle(FilmyTheme.secondary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Text(row.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FilmyTheme.primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: FilmyTheme.minimumHitTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
