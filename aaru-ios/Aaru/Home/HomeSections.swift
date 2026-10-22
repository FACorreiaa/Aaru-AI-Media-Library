import AaruAPI
import SwiftUI

// MARK: The Field's sections

extension HomeScreen {
    /// "The Field", and when it is: "Tuesday evening · 3 in progress · 2 airing today".
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The Field")
                .font(.aaruDisplay(.largeTitle, weight: .semibold))
                .foregroundStyle(Color(.ink))
                .accessibilityAddTraits(.isHeader)
            Text(model.fieldLine)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder var tonightSection: some View {
        if let tonight = model.tonight {
            TonightCard(
                tonight: tonight,
                isPending: model.pending.contains(tonight.primary.libraryItemId),
                wide: !compact
            ) { entry in Task { await model.markNextWatched(entry) } }
                .padding(.horizontal, 20)
        }
    }

    /// Agent requests waiting for the user (OUT-004), with the heron while any wait.
    @ViewBuilder var waitingSection: some View {
        if let api, !model.plans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Waiting for you").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    AgentPresence(label: "Aaru is waiting for your answer")
                }
                ForEach(model.plans, id: \.id) { plan in
                    // The card posts `.aaruPlanDecided`; Home's observer updates the list. A new
                    // status draws the card again, so an answer given in a sheet shows here too.
                    PlanCardView(api: api, plan: plan)
                        .id("\(plan.id)-\(plan.status.rawValue)")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder var welcome: some View {
        if model.isEmpty {
            HomeWelcome(
                onSearch: { router.showsSearch = true },
                onImport: { router.openSettings(.imports) }
            )
            .padding(.horizontal, 20)
        }
    }

    /// The user's own rows. Continue watching leaves out the show Tonight already leads with.
    @ViewBuilder var ownRows: some View {
        let continuing = model.continueWatching.filter { entry in
            guard case let .continuing(lead)? = model.tonight?.primary else { return true }
            return entry.libraryItemId != lead.libraryItemId
        }
        if !continuing.isEmpty {
            HomeRow(title: "Continue watching") {
                ForEach(continuing, id: \.libraryItemId) { entry in
                    ContinueCard(
                        entry: entry,
                        width: cardWidth(.wide),
                        isPending: model.pending.contains(entry.libraryItemId)
                    ) { Task { await model.markNextWatched(entry) } }
                    #if os(iOS)
                        .contextMenu {
                            // Starts the Live Activity; not "Start watching", which is a row (UX-052).
                            Button("Watching now…", systemImage: "play.circle") {
                                Task { await model.startWatching(entry) }
                            }
                        }
                    #endif
                }
            }
        }
        if !model.listening.isEmpty {
            HomeRow(title: "Listening") {
                ForEach(model.listening) { row in
                    ListeningCard(row: row, width: cardWidth(.poster))
                }
            }
        }
        if !model.upcoming.isEmpty {
            HomeRow(title: "Airing soon", trailing: ("See calendar", { onSelectTab(.calendar) })) {
                ForEach(model.upcoming, id: \.cellID) { entry in
                    AiringCard(
                        entry: entry,
                        when: model.airingLabel(entry),
                        width: cardWidth(.banner)
                    ) {
                        Task {
                            if await !model.openAiring(entry) {
                                path.append(entry.libraryItemId)
                            }
                        }
                    }
                }
            }
        }
        if !model.startable.isEmpty {
            HomeRow(title: "Start watching") {
                ForEach(model.startable, id: \.libraryItemId) { entry in
                    StartCard(entry: entry, width: cardWidth(.poster))
                }
            }
        }
        if !model.unfinished.isEmpty {
            HomeRow(title: "Unfinished") {
                ForEach(model.unfinished, id: \.libraryItemId) { entry in
                    UnfinishedCard(
                        entry: entry,
                        reason: model.unfinishedLabel(entry),
                        width: cardWidth(.poster)
                    )
                }
            }
        }
    }

    /// The side column on wide screens, after the rows on a phone: the last import, the week,
    /// the library's counts, the recap and the user's lists.
    @ViewBuilder var sideBlocks: some View {
        if let imports, let job = lastImport {
            NavigationLink {
                ImportDetailView(id: job.id, imports: imports, library: library, lists: lists, api: api)
            } label: {
                LastImportCard(job: job)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        summary
        if let offered = RecapPeriod.offered(now: .now, calendar: model.calendar) {
            RecapBanner(period: offered) { recap = offered }
                .padding(.horizontal, 20)
        }
        if !lists.lists.isEmpty {
            HomeRow(title: "Your lists", trailing: ("All lists", { router.select(.lists) })) {
                ForEach(lists.lists, id: \.id) { list in
                    NavigationLink {
                        ListDetailView(listID: list.id, lists: lists, library: library, api: api)
                    } label: {
                        ListChip(list: list)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The streak and level (to Achievements), the last 7 days (to Insights, shown at zero too)
    /// and the library's counts (to Library, hidden at zero).
    @ViewBuilder private var summary: some View {
        if let achievements, let progress = achievements.progress {
            NavigationLink {
                AchievementsView(model: achievements)
            } label: {
                StreakBar(progress: progress, isLink: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        if let stats = model.weekStats {
            NavigationLink {
                InsightsView(api: api, library: library, model: InsightsModel(api: api, span: .last7))
            } label: {
                WeekStrip(stats: stats)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        if let counts = model.counts, counts.total > 0 {
            CountChips(counts: counts, onSelect: onShowLibrary)
        }
    }

    private var lastImport: ImportJob? {
        imports?.jobs.max { $0.createdAt < $1.createdAt }
    }

    /// DISC-001: the public rows, after the user's own. The first one leads to the Discover tab.
    var discoverRows: some View {
        let rows = model.discover.filter { !$0.items.isEmpty }
        return ForEach(rows, id: \.id) { row in
            HomeRow(
                title: row.title,
                note: row.note,
                trailing: row.id == rows.first?.id ? ("See Discover", { onSelectTab(.discover) }) : nil
            ) {
                ForEach(row.items) { hit in
                    DiscoverCard(
                        hit: hit,
                        libraryItemID: model.libraryItemID(hit),
                        badge: DiscoverCard.releaseBadge(hit.releaseDate, row: row.id),
                        width: cardWidth(.poster),
                        isAdding: model.adding.contains(hit.id)
                    ) { status in
                        Task { await model.add(hit, status: status) }
                    } onAddToList: {
                        listTarget = hit
                    }
                }
            }
        }
    }
}
