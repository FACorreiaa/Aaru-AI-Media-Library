import AaruAPI
import SwiftUI

/// Settings on iPhone and iPad (DESIGN.md §18): the system Settings shape, a grouped list of the
/// eight pages, each its own page. A sheet from the account button on iPhone, the sidebar's
/// Settings row on iPad. The Mac shows the same pages as panes (`SettingsWindow`).
struct SettingsView: View {
    let context: SettingsContext
    /// The sheet needs a way out; the iPad sidebar row does not.
    var showsDone = false

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.settingsPath) {
            Form {
                Section {
                    NavigationLink(value: SettingsRoute.page(.account)) {
                        AccountSummary(account: context.models.account, social: context.models.social)
                    }
                }
                Section {
                    row(.friends)
                    row(.notifications)
                }
                Section {
                    row(.imports)
                    row(.connections)
                    row(.data)
                }
                Section {
                    row(.about)
                }
                Section {
                    row(.delete)
                }
            }
            .paperPage()
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                SettingsRouteView(route: route, context: context) { router.settingsPath.append($0) }
            }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .task {
                await context.models.account.load()
                await context.models.social.load()
            }
        }
    }

    private func row(_ page: SettingsPage) -> some View {
        NavigationLink(value: SettingsRoute.page(page)) {
            SettingsRowLabel(page)
        }
    }
}

/// One Settings route's view: a page, an import job, or History. The iPhone/iPad stack and the
/// Mac panes both draw pages through this, so each page has one view on every platform.
struct SettingsRouteView: View {
    let route: SettingsRoute
    let context: SettingsContext
    /// Pushes onto whichever stack holds this view (an import job after it starts).
    var push: (SettingsRoute) -> Void

    var body: some View {
        switch route {
        case let .page(page):
            SettingsPageView(page: page, context: context, push: push)
        case let .job(id):
            ImportDetailView(id: id, context: context)
        case .history:
            HistoryView(model: context.models.history) { await context.refreshLibrary() }
        }
    }
}

/// The page itself, without a stack around it.
struct SettingsPageView: View {
    let page: SettingsPage
    let context: SettingsContext
    var push: (SettingsRoute) -> Void
    /// Mac: Delete account sits at the bottom of the Account pane.
    var includesDeleteInAccount = false

    var body: some View {
        switch page {
        case .account:
            AccountPage(
                account: context.models.account, social: context.models.social, onSignOut: context.onSignOut,
                onDeleteAccount: includesDeleteInAccount ? context.onDeleteAccount : nil
            )
        case .friends:
            FriendsPage(api: context.api, social: context.models.social)
        case .notifications:
            NotificationsPage(model: context.models.notifications)
        case .imports:
            ImportPage(imports: context.imports) { push(.job($0)) }
        case .connections:
            ConnectionsPage(model: context.models.connections, api: context.api)
        case .data:
            DataPage(model: context.models.data, api: context.api)
        case .about:
            AboutView()
        case .delete:
            DeleteAccountPage(onDeleteAccount: context.onDeleteAccount)
        }
    }
}

/// The top row: who is signed in, the way Settings on iPhone starts with your name.
private struct AccountSummary: View {
    let account: AccountModel
    let social: SocialModel
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
                Text(social.displayName ?? account.profile?.displayName ?? social.handle.map { "@\($0)" } ?? "Account")
                    .font(.title3)
                    .foregroundStyle(Color(.ink))
                Text(account.providers == "—" ? "Name, handle, sign-in" : "Signed in with \(account.providers)")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
        }
        .padding(.vertical, 4)
    }
}

/// A page's row: its symbol in a small tinted square, as in the system Settings. Delete account
/// reads in danger.
struct SettingsRowLabel: View {
    let page: SettingsPage
    @ScaledMetric(relativeTo: .body) private var side = 28

    init(_ page: SettingsPage) {
        self.page = page
    }

    var body: some View {
        Label {
            Text(page.title).foregroundStyle(page == .delete ? Color(.danger) : Color(.ink))
        } icon: {
            Image(systemName: page.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.onAccent))
                .frame(width: side, height: side)
                .background(page.tint, in: .rect(cornerRadius: side / 4, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Every Settings page reads the same: on paper (`paperPage()`), with its own problem below (UX-029).
    func settingsPage(_ title: String, problem: Binding<String?>) -> some View {
        paperPage()
            .navigationTitle(title)
            .safeAreaInset(edge: .bottom) {
                ProblemBanner(message: problem.wrappedValue) { problem.wrappedValue = nil }
            }
    }
}
