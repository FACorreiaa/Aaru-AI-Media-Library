import AaruAPI
import SwiftUI

/// Settings → Account (§18): name and handle in one editor (UX-030), how you sign in and Link
/// Google, this device's appearance, and Sign out. On the Mac, Delete account sits at the bottom.
struct AccountPage: View {
    let account: AccountModel
    let social: SocialModel
    var onSignOut: () -> Void
    /// Mac only: the Account pane ends with Delete account. Nil leaves it out.
    var onDeleteAccount: (() async -> String?)?
    /// Nil in previews.
    @Environment(PlusModel.self) private var plus: PlusModel?

    var body: some View {
        @Bindable var account = account
        Form {
            Section {
                NavigationLink {
                    ProfileEditor(model: social)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(social.displayName ?? "No name yet").foregroundStyle(Color(.ink))
                        Text(social.handle.map { "@\($0)" } ?? "Choose a handle")
                            .font(.subheadline)
                            .foregroundStyle(social.handle == nil ? Color(.accent) : Color(.muted))
                    }
                }
            } header: {
                Text("Name and handle")
            } footer: {
                Text("Friends find you by your exact handle. Your name is what they see.")
            }
            if let plus {
                PlusSection(plus: plus)
            }
            Section("Signed in with") {
                LabeledContent("Signed in with", value: account.providers)
                if account.canLinkGoogle, let clientID = AppEnvironment.googleClientID {
                    LinkGoogleButton(account: account, clientID: clientID)
                }
            }
            Section("On this device") {
                AppearancePicker()
            }
            Section {
                Button("Sign out", action: onSignOut)
            }
            if let onDeleteAccount {
                DeleteAccountSection(onDeleteAccount: onDeleteAccount)
            }
        }
        .settingsPage("Account", problem: $account.problem)
        .task {
            await account.load()
            await social.load()
        }
    }
}
