import AaruAPI
import SwiftUI

/// The Sports destination (SPT-004): a sidebar tab on iPad and Mac. iPhone's tab bar is full,
/// so there Discover pushes `SportsView` from its toolbar.
struct SportsScreen: View {
    let api: Client?

    var body: some View {
        NavigationStack {
            SportsView(api: api)
        }
    }
}

/// Sports: Favorites (each follow with what is live, next and last) and Schedule (one local day
/// of the followed leagues, from a date strip). Near-live while the app is active: fetched again
/// every 90 seconds while something shown is live, and after a few seconds while the server is
/// still fetching. Lives only here: no Home rows, no library, no widgets.
struct SportsView: View {
    @State private var model: SportsModel
    @State private var showsSearch = false
    @State private var openEvent: SportEventLink?
    @Environment(\.scenePhase) private var scenePhase

    init(api: Client?) {
        _model = State(initialValue: SportsModel(api: api))
    }

    /// What the near-live task follows: a change restarts it (and fetches at once).
    private struct RefreshKey: Equatable {
        let section: SportsModel.Section
        let day: String
        let active: Bool
        let revision: Int
    }

    private var refreshKey: RefreshKey {
        RefreshKey(
            section: model.section, day: model.day.key, active: scenePhase == .active,
            revision: model.followRevision
        )
    }

    var body: some View {
        Group {
            if model.unavailable {
                ContentUnavailableView(
                    "Sports are off right now",
                    systemImage: "sportscourt",
                    description: Text("This server has Sports turned off.")
                )
            } else {
                switch model.section {
                case .favorites:
                    SportFavoritesView(model: model, onFind: { showsSearch = true }, onOpen: open)
                case .schedule:
                    SportScheduleView(model: model, onFind: { showsSearch = true }, onOpen: open)
                }
            }
        }
        .navigationTitle("Sports")
        #if os(iOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                sectionPicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
        #endif
            .toolbar {
                #if os(macOS)
                    ToolbarItem(placement: .principal) { sectionPicker.fixedSize() }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button("Find leagues and teams", systemImage: "magnifyingglass") { showsSearch = true }
                }
            }
            .task(id: refreshKey) {
                guard refreshKey.active else { return }
                model.rollDays()
                await model.keepFresh()
            }
            .refreshable { await model.reload() }
            .refreshesOnCommand(.sports) { await model.reload() }
            .sheet(isPresented: $showsSearch) {
                SportsSearchView(model: model)
            }
            .sheet(item: $openEvent) { link in
                SportEventDetailView(model: model, id: link.id)
            }
            .safeAreaInset(edge: .bottom) {
                ProblemBanner(message: model.problem) { model.problem = nil }
            }
            .background(Color(.paper))
    }

    private func open(_ event: SportEvent) {
        openEvent = SportEventLink(id: event.id)
    }

    private var sectionPicker: some View {
        Picker("Sports", selection: $model.section) {
            ForEach(SportsModel.Section.allCases) { section in
                Text(section.label).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct SportEventLink: Identifiable, Hashable {
    let id: String
}

// MARK: Previews

#Preview("Sports") {
    SportsScreen(api: nil)
        .environment(AppRouter())
}
