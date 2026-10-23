import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getStats(_ input: Operations.GetStats.Input) async throws -> Operations.GetStats.Output {
        let stats = try await services.stats.stats(
            userID: currentUser(), span: input.query.span.flatMap { StatsPeriod.Span(rawValue: $0.rawValue) },
            year: input.query.year, month: input.query.month, timeZone: input.query.tz
        )
        return .ok(.init(body: .json(.init(stats))))
    }
}

extension APIImplementation {
    func getProfileStats(_: Operations.GetProfileStats.Input) async throws -> Operations.GetProfileStats.Output {
        try await .ok(.init(body: .json(.init(services.stats.profile(userID: currentUser())))))
    }
}

extension Components.Schemas.ProfileStats {
    init(_ stats: ProfileStats) {
        self.init(
            memberSince: stats.memberSince,
            episodesWatched: stats.episodesWatched,
            minutesWatched: stats.minutesWatched,
            pagesRead: stats.pagesRead,
            shows: .init(stats.shows),
            anime: .init(stats.anime),
            movies: .init(stats.movies),
            books: .init(stats.books),
            byKind: stats.byKind.map {
                .init(
                    kind: .init(rawValue: $0.kind.rawValue) ?? .movie, episodes: $0.episodes, minutes: $0.minutes,
                    finished: $0.finished
                )
            },
            topGenres: stats.topGenres.map { .init(name: $0.name, minutes: $0.minutes, titles: $0.titles) },
            topNetworks: stats.topNetworks.map { .init(name: $0.name, minutes: $0.minutes, titles: $0.titles) },
            mostWatched: stats.mostWatched.map {
                .init(title: .init($0.title), episodes: $0.episodes, minutes: $0.minutes)
            },
            ratings: .init(
                count: stats.ratings.count, mean: stats.ratings.mean,
                highest: stats.ratings.highest.map(Components.Schemas.TitleSummary.init),
                highestRating: stats.ratings.highestRating, distribution: stats.ratings.distribution
            )
        )
    }
}

extension Components.Schemas.LibraryCounts {
    init(_ counts: ProfileStats.Counts) {
        self.init(
            wishlist: counts.wishlist, inProgress: counts.inProgress, finished: counts.finished,
            dropped: counts.dropped
        )
    }
}

extension Components.Schemas.Stats {
    init(_ stats: PeriodStats) {
        let totals = stats.totals
        self.init(
            span: .init(rawValue: stats.period.span.rawValue) ?? .year,
            year: stats.period.year,
            month: stats.period.month,
            from: stats.period.span.days == nil ? nil : stats.period.start.description,
            until: stats.period.span.days == nil ? nil : stats.period.lastDay.description,
            timeZone: stats.period.timeZone.identifier,
            isPartial: stats.isPartial,
            totals: .init(totals),
            prior: stats.prior.map(Components.Schemas.StatsTotals.init),
            byKind: stats.byKind.map {
                .init(
                    kind: .init(rawValue: $0.kind.rawValue) ?? .movie, episodes: $0.episodes, minutes: $0.minutes,
                    finished: $0.finished
                )
            },
            buckets: stats.buckets.map(Components.Schemas.StatsBucket.init),
            busiest: stats.busiest.map(Components.Schemas.StatsBucket.init),
            mostEpisodes: stats.mostEpisodes.map(Components.Schemas.StatsBucket.init),
            longestRun: stats.longestRun.map {
                .init(days: $0.days, start: $0.start.description, end: $0.end.description)
            },
            topTitles: stats.topTitles.map {
                .init(title: .init($0.title), episodes: $0.episodes, minutes: $0.minutes)
            },
            ratings: .init(
                count: stats.ratings.count, mean: stats.ratings.mean,
                highest: stats.ratings.highest.map(Components.Schemas.TitleSummary.init),
                highestRating: stats.ratings.highestRating, distribution: stats.ratings.distribution
            ),
            first: stats.first.map { .init(title: .init($0.title), at: $0.date) },
            last: stats.last.map { .init(title: .init($0.title), at: $0.date) },
            topGenres: stats.topGenres.map { .init(name: $0.name, minutes: $0.minutes, titles: $0.titles) },
            biggestDay: stats.biggestDay.map(Components.Schemas.StatsBucket.init),
            persona: stats.persona.flatMap { .init(rawValue: $0.rawValue) },
            music: stats.music.map(Components.Schemas.StatsMusic.init)
        )
    }
}

extension Components.Schemas.StatsMusic {
    init(_ music: ListenSummary) {
        self.init(
            listens: music.listens,
            minutes: Int(music.durationMs / 60000),
            priorListens: music.priorListens,
            priorMinutes: music.priorDurationMs.map { Int($0 / 60000) },
            topArtist: music.topArtist.map { top in
                .init(
                    artist: top.artist, count: top.count, minutes: Int(top.durationMs / 60000),
                    coverUrl: top.releaseGroupMBID.flatMap(MusicBrainzCatalog.coverURL(releaseGroup:))?.absoluteString
                )
            },
            topArtistTracks: music.topArtistTracks.map { .init(track: $0.track ?? "", count: $0.count) }
        )
    }
}

extension Components.Schemas.StatsTotals {
    init(_ totals: PeriodStats.Totals) {
        self.init(
            episodesWatched: totals.episodesWatched, minutesWatched: totals.minutesWatched,
            activeDays: totals.activeDays, moviesFinished: totals.moviesFinished,
            showsFinished: totals.showsFinished, animeFinished: totals.animeFinished,
            booksFinished: totals.booksFinished, albumsFinished: totals.albumsFinished,
            mangaFinished: totals.mangaFinished
        )
    }
}

extension Components.Schemas.StatsBucket {
    init(_ bucket: PeriodStats.Bucket) {
        self.init(
            start: bucket.start.description, episodes: bucket.episodes, minutes: bucket.minutes,
            finished: bucket.finished
        )
    }
}
