import AaruCore
import Foundation

// MARK: Stremio history (IMP-016)

extension ImportService {
    /// A link code for the user to approve on stremio.com.
    struct StremioLinkStart: Equatable, Sendable {
        var code: String
        var link: URL
        var qrcode: URL
        var expiresAt: Date
    }

    enum StremioLinkPoll: Equatable, Sendable {
        /// Not approved yet: ask again in a few seconds.
        case pending
        /// Approved: the library was read and an import job queued with its rows.
        case imported(ImportJob)
    }

    func startStremioLink(userID: UserID) async throws -> StremioLinkStart {
        let stremio = try stremioAccount()
        let code = try await stremioCall { try await stremio.createLink() }
        let expiresAt = now().addingTimeInterval(StremioAccount.linkLifetime)
        try await stores.importJobs.createStremioLink(
            code: code.code, userID: userID, expiresAt: expiresAt, now: now()
        )
        return StremioLinkStart(code: code.code, link: code.link, qrcode: code.qrcode, expiresAt: expiresAt)
    }

    /// Once approved, reads the library in this request (one call), logs the session out and
    /// forgets its key. Matching is the worker's job, as for every import.
    func pollStremioLink(code: String, userID: UserID) async throws -> StremioLinkPoll {
        let stremio = try stremioAccount()
        guard let expiresAt = try await stores.importJobs.stremioLinkExpiry(code: code, userID: userID) else {
            throw AppError.notFound()
        }
        guard expiresAt > now() else {
            _ = try await stores.importJobs.consumeStremioLink(code: code, userID: userID)
            throw AppError(
                status: .gone, code: "stremio_link_expired",
                message: "That Stremio code expired. Start again to get a new one."
            )
        }
        guard let authKey = try await stremioCall({ try await stremio.readLink(code: code) }) else {
            return .pending
        }
        // Single use: a second poll racing this one finds nothing to import.
        guard try await stores.importJobs.consumeStremioLink(code: code, userID: userID) else {
            await stremio.logout(authKey: authKey)
            throw AppError.notFound()
        }
        let items: [StremioLibraryItem]
        do {
            items = try await stremioCall { try await stremio.library(authKey: authKey) }
        } catch {
            await stremio.logout(authKey: authKey)
            throw error
        }
        await stremio.logout(authKey: authKey)

        let rows = StremioLibraryMapper.rows(items)
        guard !rows.isEmpty else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Your Stremio library has no movies or shows to import.",
                details: ["library": "Empty."]
            )
        }
        let job = ImportJob(userID: userID, source: .stremio, createdAt: now(), updatedAt: now())
        try await stores.importJobs.insert(job, rows: rows)
        return .imported(job)
    }

    /// The worker's step before matching: lays each show's watched bitfield over its Cinemeta
    /// episode list. A show Cinemeta does not know keeps its status and gets no ticks.
    ///
    /// The show is found by Cinemeta's TVDB id first, as the addon's events are: TMDB answers
    /// some IMDb series with a near-empty entry of their own (Bleach: Thousand-Year Blood War,
    /// `tt14986406`), while TVDB's id is the show Aaru tracks. Ticks of another IMDb series are
    /// put on that show's episodes by release day; one that cannot be placed is left out.
    func expandStremioWatched(_ rows: [PlannedRow]) async throws -> [PlannedRow] {
        guard let stremio else { return rows }
        var expanded = rows
        for index in expanded.indices {
            guard let field = expanded[index].row.stremioWatched, let imdb = expanded[index].row.ids.imdb else {
                continue
            }
            let series = try await stremio.series(imdb: imdb)
            var ticks = StremioWatched.episodes(field, videos: series.videos)
            if let title = await show(tvdb: series.tvdb) {
                expanded[index].row.ids = title.ids
                if title.ids.imdb != imdb, !ticks.isEmpty {
                    let episodes = try await resolver.catalogs.tmdb.episodes(ids: title.ids)?.episodes ?? []
                    ticks = ticks.compactMap { key in
                        StremioEpisodeMap.place(
                            key, imdb: imdb, title: title, episodes: episodes, listed: series.videos
                        )
                    }
                }
            }
            expanded[index].row.watched = ticks.isEmpty ? nil : Array(Set(ticks)).sorted()
            expanded[index].row.stremioWatched = nil
        }
        return expanded
    }

    /// The show TVDB's id names, when there is one and the catalog knows it.
    private func show(tvdb: String?) async -> Title? {
        guard let tvdb else { return nil }
        return try? await resolver.resolve(MediaRef(type: .show, ids: ExternalIDs(tvdb: tvdb)))
    }

    private func stremioAccount() throws -> StremioAccount {
        guard let stremio else {
            throw AppError(
                status: .serviceUnavailable, code: "stremio_unavailable",
                message: "Stremio import is not available right now."
            )
        }
        return stremio
    }

    /// Stremio's own failures read as Stremio's, not as "the catalog".
    private func stremioCall<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch is ProviderError {
            throw Self.stremioDown
        } catch is StremioAPIError {
            throw Self.stremioDown
        }
    }

    private static let stremioDown = AppError(
        status: .badGateway, code: "provider_unavailable",
        message: "Stremio did not answer. Try again in a minute."
    )
}
