import AaruAPI
import SwiftUI

/// APP-007: Settings as a list of groups, each its own page. A tab of its own; the Mac Settings
/// window (Cmd-,) shows the same pages as panes (`SettingsWindow`).
struct SettingsView: View {
    let api: Client?
    let imports: ImportsModel
    let library: LibraryModel
    let lists: ListsModel
    var onSignOut: () -> Void
    var onDeleteAccount: () async -> String?
    /// A sheet needs a way out; the Settings tab and the Mac Settings window do not.
    var showsDone = false

    @Environment(\.dismiss) private var dismiss
    @State private var account: Components.Schemas.Me?
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.settingsPath) {
            Form {
                Section {
                    NavigationLink(value: SettingsRoute.page(.account)) {
                        AccountSummary(account: account)
                    }
                }
                Section {
                    AppearancePicker()
                }
                Section {
                    NavigationLink(value: SettingsRoute.page(.imports)) {
                        SettingsRowLabel("Imports & export", systemImage: "tray.and.arrow.down.fill", tint: .blue)
                    }
                    NavigationLink(value: SettingsRoute.page(.connections)) {
                        SettingsRowLabel(
                            "Connected apps", systemImage: "app.connected.to.app.below.fill", tint: .green
                        )
                    }
                }
                Section {
                    NavigationLink(value: SettingsRoute.page(.about)) {
                        SettingsRowLabel("Insights & recaps", systemImage: "chart.bar.fill", tint: .orange)
                    }
                    NavigationLink(value: SettingsRoute.page(.about)) {
                        SettingsRowLabel("About", systemImage: "info", tint: .gray)
                    }
                }
            }
            .settingsForm(imports)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self, destination: destination)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .task {
                await imports.load()
                account = await AccountSettings.load(api) ?? account
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .page(.account):
            AccountSettings(api: api, imports: imports, account: $account, onSignOut: onSignOut)
        case .page(.imports):
            ImportsSettings(api: api, imports: imports) { router.settingsPath.append(.job($0)) }
        case .page(.connections):
            ConnectedAppsSettings(api: api, imports: imports)
        case .page:
            AboutView(onDeleteAccount: onDeleteAccount)
        case .history:
            EmptyView()
        case let .job(id):
            ImportDetailView(id: id, imports: imports, library: library, lists: lists, api: api)
        }
    }
}

/// The top row: who is signed in, the way Settings on iPhone starts with your name.
private struct AccountSummary: View {
    let account: Components.Schemas.Me?
    @ScaledMetric(relativeTo: .title) private var avatar = 48

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(.accent))
                .frame(width: avatar, height: avatar)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account?.displayName ?? "Account").font(.title3).foregroundStyle(Color(.ink))
                Text(AccountSettings.providers(account)).font(.subheadline).foregroundStyle(Color(.muted))
            }
        }
        .padding(.vertical, 4)
    }
}

/// A group's row: its symbol in a small tinted square, as in the system Settings.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var side = 28

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title).foregroundStyle(Color(.ink))
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(tint, in: .rect(cornerRadius: side / 4, style: .continuous))
        }
    }
}

extension View {
    /// Every Settings page reads the same: grouped, on paper, with the problem banner below.
    func settingsForm(_ imports: ImportsModel) -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .safeAreaInset(edge: .bottom) {
                ProblemBanner(message: imports.problem) { imports.problem = nil }
            }
    }
}
