import AaruAPI
import AuthenticationServices
import SwiftUI

/// The signed-out landing screen (DESIGN.md §0).
struct WelcomeView: View {
    let api: Client?
    /// The server ended the last session (a 401): say so instead of a silent sign-out (UX-090).
    var signedOutByServer = false
    /// Apple's authorization and the raw nonce whose hash it carries.
    var onAppleAuthorization: (ASAuthorization, String) -> Void
    var onAppleError: (any Error) -> Void
    var onContinueWithEmail: () -> Void
    /// Nil when this build has no Google client: the button is not shown.
    var onContinueWithGoogle: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @State private var nonce = ""

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
            Text("Everything you watch, read and listen to, in one library.")
                .font(.aaruDisplay(.largeTitle))
                .fixedSize(horizontal: false, vertical: true)
            Text("Films, shows, anime, books and albums, private by default.")
                .font(.title3)
                .foregroundStyle(Color(.muted))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                Pillar(symbol: "square.stack.3d.up", text: "One library, four plain statuses")
                Pillar(symbol: "lock", text: "Private by default. No public profile, no ads")
                Pillar(symbol: "arrow.down.doc", text: "Bring your history from Trakt, IMDb, Letterboxd and Goodreads")
            }
            .padding(.top, 4)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if signedOutByServer {
                Label("You were signed out. Sign in again.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(Color(.ink))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SignInWithAppleButton(.signIn) { request in
                nonce = SignInNonce.make()
                request.requestedScopes = [.fullName, .email]
                request.nonce = SignInNonce.sha256(nonce)
            } onCompletion: { result in
                switch result {
                case let .success(authorization): onAppleAuthorization(authorization, nonce)
                case let .failure(error): onAppleError(error)
                }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(Capsule())
            if let onContinueWithGoogle {
                Button("Continue with Google", action: onContinueWithGoogle)
                    .buttonStyle(OutlineCapsuleButtonStyle())
            }
            Button("Continue with email", action: onContinueWithEmail)
                .buttonStyle(OutlineCapsuleButtonStyle())
            #if DEBUG || BETA
                APIStatusLabel(api: api)
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

/// Full-width outlined capsule, the quiet partner of the Sign in with Apple button.
struct OutlineCapsuleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color(.ink))
            .overlay { Capsule().strokeBorder(Color(.ink).opacity(0.25), lineWidth: 1) }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Light") {
    WelcomeView(api: nil, onAppleAuthorization: { _, _ in }, onAppleError: { _ in }, onContinueWithEmail: {})
}

#Preview("Dark") {
    WelcomeView(api: nil, onAppleAuthorization: { _, _ in }, onAppleError: { _ in }, onContinueWithEmail: {})
        .preferredColorScheme(.dark)
}
