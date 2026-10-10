import SwiftUI

/// The signed-out landing screen. APP-002 connects both actions to `/v1/auth`.
struct WelcomeView: View {
    var onSignInWithApple: () -> Void
    var onContinueWithEmail: () -> Void

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    var body: some View {
        ScrollView {
            Group {
                if isWide {
                    HStack(alignment: .center, spacing: 56) {
                        MascotMedallion()
                            .frame(maxWidth: 380)
                        VStack(alignment: .leading, spacing: 32) {
                            copy
                            actions
                        }
                        .frame(maxWidth: 420)
                    }
                    .padding(48)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        MascotMedallion()
                            .frame(maxWidth: 230)
                            .frame(maxWidth: .infinity)
                        copy
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if !isWide {
                actions
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color(.paper))
            }
        }
        .background(Color(.paper).ignoresSafeArea())
        .foregroundStyle(Color(.ink))
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(.wordmark)
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .accessibilityLabel("Aaru")
            Text("Everything you watch and read, on one shelf.")
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("Films, shows, anime and books in one calm library.")
                .font(.title3)
                .foregroundStyle(Color(.muted))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                Pillar(symbol: "square.stack.3d.up", text: "One shelf, four plain statuses")
                Pillar(symbol: "lock", text: "Private by default. No public profile, no ads")
                Pillar(symbol: "arrow.down.doc", text: "Bring your history from Trakt, IMDb, Letterboxd and Goodreads")
            }
            .padding(.top, 4)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onSignInWithApple) {
                Label("Sign in with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            Button("Continue with email", action: onContinueWithEmail)
                .buttonStyle(CapsuleButtonStyle(prominent: false))
            #if DEBUG || BETA
                Text("\(AppEnvironment.channel) · \(AppEnvironment.apiBaseURL?.host() ?? "no API")")
                    .font(.caption2)
                    .foregroundStyle(Color(.muted))
                    .padding(.top, 4)
            #endif
        }
    }
}

/// The mascot on a paper disc, so its painted edge reads the same in light and dark.
private struct MascotMedallion: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.medallion))
            Image(.mascot)
                .resizable()
                .scaledToFit()
                .padding(.top, 10)
                .accessibilityLabel("Aaru's mascot, a small teal bird carrying books and a film reel")
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
    }
}

private struct Pillar: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
        }
        .font(.body)
    }
}

/// Full-width capsule. Prominent follows the Sign in with Apple contrast rule:
/// black on light, white on dark.
private struct CapsuleButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = prominent ? (scheme == .dark ? .white : .black) : .clear
        let text: Color = prominent ? (scheme == .dark ? .black : .white) : Color(.ink)
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(text)
            .background(fill, in: Capsule())
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(Color(.ink).opacity(0.25), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Light") {
    WelcomeView(onSignInWithApple: {}, onContinueWithEmail: {})
}

#Preview("Dark") {
    WelcomeView(onSignInWithApple: {}, onContinueWithEmail: {})
        .preferredColorScheme(.dark)
}
