import AaruAPI
import SwiftUI

// MARK: The Field's sections

extension HomeScreen {
    /// The owl beside "The Field", and when it is: "Tuesday evening · 3 in progress · 2 airing today".
    var header: some View {
        HStack(spacing: AaruSpace.medium) {
            OwlHead(size: 48, idle: true)
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
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder var tonightSection: some View {
        if let tonight = model.tonight {
            TonightCard(
                tonight: tonight,
                isPending: model.pending.contains(tonight.primary.libraryItemId),
                wide: !compact,
                onSetAside: { pick, verdict in Task { await model.setAside(pick, verdict: verdict) } },
                onMarkWatched: { entry in Task { await model.markNextWatched(entry) } }
            )
            .padding(.horizontal, 20)
        }
    }

    /// The Field's composer (AG-006): a capture opens its review, then waits below until approved.
    @ViewBuilder var composer: some View {
        if let imports {
            CaptureComposer(imports: imports) { openedCapture = $0 }
                .padding(.horizontal, 20)
        }
    }

    /// Captures being read or waiting for approval, newest first.
    var waitingCaptures: [ImportJob] {
        (imports?.jobs ?? []).filter(\.isWaitingCapture).sorted { $0.createdAt > $1.createdAt }
    }

    /// Captures and agent requests waiting for the user (AG-006, OUT-004), with the owl while any wait.
    @ViewBuilder var waitingSection: some View {
        if let api, !model.plans.isEmpty || !waitingCaptures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Waiting for you").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    AgentPresence(label: "Aaru is waiting for your answer")
                }
                if let imports {
                    ForEach(waitingCaptures, id: \.id) { job in
                        NavigationLink {
                            ImportDetailView(id: job.id, imports: imports, library: library, lists: lists, api: api)
                        } label: {
                            CaptureCard(job: job)
                        }
                        .buttonStyle(.plain)
                    }
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

    /// The user's own rows. Continue watching leaves out the show Tonight already leads with,
    /// and whatever is playing now.
    @ViewBuilder var ownRows: some View {
        let playing = model.playingItemIds
        let continuing = model.continueWatching.filter { entry in
            guard !playing.contains(entry.libraryItemId) else { return false }
            guard let lead = model.tonight?.primary.markable else { return true }
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
                        .markWatchedMenu(library.entry(entry.libraryItemId), api: api, library: library) {
                            #if os(iOS)
                                // Starts the Live Activity; not "Start watching", which is a row (UX-052).
                                Button("Watching now…", systemImage: "play.circle") {
                                    Task { await model.startWatching(entry) }
                                }
                            #endif
                        }
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
                    .markWatchedMenu(library.entry(entry.libraryItemId), api: api, library: library) {}
                }
            }
        }
        if !model.startable.isEmpty {
            HomeRow(title: "Start watching") {
                ForEach(model.startable, id: \.libraryItemId) { entry in
                    StartCard(entry: entry, width: cardWidth(.poster))
                        .markWatchedMenu(library.entry(entry.libraryItemId), api: api, library: library) {}
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
            CountChips(counts: counts) { onShowLibrary(LibraryFilter(status: $0)) }
        }
    }

    private var lastImport: ImportJob? {
        // Captures wait under "Waiting for you" instead.
        imports?.jobs.filter { !$0.isCapture }.max { $0.createdAt < $1.createdAt }
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
