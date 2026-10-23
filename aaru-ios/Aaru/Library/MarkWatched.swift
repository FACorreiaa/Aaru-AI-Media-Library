import AaruAPI
import SwiftUI

typealias ShowWatched = Components.Schemas.ShowWatched

/// A write the server refused or never got, in words for the toast or banner.
struct WriteFailure: Error {
    let message: String
}

// MARK: Writes

extension LibraryModel {
    /// PROG-005: every aired episode of a show, ticked as one action the toast can undo. The
    /// server decides the status: an ended show becomes Watched, a running one stays Watching,
    /// caught up. The shelf takes the answer at once.
    func markShowWatched(_ id: String, api: Client?) async -> Result<ShowWatched, WriteFailure> {
        let name = entry(id)?.title.title ?? "The show"
        guard let api else { return .failure(WriteFailure(message: "Aaru could not reach the server.")) }
        do {
            switch try await api.markShowWatched(path: .init(id: id)) {
            case let .ok(response):
                let result = try response.body.json
                var forShelf = result.entry
                forShelf.watchedEpisodes = nil
                upsert(forShelf)
                if result.action != nil {
                    // The widgets' up next and week follow (WID-001).
                    Task { try? await WidgetSync.refresh(api: api) }
                    #if os(iOS)
                        let seasons = Set((result.entry.watchedEpisodes ?? []).map(\.season))
                        for season in seasons {
                            await NowWatching.seasonWatched(libraryItemId: id, season: season)
                        }
                    #endif
                }
                return .success(result)
            case let .default(_, error):
                return .failure(WriteFailure(
                    message: (try? error.body.json.message) ?? "\(name) could not be marked watched."
                ))
            }
        } catch {
            return .failure(
                WriteFailure(message: "\(name) could not be marked watched. Aaru could not reach the server.")
            )
        }
    }

    /// A film's "Mark watched": status Watched, the same PATCH as the title page. Returns what
    /// went wrong, or nil.
    func markFilmWatched(_ id: String, api: Client?) async -> String? {
        let name = entry(id)?.title.title ?? "The film"
        guard let api else { return "Aaru could not reach the server." }
        do {
            switch try await api.updateLibraryItem(path: .init(id: id), body: .json(.init(status: .finished))) {
            case let .ok(response):
                try upsert(response.body.json)
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "\(name) could not be marked watched."
            }
        } catch {
            return "\(name) could not be marked watched. Aaru could not reach the server."
        }
    }

    /// Takes back one journaled action (`/v1/actions/{id}/undo`), then reloads the items it
    /// touched so the shelf, and Home through the revision, show the state before it.
    func undo(_ actionID: String, api: Client?) async -> String? {
        guard let api else { return "Aaru could not reach the server." }
        do {
            switch try await api.undoAction(path: .init(id: actionID)) {
            case let .ok(response):
                let action = try response.body.json
                for id in action.itemIds {
                    if case let .ok(item) = try? await api.getLibraryItem(path: .init(id: id)),
                       var entry = try? item.body.json
                    {
                        entry.watchedEpisodes = nil
                        upsert(entry)
                    }
                }
                Task { try? await WidgetSync.refresh(api: api) }
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "That could not be undone."
            }
        } catch {
            return "That could not be undone. Aaru could not reach the server."
        }
    }
}

extension ShowWatched {
    /// The toast's words (DESIGN.md §9): "Marked 62 episodes of Severance", "Caught up on 18
    /// aired episodes" for a running show, "Already caught up" when nothing changed.
    var toastMessage: String {
        guard action != nil else { return "Already caught up" }
        let title = entry.title.title
        if entry.status == .finished {
            return episodes == 0
                ? "Marked \(title) watched"
                : "Marked \(episodes == 1 ? "1 episode" : "\(episodes.formatted()) episodes") of \(title)"
        }
        return episodes == 0
            ? "\(title) is caught up"
            : "Caught up on \(episodes == 1 ? "1 aired episode" : "\(episodes.formatted()) aired episodes")"
    }
}

extension ToastCenter {
    /// The toast for a whole-show mark: with Undo when it wrote, quiet when it did not.
    func showWatched(_ result: ShowWatched, undo: @escaping @MainActor (String) async -> String?) {
        guard let action = result.action else {
            show(result.toastMessage, tone: .quiet)
            return
        }
        let id = action.id
        show(result.toastMessage) { await undo(id) }
    }
}

// MARK: The long-press menu

/// "Mark show watched" for a show or anime, "Mark watched" for a film, in a card's long-press
/// menu (DESIGN.md §9). Applies at once, never a dialog; the toast offers Undo. Absent when
/// nothing is left to mark.
struct MarkWatchedButton: View {
    let entry: LibraryEntry
    let api: Client?
    let library: LibraryModel
    /// Nil in previews.
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    /// Finished, or every aired episode already ticked: nothing to mark. Books and albums have
    /// their own words and are not offered.
    static func applies(to entry: LibraryEntry) -> Bool {
        guard entry.status != .finished else { return false }
        switch entry.title._type {
        case .movie:
            return true
        case .show:
            guard let progress = entry.progress else { return true }
            return progress.watchedCount < progress.airedCount
        case .book, .album:
            return false
        }
    }

    var body: some View {
        if Self.applies(to: entry) {
            Button(
                entry.title._type == .show ? "Mark show watched" : "Mark watched",
                systemImage: "checkmark.circle"
            ) {
                Task { await mark() }
            }
        }
    }

    private func mark() async {
        let id = entry.id
        if entry.title._type == .movie {
            if let problem = await library.markFilmWatched(id, api: api) {
                toasts?.show(problem, tone: .problem)
            } else {
                toasts?.show("Marked \(entry.title.title) watched")
            }
            return
        }
        switch await library.markShowWatched(id, api: api) {
        case let .success(result):
            toasts?.showWatched(result) { [library, api] actionID in
                await library.undo(actionID, api: api)
            }
        case let .failure(failure):
            toasts?.show(failure.message, tone: .problem)
        }
    }
}

/// A long press's preview: the poster, the name, and how far along it is ("38 of 62 episodes"),
/// so the user sees what they are about to finish.
struct ProgressPreview: View {
    let entry: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            PosterView(url: entry.title.posterURL, kind: entry.title.mediaKind)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.title)
                    .font(.headline)
                    .foregroundStyle(Color(.ink))
                    .lineLimit(2)
                if let progress = entry.progress, progress.airedCount > 0 {
                    Text("\(progress.watchedCount) of \(progress.airedCount) episodes")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color(.muted))
                }
            }
        }
        .frame(width: 200, alignment: .leading)
        .padding(16)
        .background(Color(.paper))
    }
}

extension View {
    /// A card's long-press menu: Mark watched first, when there is something to mark, then
    /// `items`, over a preview of the poster and the progress. Without the shelf's entry (not
    /// synced yet) only `items`.
    @ViewBuilder
    func markWatchedMenu(
        _ entry: LibraryEntry?,
        api: Client?,
        library: LibraryModel,
        @ViewBuilder items: () -> some View
    ) -> some View {
        let more = items()
        if let entry {
            contextMenu {
                MarkWatchedButton(entry: entry, api: api, library: library)
                more
            } preview: {
                ProgressPreview(entry: entry)
            }
        } else {
            contextMenu { more }
        }
    }
}
