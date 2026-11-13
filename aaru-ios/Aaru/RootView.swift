import AaruAPI
import AuthenticationServices
import SwiftUI

/// Routes on the session: welcome when signed out, the app when signed in.
struct RootView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let imports: ImportsModel
    let settings: SettingsServices
    let groups: GroupsModel
    let realtime: RealtimeClient
    /// `AppServices.signedOut()`: resets every model when the session ends.
    let onSignedOut: @MainActor () -> Void
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AISharingModel.self) private var aiSharing
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
    /// The first run (ONB-001): whether this account still has it to do.
    @State private var onboarding = OnboardingGate.checking
    /// An invite or share link came in: it wins, and the first run waits for the next launch.
    @State private var onboardingDeferred = false
    /// The first run ended while the app was open: AI sharing is asked the next time it opens.
    @State private var firstRunEndedThisLaunch = false
    /// PRV-002: `Me`, read as the app opened, says this account is asked about AI sharing now.
    @State private var asksAISharing = false

    private var flow: AuthFlow {
        AuthFlow(api: api, session: session)
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                switch onboarding {
                case .checking:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.paper).ignoresSafeArea())
                case .pending:
                    OnboardingFlow(
                        api: api, library: library, notifications: settings.notifications, aiSharing: aiSharing
                    ) { openImport in
                        finishOnboarding(openImport: openImport)
                    }
                case .done:
                    // A branch, as the first run is: it covers the Mac's toolbar too.
                    if asksAISharing, aiSharing.state == .unanswered {
                        AISharingAskScreen(model: aiSharing)
                    } else {
                        MainTabs(
                            api: api, library: library, lists: lists, imports: imports, groups: groups,
                            realtime: realtime, settings: settingsContext
                        )
                    }
                }
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
                if session.isSignedIn {
                    deferOnboarding()
                }
                open(share)
                return
            }
            guard let invite = InviteLink(url) else { return }
            if session.isSignedIn {
                deferOnboarding()
                openInvite = invite
            } else {
                pendingInvite = invite
            }
        }
        // A signed-out device keeps nothing of the last user's library.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn, pendingInvite != nil || pendingShare != nil {
                deferOnboarding()
            }
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
                onboarding = .checking
                onboardingDeferred = false
                firstRunEndedThisLaunch = false
                asksAISharing = false
                OnboardingGate.forget()
                AISharingAsk.forget()
                onSignedOut()
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
        .task(id: session.token) { await checkOnboarding() }
        .onChange(of: aiSharing.state) { _, state in
            if state == .allowed || state == .declined {
                AISharingAsk.rememberAnswered()
            }
        }
    }

    // MARK: First run (ONB-001)

    /// Reads `Me` once per session, for `onboardingPending` and `aiSharing` (PRV-002). Never holds
    /// the app: a failed or slow call, or a server that does not send the fields, opens the app.
    /// Once the server says the first run is done and AI sharing has an answer, this device stops
    /// waiting for it and reads `Me` behind the app.
    private func checkOnboarding() async {
        guard session.isSignedIn, onboarding == .checking else { return }
        guard let api else {
            onboarding = .done
            return
        }
        if onboardingDeferred || (OnboardingGate.isKnownDone && AISharingAsk.isKnownAnswered) {
            onboarding = .done
            if let account = await OnboardingGate.fetchAccount(api), !Task.isCancelled {
                aiSharing.apply(account)
            }
            return
        }
        let account = await OnboardingGate.fetchAccount(api)
        guard !Task.isCancelled else { return }
        let pending = account.map { $0.onboardingPending ?? false }
        if let account {
            aiSharing.apply(account)
        }
        guard onboarding == .checking else { return }
        if pending == false {
            OnboardingGate.rememberDone()
        }
        // Never on a guess: with no `Me` there is no state, and nothing is asked.
        asksAISharing = !onboardingDeferred && AISharingAsk.asksOnOpen(
            onboardingPending: pending, state: aiSharing.state, firstRunEndedThisLaunch: firstRunEndedThisLaunch
        )
        onboarding = pending == true && !onboardingDeferred ? .pending : .done
    }

    /// A link is waiting: the app opens on it, and the first run stays pending on the server.
    private func deferOnboarding() {
        onboardingDeferred = true
        if onboarding != .done {
            onboarding = .done
        }
    }

    /// The flow ended (finished, skipped or "Bring your history instead"). Import opens once the
    /// app is up, as the share sheet does after other sheets go.
    private func finishOnboarding(openImport: Bool) {
        onboarding = .done
        firstRunEndedThisLaunch = true
        guard openImport else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            router.openSettings(.imports)
        }
    }

    /// Clears whatever sheet is up first: SwiftUI shows nothing when asked for a sheet over
    /// another, and setting the same link again would not retry. The share sheet follows once
    /// the others have gone.
    private func open(_ share: SharedLink) {
        openShare = nil
        openInvite = nil
        showsEmailSignIn = false
        router.closeSheets()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            openShare = share
        }
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
        realtime: RealtimeClient(baseURL: nil) { nil }, onSignedOut: {}
    )
    .environment(SessionStore(keychain: SessionKeychain(service: "preview")))
    .environment(AppRouter())
    .environment(AISharingModel(api: nil))
}
