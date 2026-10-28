import AaruAPI
import Foundation

/// One card in "Now" (APP-017): the entry, how far along it is, and the next step.
struct NowItem: Identifiable {
    let entry: LibraryEntry
    let kind: MediaKind
    /// 0…1 when the share done is known: episodes watched of aired, or a book's percent.
    let done: Double?
    let label: String
    /// The next episode to tick, for shows and anime.
    let next: Components.Schemas.EpisodeRef?

    var id: String {
        entry.id
    }

    init(_ entry: LibraryEntry) {
        self.entry = entry
        kind = MediaKind(type: entry.title._type, isAnime: entry.title.isAnime)
        if let progress = entry.progress, progress.airedCount > 0 {
            done = min(1, Double(progress.watchedCount) / Double(progress.airedCount))
            label = "\(progress.watchedCount) of \(progress.airedCount) episodes"
            next = progress.nextEpisode
        } else if kind == .manga {
            let chapter = entry.mangaProgress?.chapter
            done = chapter.flatMap { read in entry.title.chapterCount.map { min(1, Double(read) / Double($0)) } }
            label = entry.mangaProgressLabel ?? "Just started"
            next = nil
        } else if let percent = entry.bookProgress?.percent {
            done = min(1, percent / 100)
            label = "\(Int(percent.rounded()))%"
            next = nil
        } else if let page = entry.bookProgress?.page {
            let pages = entry.title.pageCount
            done = pages.map { min(1, Double(page) / Double($0)) }
            label = pages.map { "Page \(page) of \($0)" } ?? "Page \(page)"
            next = nil
        } else {
            done = nil
            switch kind {
            case .book: label = entry.title.pageCount.map { "\($0) pages" } ?? "Just started"
            case .music: label = "Listening"
            default: label = "Watching"
            }
            next = nil
        }
    }
}

/// What one Now write came back with: a problem to show, or the journaled action
/// (`/v1/actions/{id}/undo`) an Undo takes back. Both nil when nothing was sent or nothing changed.
struct NowWrite {
    var problem: String?
    var action: String?
}

/// One of Now's groups, and the page "Show all" opens (APP-018).
enum NowGroupID: String, CaseIterable, Hashable {
    case watching, reading, listening

    var title: String {
        switch self {
        case .watching: "Watching"
        case .reading: "Reading"
        case .listening: "Listening"
        }
    }

    var kinds: [MediaKind] {
        switch self {
        case .watching: [.film, .show, .anime]
        case .reading: [.book, .manga]
        case .listening: [.music]
        }
    }
}

/// "Watching" or "Reading", with its cards. Anime in the backlog are counted, not listed.
struct NowGroup: Identifiable {
    let id: NowGroupID
    let items: [NowItem]
    let backlogCount: Int

    var title: String {
        id.title
    }
}

/// How a Now group's page orders its titles (APP-018).
enum NowSort: String, CaseIterable, Identifiable {
    case recent, airsNext, title

    var id: String {
        rawValue
    }

    func label(for group: NowGroupID) -> String {
        switch self {
        case .recent: group == .watching ? "Recently watched" : "Recent"
        case .airsNext: "Airs next"
        case .title: "A–Z"
        }
    }
}

extension LibraryEntry {
    /// When the user last moved it: their newest tick in Aaru, else the item's last change.
    var recentAt: Date {
        lastWatchedAt ?? updatedAt
    }
}

extension LibraryModel {
    /// In-progress items of a kind (or all), newest activity first.
    private func nowItems(kind: MediaKind?) -> [NowItem] {
        inProgress.sorted { $0.recentAt > $1.recentAt }
            .map(NowItem.init)
            .filter { kind == nil || $0.kind == kind }
    }

    /// In-progress items grouped as the user would say it, newest first; a chosen kind keeps only
    /// that kind, and empty groups are left out. Anime the user never touched in Aaru (the
    /// server's `inBacklog`) wait on the Watching page instead.
    func nowGroups(kind: MediaKind?) -> [NowGroup] {
        let items = nowItems(kind: kind)
        return NowGroupID.allCases.map { group in
            let all = items.filter { group.kinds.contains($0.kind) }
            let active = all.filter { !$0.entry.inBacklog }
            return NowGroup(id: group, items: active, backlogCount: all.count - active.count)
        }
        .filter { !$0.items.isEmpty || $0.backlogCount > 0 }
    }

    /// One group's page: what the user keeps up with, and the anime backlog apart.
    func groupItems(_ group: NowGroupID, kind: MediaKind?) -> (active: [NowItem], backlog: [NowItem]) {
        let all = nowItems(kind: kind).filter { group.kinds.contains($0.kind) }
        return (all.filter { !$0.entry.inBacklog }, all.filter(\.entry.inBacklog))
    }

    /// Runs a card's or row's next step: a problem to show, or the action Undo takes back.
    func perform(_ action: NowAction, on item: NowItem, api: Client?) async -> NowWrite {
        switch action {
        case .tickNext: await tickNext(item, api: api)
        case let .page(page): await setPage(page, of: item, api: api)
        case let .chapter(chapter): await setChapter(chapter, of: item, api: api)
        case .finish: await finish(item, api: api)
        }
    }

    /// Ticks the next episode.
    func tickNext(_ item: NowItem, api: Client?) async -> NowWrite {
        guard let next = item.next else { return NowWrite() }
        return await write(item, api: api) { client in
            switch try await client.setEpisodeWatched(
                path: .init(id: item.entry.id, season: next.season, episode: next.number),
                body: .json(.init(watched: true))
            ) {
            case let .ok(response): return try .success(response.body.json, action: response.headers.aaruAction)
            case let .default(
                _,
                error
            ): return .failure((try? error.body.json.message) ?? "That episode was not saved.")
            }
        }
    }

    func setPage(_ page: Int, of item: NowItem, api: Client?) async -> NowWrite {
        await patch(item, .init(bookPage: page), api: api)
    }

    func setChapter(_ chapter: Int, of item: NowItem, api: Client?) async -> NowWrite {
        await patch(item, .init(mangaChapter: chapter), api: api)
    }

    func finish(_ item: NowItem, api: Client?) async -> NowWrite {
        await patch(item, .init(status: .finished), api: api)
    }

    private func patch(
        _ item: NowItem,
        _ body: Components.Schemas.LibraryItemPatch,
        api: Client?
    ) async -> NowWrite {
        await write(item, api: api) { client in
            switch try await client.updateLibraryItem(path: .init(id: item.entry.id), body: .json(body)) {
            case let .ok(response): return try .success(response.body.json, action: response.headers.aaruAction)
            case let .default(_, error): return .failure((try? error.body.json.message) ?? "That change was not saved.")
            }
        }
    }

    private enum Outcome {
        case success(LibraryEntry, action: String?)
        case failure(String)
    }

    /// One write per item at a time; the server's entry replaces the shelf's.
    private func write(
        _ item: NowItem,
        api: Client?,
        _ send: (Client) async throws -> Outcome
    ) async -> NowWrite {
        guard let api else { return NowWrite(problem: "Aaru could not reach the server.") }
        guard !nowPending.contains(item.id) else { return NowWrite() }
        nowPending.insert(item.id)
        defer { nowPending.remove(item.id) }
        do {
            switch try await send(api) {
            case .success(var entry, let action):
                entry.watchedEpisodes = nil
                upsert(entry)
                return NowWrite(action: action)
            case let .failure(message):
                return NowWrite(problem: message)
            }
        } catch {
            return NowWrite(problem: "Aaru could not reach the server.")
        }
    }
}
