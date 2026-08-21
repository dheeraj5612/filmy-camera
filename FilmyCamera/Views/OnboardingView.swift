import SwiftUI

enum OnboardingStore {
    static let hasCompletedKey = "hasCompletedRecipeFirstOnboarding"
}

struct OnboardingView: View {
    private struct Page: Identifiable {
        let id: Int
        let eyebrow: String
        let title: String
        let message: String
        let icon: String
        let detail: String
        let accent: Color
    }

    private static let pages = [
        Page(
            id: 0,
            eyebrow: "CHOOSE YOUR FEELING",
            title: "Start with a feeling.",
            message: "Pick a film-inspired recipe before you shoot, then shape it until the frame feels like yours.",
            icon: "camera.aperture",
            detail: "Choose a feeling first",
            accent: FilmyTheme.accent
        ),
        Page(
            id: 1,
            eyebrow: "COMPOSE IN THE MOOD",
            title: "See the mood as you compose.",
            message: "Camera access lets Filmy Camera show your selected look in the live preview. You stay in control of when a frame is made.",
            icon: "viewfinder",
            detail: "Camera access powers preview",
            accent: FilmyTheme.mint
        ),
        Page(
            id: 2,
            eyebrow: "KEEP THE FRAME",
            title: "Save the finished photo.",
            message: "When you choose to keep a frame, Photos access lets you save it and revisit the recipe details in Roll.",
            icon: "photo.on.rectangle.angled",
            detail: "Save only when you choose",
            accent: FilmyTheme.accentWarm
        )
    ]

    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage = 0

    var body: some View {
        ZStack {
            FilmyTheme.background
                .ignoresSafeArea()

            LinearGradient(
                colors: [Self.pages[selectedPage].accent.opacity(0.1), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $selectedPage) {
                    ForEach(Self.pages) { page in
                        pageView(page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedPage)

                pageControls
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("onboarding-screen")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(FilmyTheme.accent)
                    .frame(width: 4, height: 26)
                .accessibilityHidden(true)

                Text("FILMY")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(FilmyTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            Text("\(String(format: "%02d", selectedPage + 1)) / \(String(format: "%02d", Self.pages.count))")
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundStyle(Self.pages[selectedPage].accent)
                .monospacedDigit()
                .accessibilityLabel("Introduction page \(selectedPage + 1) of \(Self.pages.count)")

            Button("Skip") {
                onFinish()
            }
            .font(.system(.subheadline, design: .default).weight(.semibold))
            .foregroundStyle(FilmyTheme.secondary)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .contentShape(Rectangle())
            .accessibilityIdentifier("onboarding-skip")
            .accessibilityHint("Go straight to the camera. You can change permissions later in Settings.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                visual(for: page)

                VStack(alignment: .leading, spacing: 10) {
                    Text(page.eyebrow)
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(page.accent)

                    Text(page.title)
                        .font(.system(size: 38, weight: .bold, design: .default))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.message)
                        .font(FilmyTheme.bodyFont)
                        .foregroundStyle(FilmyTheme.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: page.icon)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(page.accent)
                        .frame(width: 38, height: 38)
                            .background(page.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("THE POINT")
                            .font(.system(.caption2, design: .default).weight(.semibold))
                            .foregroundStyle(FilmyTheme.tertiary)

                        Text(page.detail)
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .foregroundStyle(FilmyTheme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FilmyTheme.line)
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(FilmyTheme.line)
                        .frame(height: 1)
                }
                .accessibilityElement(children: .combine)

                if page.id == 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(page.accent)
                        Text("Swipe to explore the looks")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(FilmyTheme.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
    }

    private func visual(for page: Page) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [page.accent.opacity(0.18), FilmyTheme.panel.opacity(0.96), Color.black.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    Text("FILMY / CAMERA")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.76))

                    Spacer(minLength: 12)

                    Text("FRAME \(String(format: "%02d", page.id + 1))")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(page.accent)
                        .monospacedDigit()
                }

                HStack(spacing: 5) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(page.accent.opacity(0.55))
                            .frame(width: 10, height: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

                Spacer(minLength: 8)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [page.accent.opacity(0.75), page.accent.opacity(0.16), Color.black.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(spacing: 8) {
                        Image(systemName: page.icon)
                            .font(.system(.largeTitle, weight: .light))
                            .foregroundStyle(.white.opacity(0.92))

                        Text(page.detail.uppercased())
                            .font(.system(.caption2, design: .rounded).weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 158)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    ViewfinderCorner(color: page.accent)
                        .padding(14)
                }
                .overlay(alignment: .topTrailing) {
                    ViewfinderCorner(color: page.accent)
                        .rotationEffect(.degrees(90))
                        .padding(14)
                }
                .overlay(alignment: .bottomTrailing) {
                    ViewfinderCorner(color: page.accent)
                        .rotationEffect(.degrees(180))
                        .padding(14)
                }
                .overlay(alignment: .bottomLeading) {
                    ViewfinderCorner(color: page.accent)
                        .rotationEffect(.degrees(270))
                        .padding(14)
                }

                HStack(spacing: 14) {
                    onboardingMetric(title: "LOOK", value: page.id == 0 ? "RECIPE" : "LIVE")
                    onboardingMetric(title: "FORMAT", value: "35 MM")
                    onboardingMetric(title: "STATE", value: page.id == 2 ? "KEPT" : "READY")
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 284)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityHidden(true)
        // The viewfinder card is decorative and already has an accessible
        // semantic explanation below it. Keep its typography bounded so a
        // large-text setting cannot make the fixed visual chrome collide.
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private func onboardingMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.8)

            Text(value)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    ForEach(Self.pages) { page in
                        Capsule()
                            .fill(page.id == selectedPage ? page.accent : Color.white.opacity(0.2))
                            .frame(width: page.id == selectedPage ? 28 : 7, height: 6)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedPage)
                    }
                }

                Spacer(minLength: 12)

                Text("Swipe or tap continue")
                        .font(.system(.caption2, design: .default).weight(.semibold))
                    .foregroundStyle(FilmyTheme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Introduction page \(selectedPage + 1) of \(Self.pages.count)")
            .accessibilityValue("Swipe left or right to explore")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selectedPage = min(selectedPage + 1, Self.pages.count - 1)
                case .decrement:
                    selectedPage = max(selectedPage - 1, 0)
                @unknown default:
                    break
                }
            }

            Button {
                if selectedPage == Self.pages.count - 1 {
                    onFinish()
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        selectedPage += 1
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selectedPage == Self.pages.count - 1 ? "Open camera" : "Continue")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: selectedPage == Self.pages.count - 1 ? "camera.fill" : "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.system(.headline, design: .default).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-continue")
            .accessibilityHint(selectedPage == Self.pages.count - 1 ? "Open the camera" : "Move to the next introduction page")

            Button("Skip for now") {
                onFinish()
            }
            .font(.system(.subheadline, design: .default).weight(.semibold))
            .foregroundStyle(FilmyTheme.secondary)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .contentShape(Rectangle())
            .accessibilityIdentifier("onboarding-skip-for-now")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}

private struct ViewfinderCorner: View {
    let color: Color

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 1, y: 20))
            path.addLine(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 20, y: 1))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView {}
}
