import AaruAPI
import SwiftUI

typealias WatchingItem = Components.Schemas.WatchingItem

/// The page "Show all N" pushes from Library's Now (APP-018), optionally scrolled to the backlog.
struct NowGroupRoute: Hashable {
    let group: NowGroupID
    var kind: MediaKind?
    var opensBacklog = false
}

/// APP-018 · one Now group on its own page: every title in progress, as big cards (Grid) or dense
/// rows (List), sorted by the last tick, the next airing (Watching) or A–Z, and narrowed by kind.
/// Watching carries each show's facts from `GET /v1/library/watching`; anime the user never
/// touched in Aaru sit apart, collapsed, in the Anime backlog. Matches the web's
/// `/app/library/now/{group}`.
struct NowGroupView: View {
    let route: NowGroupRoute
    let library: LibraryModel
    let api: Client?

    @AppStorage("library.now.layout") private var layout = LibraryLayout.grid
    @State private var kind: MediaKind?
    @State private var sort = NowSort.recent
    @State private var facts: [String: WatchingItem] = [:]
    @State private var showsBacklog: Bool
    @State private var problem: String?

    init(route: NowGroupRoute, library: LibraryModel, api: Client?) {
        self.route = route
        self.library = library
        self.api = api
        _kind = State(initialValue: route.kind.flatMap { route.group.kinds.contains($0) ? $0 : nil })
        _showsBacklog = State(initialValue: route.opensBacklog)
    }

    private var group: NowGroupID {
        route.group
    }

    private var sorts: [NowSort] {
        group == .watching ? NowSort.allCases : [.recent, .title]
    }

    var body: some View {
        let page = library.groupItems(group, kind: kind)
        let active = sorted(page.active, by: sort)
        // The backlog is long and untouched: A–Z unless another order is chosen.
        let backlog = sorted(page.backlog, by: sort == .recent ? .title : sort)
        ScrollViewReader { proxy in
            Group {
                if active.isEmpty, backlog.isEmpty {
                    ContentUnavailableView(
                        "Nothing \(group.title.lowercased()) right now",
                        systemImage: "play.square.stack",
                        description: Text("Titles you are in the middle of show up here.")
                    )
                } else if layout == .grid {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AaruSpace.section) {
                            if !active.isEmpty {
                                section(backlog.isEmpty ? nil : "Keeping up") { cards(active) }
                            }
                            if !backlog.isEmpty {
                                backlogHeader(count: backlog.count)
                                if showsBacklog {
                                    cards(backlog)
                                }
                            }
                        }
                        .padding(.vertical, AaruSpace.large)
                    }
                } else {
                    List {
                        if !active.isEmpty {
                            Section {
                                rows(active)
                            } header: {
                                if !backlog.isEmpty {
                                    Text("Keeping up")
                                }
                            }
                        }
                        if !backlog.isEmpty {
                            Section {
                                backlogHeader(count: backlog.count)
                                    .listRowInsets(EdgeInsets(
                                        top: AaruSpace.xxlarge,
                                        leading: 0,
                                        bottom: 8,
                                        trailing: 0
                                    ))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                if showsBacklog {
                                    rows(backlog)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .onAppear {
                if route.opensBacklog {
                    proxy.scrollTo("backlog", anchor: .top)
                }
            }
        }
        .navigationTitle(group.title)
        .toolbar { toolbar }
        .refreshable {
            await library.sync(api: api)
            await loadFacts()
        }
        .task { await loadFacts() }
        .safeAreaInset(edge: .bottom) {
            ProblemBanner(message: problem) { problem = nil }
        }
        .background(Color(.paper))
    }

    // MARK: Grid

    private func section(_ title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            if let title {
                Text(title)
                    .font(.aaruDisplay(.title2, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
            }
            content()
        }
    }

    private func cards(_ items: [NowItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
            ForEach(items) { item in
                NowCard(item: item, isPending: library.nowPending.contains(item.id), lines: lines(item)) { action in
                    run(action, on: item)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func backlogHeader(count: Int) -> some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            HStack(alignment: .firstTextBaseline) {
                Text("Anime backlog")
                    .font(.aaruDisplay(.title2, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(showsBacklog ? "Hide" : "Show \(count)") {
                    withAnimation { showsBacklog.toggle() }
                }
                .font(.subheadline.weight(.medium))
                .accessibilityHint(showsBacklog ? "Hides the backlog" : "Shows the backlog")
            }
            Text("Anime that came in as watching from an import and that you have not started here. "
                + "They stay in progress; tick an episode to bring one up.")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        }
        .padding(.horizontal, 16)
        .id("backlog")
    }

    // MARK: List

    private func rows(_ items: [NowItem]) -> some View {
        ForEach(items) { item in
            NavigationLink(value: item.entry.id) {
                NowRow(item: item, lines: lines(item))
            }
            .listRowBackground(Color.clear)
            .disabled(library.nowPending.contains(item.id))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let step = NowStep(item) {
                    Button(step.label, systemImage: "checkmark") { run(step.action, on: item) }
                        .tint(Color(.accent))
                }
            }
            .contextMenu {
                if let step = NowStep(item) {
                    Button(step.label, systemImage: "checkmark") { run(step.action, on: item) }
                }
            }
            .accessibilityActions {
                if let step = NowStep(item) {
                    Button(step.label) { run(step.action, on: item) }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Sort and filter", systemImage: "line.3.horizontal.decrease.circle") {
                Picker("Sort", selection: $sort) {
                    ForEach(sorts) { option in
                        Text(option.label(for: group)).tag(option)
                    }
                }
                if group.kinds.count > 1 {
                    Picker("Kind", selection: $kind) {
                        Text("All").tag(MediaKind?.none)
                        ForEach(group.kinds) { option in
                            Text(option.label).tag(MediaKind?.some(option))
                        }
                    }
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Layout", selection: $layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Data

    private func sorted(_ items: [NowItem], by sort: NowSort) -> [NowItem] {
        switch sort {
        case .recent:
            return items
        case .title:
            return items.sorted {
                $0.entry.title.title.localizedStandardCompare($1.entry.title.title) == .orderedAscending
            }
        case .airsNext:
            // The soonest next airing first; titles with none keep their recent order after.
            let dated = items.compactMap { item in facts[item.id]?.nextAiring.map { (item, $0.airsAt) } }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
            return dated + items.filter { facts[$0.id]?.nextAiring == nil }
        }
    }

    private func lines(_ item: NowItem) -> [String] {
        if group == .watching {
            return WatchingLines.lines(item, facts: facts[item.id], now: .now, calendar: .aaru)
        }
        return [item.entry.title.byline].compactMap(\.self)
    }

    private func run(_ action: NowAction, on item: NowItem) {
        Task {
            problem = await library.perform(action, on: item, api: api).problem
            await loadFacts()
        }
    }

    /// Watching's facts; the other groups need nothing past the library.
    private func loadFacts() async {
        guard group == .watching, let api, case let .ok(response) = try? await api.listWatching(),
              let body = try? response.body.json
        else { return }
        facts = Dictionary(body.items.map { ($0.entry.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The one next step a row offers by swipe, menu or VoiceOver: the next episode, the next
/// chapter, or finishing. A book's page is moved on its card or its page.
private struct NowStep {
    let label: String
    let action: NowAction

    init?(_ item: NowItem) {
        if let next = item.next {
            label = "Mark \(EpisodeCode.short(season: next.season, number: next.number)) watched"
            action = .tickNext
        } else if item.kind == .manga {
            let chapter = (item.entry.mangaProgress?.chapter ?? 0) + 1
            label = "Read ch. \(chapter)"
            action = .chapter(chapter)
        } else {
            switch item.kind {
            case .book: label = "Mark read"
            case .music: label = "Mark listened"
            default: label = "Mark watched"
            }
            action = .finish
        }
    }
}

/// A dense row on the List layout: thumb, title, progress, and the facts one per line.
private struct NowRow: View {
    let item: NowItem
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: AaruSpace.medium) {
            PosterView(url: item.entry.title.posterUrl.flatMap(URL.init(string:)), kind: item.kind)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                Text(item.entry.title.title).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: AaruSpace.small) {
                    Text(item.label).font(.subheadline.weight(.medium))
                    if let done = item.done {
                        ProgressView(value: done)
                            .frame(maxWidth: 96)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(lines, id: \.self) { line in
                    Text(line).lineLimit(1)
                }
                .font(.footnote)
                .foregroundStyle(Color(.muted))
            }
        }
        .padding(.vertical, AaruSpace.xsmall)
        .accessibilityElement(children: .combine)
    }
}

/// A Watching row's facts, one line each, empty ones left out: "Apple TV+ · Returning series",
/// "Next S2 · E3 · Who Is Alive", "7 left · 5h 40m", "Airs S2 · E10 · Tomorrow · 9:00 PM", or
/// "Caught up" when every aired episode is watched. The web's `watchingLines`.
enum WatchingLines {
    static func lines(_ item: NowItem, facts: WatchingItem?, now: Date, calendar: Calendar) -> [String] {
        let progress = item.entry.progress
        let channel = [item.entry.title.network, facts?.showStatus.map { ShowStatusLabel.label($0.rawValue) }]
            .compactMap(\.self).joined(separator: " · ")
        let next = item.next.map { next in
            (["Next " + EpisodeCode.short(season: next.season, number: next.number)] + [facts?.nextName]
                .compactMap(\.self)).joined(separator: " · ")
        }
        let left = facts?.remainingCount.flatMap { count -> String? in
            guard count > 0 else { return nil }
            let minutes = facts?.remainingMinutes ?? 0
            return minutes > 0 ? "\(count) left · \(durationLabel(minutes: minutes))" : "\(count) left"
        }
        let airs = facts?.nextAiring.map { airing in
            var parts = [
                "Airs " + EpisodeCode.short(season: airing.season, number: airing.number),
                HomeModel.airingLabel(
                    airsAt: airing.airsAt,
                    airTimeKnown: airing.airTimeKnown,
                    now: now,
                    calendar: calendar
                ),
            ]
            if airing.airTimeKnown {
                parts.append(airing.airsAt.formatted(date: .omitted, time: .shortened))
            }
            return parts.joined(separator: " · ")
        }
        let caughtUp = progress.map { $0.airedCount > 0 && $0.nextEpisode == nil } ?? false
        return [channel.isEmpty ? nil : channel, next, left, airs, caughtUp ? "Caught up" : nil].compactMap(\.self)
    }
}
