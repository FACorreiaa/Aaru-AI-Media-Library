import AaruAPI
import SwiftUI

/// What the shelf is narrowed to. Owned by the root so Home's count chips can set it.
struct LibraryFilter: Equatable {
    var kind: MediaKind?
    var status: LibraryStatus?
}

/// APP-003: the shelf. Filter by kind and status, poster grid or list, readable offline.
struct LibraryView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let imports: ImportsModel
    @Binding var filter: LibraryFilter
    var onSignOut: () -> Void
    var onDeleteAccount: () async -> String?

    @AppStorage("library.layout") private var layout = Layout.grid
    @State private var showsSearch = false
    @State private var showsInsights = false
    @State private var showsSettings = false
    @State private var recap: RecapPeriod?

    enum Layout: String {
        case grid, list
    }

    private var rows: [LibraryRow] {
        library.rows(kind: filter.kind, status: filter.status)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .safeAreaInset(edge: .top, spacing: 0) { filters }
                .toolbar { toolbar }
                .refreshable { await library.sync(api: api) }
                .task { await library.sync(api: api) }
                .navigationDestination(for: String.self) { id in
                    if let entry = library.entry(id) {
                        TitleDetailView(entry: entry, api: api, library: library, lists: lists)
                    }
                }
                .sheet(isPresented: $showsSettings) {
                    SettingsView(
                        api: api, imports: imports, library: library, lists: lists,
                        onSignOut: onSignOut, onDeleteAccount: onDeleteAccount
                    )
                }
                .sheet(isPresented: $showsSearch) {
                    SearchView(api: api, library: library, lists: lists)
                }
                .navigationDestination(isPresented: $showsInsights) { InsightsView(api: api) }
                .recapStory($recap, api: api)
                .background(Color(.paper))
        }
    }

    @ViewBuilder private var content: some View {
        if rows.isEmpty {
            if !library.hasSynced, library.isSyncing {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.rows.isEmpty {
                ContentUnavailableView {
                    Label("Your shelf is empty", systemImage: "books.vertical")
                } description: {
                    Text("Search for a film, show, anime or book to start.")
                } actions: {
                    Button("Search") { showsSearch = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No titles match these filters.")
                )
            }
        } else if layout == .grid {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 108, maximum: 160), spacing: 16, alignment: .top)],
                    spacing: 20
                ) {
                    ForEach(rows) { row in
                        NavigationLink(value: row.id) { PosterCard(row: row) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } else {
            List(rows) { row in
                NavigationLink(value: row.id) { LibraryListRow(row: row) }
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isOn: filter.kind == nil) { filter.kind = nil }
                    ForEach(MediaKind.allCases) { option in
                        FilterChip(title: option.label, isOn: filter.kind == option) { filter.kind = option }
                    }
                    Menu {
                        Picker("Status", selection: $filter.status) {
                            Text("Any status").tag(LibraryStatus?.none)
                            ForEach(LibraryStatus.allCases) { Text($0.label(for: filter.kind)).tag(Optional($0)) }
                        }
                    } label: {
                        Label(
                            filter.status?.label(for: filter.kind) ?? "Any status",
                            systemImage: "line.3.horizontal.decrease"
                        )
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.18)))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            if let problem = library.syncProblem {
                Label(problem, systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.paper))
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { showsSearch = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis.circle") {
                Picker("Layout", selection: $layout) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(Layout.grid)
                    Label("List", systemImage: "list.bullet").tag(Layout.list)
                }
                Divider()
                Button("Insights", systemImage: "chart.bar") { showsInsights = true }
                Menu("Recaps", systemImage: "sparkles") {
                    ForEach(RecapPeriod.shortcuts(now: .now, calendar: .aaru)) { period in
                        Button(period.label) { recap = period }
                    }
                }
                Button("Settings and imports", systemImage: "gearshape") { showsSettings = true }
                Button("Sign out", role: .destructive, action: onSignOut)
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color(.paper) : Color(.ink))
                .background(isOn ? Color(.ink) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(.ink).opacity(isOn ? 0 : 0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct PosterCard: View {
    let row: LibraryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: row.posterURL, kind: row.kind)
            Text(row.title)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
            Text(row.detail ?? row.status.label(for: row.kind))
                .font(.caption2)
                .foregroundStyle(Color(.muted))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryListRow: View {
    let row: LibraryRow

    var body: some View {
        HStack(spacing: 14) {
            PosterView(url: row.posterURL, kind: row.kind)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.body.weight(.medium)).lineLimit(2)
                Text([row.year.map(String.init), row.kind.label].compactMap(\.self).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                Text([row.status.label(for: row.kind), row.detail].compactMap(\.self).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}
