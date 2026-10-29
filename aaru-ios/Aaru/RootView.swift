import AaruAPI
import AuthenticationServices
import SwiftUI
import WidgetKit

/// Routes on the session: welcome when signed out, the app when signed in.
struct RootView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let imports: ImportsModel
    let settings: SettingsServices
    let groups: GroupsModel
    let realtime: RealtimeClient
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(ProgressModel.self) private var progress: ProgressModel?
    @Environment(PlusModel.self) private var plus: PlusModel?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var showsEmailSignIn = false
    @State private var errorMessage: String?
    /// A friend invite link (SOC-002). Opened signed out, it waits here through sign-in.
    @State private var pendingInvite: InviteLink?
    @State private var openInvite: InviteLink?
    /// A share link (SHR-002) opens signed in or out. "Add to my Aaru" signed out parks it here
    /// until sign-in, then it reopens and saves its title once.
    @State private var openShare: SharedLink?
    @State private var pendingShare: SharedLink?
    /// The undo toast after a bulk write (PROG-005), shared by every screen and sheet.
    @State private var toasts = ToastCenter()

    private var flow: AuthFlow {
        AuthFlow(api: api, session: session)
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                MainTabs(
                    api: api, library: library, lists: lists, imports: imports, groups: groups,
                    realtime: realtime, settings: settingsContext
                )
            } else {
                WelcomeView(
                    api: api,
                    signedOutByServer: session.wasSignedOutByServer,
                    onAppleAuthorization: { authorization, nonce in
                        Task { await run { try await flow.signInWithApple(authorization, rawNonce: nonce) } }
                    },
                    onAppleError: { error in
                        // Closing Apple's sheet is not an error worth showing.
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    },
                    onContinueWithEmail: { showsEmailSignIn = true },
                    onContinueWithGoogle: AppEnvironment.googleClientID.map { clientID in
                        { Task { await signInWithGoogle(clientID: clientID) } }
                    }
                )
                .sheet(isPresented: $showsEmailSignIn) {
                    EmailSignInSheet(flow: flow)
                }
            }
        }
        .sheet(item: $openInvite) { link in
            InviteSheet(api: api, link: link)
        }
        .sheet(item: $openShare) { link in
            SharePreviewView(api: api, link: link, library: library, lists: lists) { pendingShare = $0 }
        }
        // Share links and invites open signed out too; every other link waits for the app.
        .onOpenURL { url in
            if let share = SharedLink(url) {
                openShare = share
                return
            }
            guard let invite = InviteLink(url) else { return }
            if session.isSignedIn {
                openInvite = invite
            } else {
                pendingInvite = invite
            }
        }
        // A signed-out device keeps nothing of the last user's library.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn, let invite = pendingInvite {
                pendingInvite = nil
                openInvite = invite
            }
            if signedIn, let share = pendingShare {
                pendingShare = nil
                openShare = share
            }
            if !signedIn {
                openShare = nil
                pendingShare = nil
                library.reset()
                lists.reset()
                imports.reset()
                settings.reset()
                groups.reset()
                progress?.reset()
                plus?.reset()
                realtime.reset()
                router.reset()
                HomeCache().clear()
                WidgetSnapshotStore.clear()
                WidgetCenter.shared.reloadAllTimelines()
                #if os(iOS)
                    Task {
                        await NowWatching.endAll()
                        await NowPlayingActivity.endAll()
                        NowPlayingArtwork.clear()
                    }
                #endif
                toasts.dismiss()
            }
        }
        .alert("Could not sign in", isPresented: $errorMessage.isPresent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        // Outermost, so the sheets above (a widget's title, a push's request) carry it too.
        .toastCenter(toasts)
    }

    private var settingsContext: SettingsContext {
        SettingsContext(
            api: api, imports: imports, models: settings, library: library, lists: lists,
            onSignOut: { Task { await flow.signOut() } },
            onDeleteAccount: { await flow.deleteAccount() }
        )
    }

    private func signInWithGoogle(clientID: String) async {
        await run {
            let google = GoogleSignIn(clientID: clientID)
            if let token = try await google.token(using: webAuthenticationSession) {
                try await flow.signInWithGoogle(token)
            }
        }
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RootView(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil), imports: ImportsModel(api: nil),
        settings: SettingsServices(api: nil), groups: GroupsModel(api: nil, realtime: nil),
        realtime: RealtimeClient(baseURL: nil) { nil }
    )
    .environment(SessionStore(keychain: SessionKeychain(service: "preview")))
    .environment(AppRouter())
}
