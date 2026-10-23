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

/// "Watching" or "Reading", with its cards.
struct NowGroup: Identifiable {
    let title: String
    let items: [NowItem]

    var id: String {
        title
    }
}

extension LibraryModel {
    /// In-progress items grouped as the user would say it, newest first; a chosen kind keeps only
    /// that kind, and empty groups are left out.
    func nowGroups(kind: MediaKind?) -> [NowGroup] {
        let items = inProgress.map(NowItem.init).filter { kind == nil || $0.kind == kind }
        return [
            NowGroup(title: "Watching", items: items.filter { ![.book, .manga, .music].contains($0.kind) }),
            NowGroup(title: "Reading", items: items.filter { $0.kind == .book || $0.kind == .manga }),
            NowGroup(title: "Listening", items: items.filter { $0.kind == .music }),
        ].filter { !$0.items.isEmpty }
    }

    /// Ticks the next episode. Returns a problem to show, or nil.
    func tickNext(_ item: NowItem, api: Client?) async -> String? {
        guard let next = item.next else { return nil }
        return await write(item, api: api) { client in
            switch try await client.setEpisodeWatched(
                path: .init(id: item.entry.id, season: next.season, episode: next.number),
                body: .json(.init(watched: true))
            ) {
            case let .ok(response): return try .success(response.body.json)
            case let .default(
                _,
                error
            ): return .failure((try? error.body.json.message) ?? "That episode was not saved.")
            }
        }
    }

    func setPage(_ page: Int, of item: NowItem, api: Client?) async -> String? {
        await patch(item, .init(bookPage: page), api: api)
    }

    func setChapter(_ chapter: Int, of item: NowItem, api: Client?) async -> String? {
        await patch(item, .init(mangaChapter: chapter), api: api)
    }

    func finish(_ item: NowItem, api: Client?) async -> String? {
        await patch(item, .init(status: .finished), api: api)
    }

    private func patch(
        _ item: NowItem,
        _ body: Components.Schemas.LibraryItemPatch,
        api: Client?
    ) async -> String? {
        await write(item, api: api) { client in
            switch try await client.updateLibraryItem(path: .init(id: item.entry.id), body: .json(body)) {
            case let .ok(response): return try .success(response.body.json)
            case let .default(_, error): return .failure((try? error.body.json.message) ?? "That change was not saved.")
            }
        }
    }

    private enum Outcome {
        case success(LibraryEntry)
        case failure(String)
    }

    /// One write per item at a time; the server's entry replaces the shelf's.
    private func write(
        _ item: NowItem,
        api: Client?,
        _ send: (Client) async throws -> Outcome
    ) async -> String? {
        guard let api else { return "Aaru could not reach the server." }
        guard !nowPending.contains(item.id) else { return nil }
        nowPending.insert(item.id)
        defer { nowPending.remove(item.id) }
        do {
            switch try await send(api) {
            case var .success(entry):
                entry.watchedEpisodes = nil
                upsert(entry)
                return nil
            case let .failure(message):
                return message
            }
        } catch {
            return "Aaru could not reach the server."
        }
    }
}
