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
            eyebrow: "RECIPE-FIRST CAMERA",
            title: "Start with a feeling.",
            message: "Pick a film-inspired recipe before you shoot, then shape it until the frame feels like yours.",
            icon: "camera.aperture",
            detail: "Choose a look first",
            accent: FilmyTheme.accent
        ),
        Page(
            id: 1,
            eyebrow: "LIVE PREVIEW",
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
            accent: Color(red: 0.89, green: 0.52, blue: 0.38)
        )
    ]

    let onFinish: () -> Void

    @State private var selectedPage = 0

    var body: some View {
        ZStack {
            FilmyTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [Self.pages[selectedPage].accent.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 430
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
                .animation(.easeInOut(duration: 0.25), value: selectedPage)

                pageControls
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("onboarding-screen")
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 9) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FilmyTheme.accent)

                Text("FILMY CAMERA")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(FilmyTheme.primary)
            }

            Spacer()

            Button("Skip") {
                onFinish()
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(FilmyTheme.secondary)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .contentShape(Rectangle())
            .accessibilityIdentifier("onboarding-skip")
            .accessibilityHint("Go straight to the camera. You can change permissions later in Settings.")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                visual(for: page)

                VStack(alignment: .leading, spacing: 11) {
                    Text(page.eyebrow)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(page.accent)

                    Text(page.title)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.message)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(FilmyTheme.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Image(systemName: page.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(page.accent)
                        .frame(width: 30, height: 30)
                        .background(page.accent.opacity(0.12), in: Circle())

                    Text(page.detail)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(FilmyTheme.primary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    private func visual(for page: Page) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [page.accent.opacity(0.22), FilmyTheme.panel.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1)
                }

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(page.accent.opacity(0.16))
                        .frame(width: 112, height: 112)

                    Circle()
                        .stroke(page.accent.opacity(0.35), lineWidth: 1)
                        .frame(width: 112, height: 112)

                    Image(systemName: page.icon)
                        .font(.system(size: 43, weight: .light))
                        .foregroundStyle(page.accent)
                }

                HStack(spacing: 7) {
                    ForEach(Self.pages) { dotPage in
                        Capsule()
                            .fill(dotPage.id == page.id ? page.accent : Color.white.opacity(0.2))
                            .frame(width: dotPage.id == page.id ? 24 : 8, height: 6)
                    }
                }
            }
            .padding(.vertical, 36)
        }
        .frame(height: 250)
        .accessibilityHidden(true)
    }

    private var pageControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(Self.pages) { page in
                    Capsule()
                        .fill(page.id == selectedPage ? page.accent : Color.white.opacity(0.2))
                        .frame(width: page.id == selectedPage ? 24 : 7, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: selectedPage)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Introduction page \(selectedPage + 1) of \(Self.pages.count)")

            Button {
                if selectedPage == Self.pages.count - 1 {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedPage += 1
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selectedPage == Self.pages.count - 1 ? "Open camera" : "Continue")
                    Image(systemName: selectedPage == Self.pages.count - 1 ? "camera.fill" : "arrow.right")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(FilmyTheme.background)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(FilmyTheme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-continue")

            Button("Skip for now") {
                onFinish()
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(FilmyTheme.secondary)
            .frame(minWidth: FilmyTheme.minimumHitTarget, minHeight: FilmyTheme.minimumHitTarget)
            .accessibilityIdentifier("onboarding-skip-for-now")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }
}

#Preview {
    OnboardingView {}
}
