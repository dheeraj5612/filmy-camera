import SwiftUI

/// Signal Frame: two open, offset rectangles become an F. No camera body,
/// aperture blades, or borrowed logo. Coordinates match the icon generator.
struct FilmyMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x + side * px / 32, y: y + side * py / 32)
        }
        var path = Path()
        // Outer exposure / upper arm; the cut at the right remains legible
        // even when the mark is only 18 points high in the camera header.
        path.move(to: point(4, 3))
        path.addLine(to: point(28, 3))
        path.addLine(to: point(28, 9))
        path.addLine(to: point(10, 9))
        path.addLine(to: point(10, 29))
        path.addLine(to: point(4, 29))
        path.closeSubpath()
        // Offset inner exposure. Its square terminal repeats the outer cut.
        path.move(to: point(14, 13))
        path.addLine(to: point(28, 13))
        path.addLine(to: point(28, 19))
        path.addLine(to: point(20, 19))
        path.addLine(to: point(20, 25))
        path.addLine(to: point(14, 25))
        path.closeSubpath()
        return path
    }
}

/// The G7X monogram uses the same square-terminal construction as Filmy's
/// mark. Coordinates mirror scripts/design/render_g7_identity.py exactly.
struct G7Mark: Shape {
    private let polygons: [[CGPoint]] = [
        [(1, 7), (11, 7), (11, 11), (5, 11), (5, 21), (7, 21),
         (7, 18), (6, 18), (6, 14), (11, 14), (11, 25), (1, 25)],
        [(13, 7), (22, 7), (22, 11), (17, 25), (13, 25), (18, 11), (13, 11)],
        [(23, 7), (27, 7), (28.5, 12), (30, 7), (34, 7),
         (30.5, 16), (34, 25), (30, 25), (28.5, 20), (27, 25),
         (23, 25), (26.5, 16)]
    ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: x + side * p.x / 32, y: y + side * p.y / 32)
        }
        var path = Path()
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            path.move(to: point(first))
            for vertex in polygon.dropFirst() { path.addLine(to: point(vertex)) }
            path.closeSubpath()
        }
        return path
    }
}

struct FilmyWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            Group {
                #if G7_APP
                G7Mark()
                #else
                FilmyMark()
                #endif
            }
                .foregroundStyle(FilmyTheme.accent)
                .frame(width: compact ? 20 : 28, height: compact ? 20 : 28)
            Text(AppConfiguration.wordmark)
                .font(.system(compact ? .subheadline : .title2, design: .rounded).weight(.heavy))
                .tracking(-0.8)
                .foregroundStyle(FilmyTheme.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppConfiguration.displayName)
    }
}

/// Consistent, non-colored photographic edges. A photo never inherits a
/// branded material, opacity, tint, shadow, or rounded crop from its parent.
struct FilmRegistration: View {
    var color = FilmyTheme.accent

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().frame(width: 16, height: 3)
            Rectangle().frame(width: 4, height: 3)
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
