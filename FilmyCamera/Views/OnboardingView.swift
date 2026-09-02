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
            eyebrow: "CHOOSE A RECIPE",
            title: "Start with a feeling.",
            message: "Pick a film-inspired recipe before you shoot, then shape it until the frame feels like yours.",
            icon: "film.stack",
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

            RadialGradient(
                colors: [Self.pages[selectedPage].accent.opacity(0.16), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: selectedPage)

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
            HStack(spacing: 8) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FilmyTheme.accent)
                    .accessibilityHidden(true)

                Text("Filmy Camera")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(FilmyTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            Text("\(selectedPage + 1) of \(Self.pages.count)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(FilmyTheme.tertiary)
                .monospacedDigit()
                .accessibilityLabel("Introduction page \(selectedPage + 1) of \(Self.pages.count)")

            Button("Skip") {
                onFinish()
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
            VStack(alignment: .leading, spacing: 26) {
                visual(for: page)

                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: page.eyebrow, color: page.accent)

                    Text(page.title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.message)
                        .font(FilmyTheme.bodyFont)
                        .foregroundStyle(FilmyTheme.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center, spacing: 12) {
                    SettingIcon(systemName: page.icon, tint: page.accent)

                    Text(page.detail)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)
                }
                .padding(12)
                .background(FilmyTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(FilmyTheme.line, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Visuals

    @ViewBuilder
    private func visual(for page: Page) -> some View {
        Group {
            switch page.id {
            case 0:
                recipeFanVisual(accent: page.accent)
            case 1:
                viewfinderVisual(accent: page.accent)
            default:
                keptFrameVisual(accent: page.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .background(FilmyTheme.backgroundRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(FilmyTheme.lineStrong, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityHidden(true)
        // The visual is decorative and already has an accessible semantic
        // explanation below it. Keep its typography bounded so a large-text
        // setting cannot make the fixed chrome collide.
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    /// Three real recipe renders fanned like film boxes on a shelf.
    private func recipeFanVisual(accent: Color) -> some View {
        let recipes = [FilmRecipe.builtIns[6], FilmRecipe.builtIns[1], FilmRecipe.builtIns[2]]

        return ZStack {
            ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                let isCenter = index == 1
                VStack(spacing: 8) {
                    RecipeSwatch(recipe: recipe, isSelected: isCenter, compact: false, showsLabel: false)
                        .frame(width: 150, height: 104)
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)

                    Text(recipe.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isCenter ? accent : Color.white.opacity(0.7))
                }
                .rotationEffect(.degrees(Double(index - 1) * 9))
                .offset(x: CGFloat(index - 1) * 96, y: isCenter ? -8 : 22)
                .scaleEffect(isCenter ? 1 : 0.9)
                .zIndex(isCenter ? 1 : 0)
            }
        }
    }

    /// A miniature viewfinder: the live preview shows the recipe, the chrome
    /// stays at the edges, and the shutter waits for the photographer.
    private func viewfinderVisual(accent: Color) -> some View {
        ZStack {
            RecipeSwatch(recipe: FilmRecipe.builtIns[1], compact: false, showsLabel: false)
                .padding(-2)

            LinearGradient(
                colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .viewfinderCapsule()

                Spacer()

                HStack(spacing: 8) {
                    ForEach([1, 2, 6], id: \.self) { index in
                        RecipeSwatch(recipe: FilmRecipe.builtIns[index], isSelected: index == 1, compact: true, showsLabel: false)
                            .frame(width: 44, height: 30)
                    }
                }

                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 42, height: 42)
                    }
                    .padding(.top, 10)
            }
            .padding(16)
        }
    }

    /// A kept frame settling into the Roll with its recipe attached.
    private func keptFrameVisual(accent: Color) -> some View {
        ZStack {
            HStack(spacing: 4) {
                ForEach([2, 6, 4, 1], id: \.self) { index in
                    RecipeSwatch(recipe: FilmRecipe.builtIns[index], compact: true, showsLabel: false)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .opacity(0.5)
            .offset(y: 92)

            VStack(spacing: 12) {
                RecipeSwatch(recipe: FilmRecipe.builtIns[1], isSelected: true, compact: false, showsLabel: false)
                    .frame(width: 172, height: 118)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(FilmyTheme.background)
                            .frame(width: 24, height: 24)
                            .background(accent, in: Circle())
                            .padding(8)
                    }

                HStack(spacing: 6) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 10, weight: .bold))
                    Text("Muted Color")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text("·")
                    Text("Kept")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .viewfinderCapsule()
            }
            .offset(y: -30)
        }
    }

    // MARK: - Controls

    private var pageControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(Self.pages) { page in
                    Capsule()
                        .fill(page.id == selectedPage ? page.accent : Color.white.opacity(0.2))
                        .frame(width: page.id == selectedPage ? 26 : 7, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedPage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            }
            .buttonStyle(.filmyPrimary)
            .accessibilityIdentifier("onboarding-continue")
            .accessibilityHint(selectedPage == Self.pages.count - 1 ? "Open the camera" : "Move to the next introduction page")

            Button("Skip for now") {
                onFinish()
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(FilmyTheme.secondary)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .contentShape(Rectangle())
            .accessibilityIdentifier("onboarding-skip-for-now")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}

#Preview {
    OnboardingView {}
}
