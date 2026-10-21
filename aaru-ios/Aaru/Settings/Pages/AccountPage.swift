import AaruAPI
import SwiftUI

/// Settings → Account: who you are, how you sign in, friends, notifications, and the city Aaru
/// looks for concerts around.
struct AccountSettings: View {
    let api: Client?
    let imports: ImportsModel
    @Binding var account: Components.Schemas.Me?
    var onSignOut: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: account?.displayName ?? "Not set")
                LabeledContent("Signed in with", value: Self.providers(account))
                if let clientID = AppEnvironment.googleClientID, let account, !account.providers.contains(.google) {
                    LinkGoogleButton(api: api, clientID: clientID, account: $account)
                }
                Button("Sign out", action: onSignOut)
            }
            FriendsSection(api: api)
            ConcertPlaceSection(api: api) { imports.problem = $0 }
            #if os(iOS)
                if let push = PushRegistrar.current {
                    NotificationsSection(push: push)
                }
            #endif
        }
        .settingsForm(imports)
        .navigationTitle("Account")
        .task { account = await Self.load(api) ?? account }
    }

    static func load(_ api: Client?) async -> Components.Schemas.Me? {
        guard let api, case let .ok(response) = try? await api.getMe() else { return nil }
        return try? response.body.json
    }

    static func providers(_ account: Components.Schemas.Me?) -> String {
        let names = (account?.providers ?? []).map { provider in
            switch provider {
            case .apple: "Apple"
            case .google: "Google"
            case .email: "Email"
            }
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }
}

#if os(iOS)
    /// Alerts: a new episode of a show you are watching, and groups (GRP-012).
    private struct NotificationsSection: View {
        let push: PushRegistrar

        var body: some View {
            Section {
                Toggle("New episodes", isOn: binding(\.airing))
                Toggle("Mentions in groups", isOn: binding(\.groupMentions))
                Toggle("Group invites", isOn: binding(\.groupInvites))
                if let problem = push.problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "New episodes of shows you are watching, mentions in groups you have not muted, and invites. "
                        + "A mention says who tagged you and where, never what they wrote."
                )
            }
            .task { await push.loadSetting() }
        }

        private func binding(_ setting: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
            Binding(get: { push.settings[keyPath: setting] }, set: { value in Task { await push.set(setting, value) } })
        }
    }
#endif
