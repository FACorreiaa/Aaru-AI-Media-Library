import Foundation
import Logging
import ServiceLifecycle

/// Keeps tracked shows' episodes current (JOB-001's second kind). The hydration timestamps
/// are the queue: each pass loads shows nobody has loaded yet (imports, a provider outage
/// at add time), then shows past their CAT-006 window. Title detail still hydrates on read.
/// Each pass also fills genres for titles stored before CAT-018.
struct CatalogRefresher: Sendable {
    /// Shows per pass. Each costs one TMDB call per season, so this stays well inside TMDB's
    /// limit while user traffic shares it.
    var passLimit = 40
    /// Titles per pass whose genres are filled; one provider call each.
    var genreLimit = 40
    /// A show whose refresh was attempted this recently is skipped.
    static let retryAfter: TimeInterval = 60 * 60
    /// A title the provider gave no genres is asked again after a week.
    static let genresRetryAfter: TimeInterval = 7 * 24 * 60 * 60
    /// Books per pass whose page count is filled; one Open Library read each.
    var pageCountLimit = 40

    let stores: Stores
    let catalog: CatalogService
    var now: @Sendable () -> Date = { Date() }

    /// Refreshes one batch and returns how many shows were attempted.
    func runOnce() async throws -> Int {
        let now = now()
        let due = try await stores.titles.staleTrackedShows(
            now: now, retryAfter: now.addingTimeInterval(-Self.retryAfter), limit: passLimit
        )
        for id in due {
            try Task.checkCancellation()
            // Stamped first: a show the provider no longer knows would otherwise come back every pass.
            try await stores.titles.markEpisodesAttempted(id, at: now)
            _ = try? await catalog.detail(id)
        }
        return due.count
    }

    /// CAT-018 backfill: one provider read per title missing genres; every attempt is stamped.
    /// Returns how many titles were attempted.
    func fillGenres() async throws -> Int {
        let now = now()
        let resolver = TitleResolver(stores: stores, catalogs: catalog.catalogs)
        let due = try await stores.titles.titlesMissingGenres(
            retryAfter: now.addingTimeInterval(-Self.genresRetryAfter), limit: genreLimit
        )
        for title in due {
            try Task.checkCancellation()
            let genres = (try? await resolver.genres(of: title)) ?? nil
            try await stores.titles.fillGenres(title.id, genres ?? [], attemptedAt: now)
        }
        return due.count
    }

    /// APP-017 backfill: a page count for shelved books stored before Open Library's was kept,
    /// in-progress books first. Every attempt is stamped; one without a count is asked again weekly.
    func fillPageCounts() async throws -> Int {
        let now = now()
        let due = try await stores.titles.booksMissingPageCount(
            retryAfter: now.addingTimeInterval(-Self.genresRetryAfter), limit: pageCountLimit
        )
        for book in due {
            try Task.checkCancellation()
            let found = try? await catalog.catalogs.openLibrary.hydrate(ids: book.ids, type: .book)
            try await stores.titles.fillPageCount(book.id, found?.hit.pageCount, attemptedAt: now)
        }
        return due.count
    }
}

/// Runs the catalog refresher every five minutes in the API process.
struct CatalogRefreshService: Service {
    let refresher: CatalogRefresher
    let logger: Logger
    var interval: Duration = .seconds(300)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let attempted = try await refresher.runOnce()
                    if attempted > 0 {
                        logger.info("Show episodes refreshed", metadata: ["count": "\(attempted)"])
                    }
                    let genres = try await refresher.fillGenres()
                    if genres > 0 {
                        logger.info("Title genres filled", metadata: ["count": "\(genres)"])
                    }
                    let pages = try await refresher.fillPageCounts()
                    if pages > 0 {
                        logger.info("Book page counts filled", metadata: ["count": "\(pages)"])
                    }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Show refresh pass failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
