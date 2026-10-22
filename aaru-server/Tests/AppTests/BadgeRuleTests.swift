import AaruCore
import Foundation
import Testing
@testable import aaru

/// GAM-004: one row per badge; each tier boundary is checked from one below to exactly on it.
@Suite("Badge rules (GAM-004)")
struct BadgeRuleTests {
    /// Sets the fact a badge reads to `value`.
    static let setters: [String: @Sendable (inout AchievementFacts, Int) -> Void] = {
        func int(_ path: WritableKeyPath<AchievementFacts, Int>) -> @Sendable (inout AchievementFacts, Int) -> Void {
            { $0[keyPath: path] = $1 }
        }
        var setters: [String: @Sendable (inout AchievementFacts, Int) -> Void] = [
            "first_film": int(\.filmsFinished), "films": int(\.filmsFinished),
            "silver_screen": int(\.filmsBefore1960), "double_feature": int(\.doubleFeatureDays),
            "first_episode": int(\.episodesTicked), "episodes": int(\.episodesTicked),
            "shows": int(\.showsFinished), "seasons": int(\.seasonsComplete),
            "completionist": int(\.endedShowsComplete), "long_haul": int(\.longShowsComplete),
            "binge": int(\.bingedSeasons), "marathon": int(\.marathonDays), "day_one": int(\.dayOneEpisodes),
            "finale_night": int(\.finaleNights),
            "first_anime": int(\.animeFinished), "anime": int(\.animeFinished),
            "anime_episodes": int(\.animeEpisodes),
            "first_book": int(\.booksFinished), "books": int(\.booksFinished), "pages": int(\.pagesRead),
            "doorstopper": int(\.longBooksFinished), "chapter_a_day": int(\.longestBookRun),
            "first_listen": int(\.listens), "listens": int(\.listens), "artists": int(\.artists),
            "albums": int(\.albumsFinished),
            "first_rating": int(\.ratings), "ratings": int(\.ratings), "perfect_ten": int(\.perfectTens),
            "notes": int(\.notes),
            "first_list": int(\.lists), "lists": int(\.lists), "first_shelf": int(\.shelves), "collector": int(\.owned),
            "first_import": int(\.importsApplied),
            "genres": int(\.genres), "decades": int(\.decades), "networks": int(\.networks),
            "streak": int(\.longestStreak), "night_owl": int(\.nightOwlWrites),
            "first_friend": int(\.friends), "friends": int(\.friends), "ambassador": int(\.invitesRedeemed),
            "tastemaker": int(\.recommendationsSent), "good_call": int(\.recommendationsAdded),
            "applause": int(\.reactions), "watch_party": int(\.watchParties),
        ]
        setters["tough_crowd"] = { facts, value in
            facts.ratings = value >= 1 ? 25 : 24
            facts.ratingMean = 4.5
        }
        setters["all_rounder"] = { facts, value in
            facts.filmsFinished = 1
            facts.showsFinished = 1
            facts.animeFinished = 1
            facts.booksFinished = 1
            facts.albumsFinished = value >= 1 ? 1 : 0
        }
        setters["comeback"] = { facts, value in facts.comeback = value >= 1 }
        setters["sources"] = { facts, value in
            facts.importSources = Set(BadgeCatalog.stamps.prefix(value).compactMap(\.sources.first))
        }
        for stamp in BadgeCatalog.stamps {
            setters["stamp_\(stamp.id)"] = { facts, value in
                facts.importSources = value >= 1 ? stamp.sources : []
            }
        }
        return setters
    }()

    @Test("Every badge in the catalog has a rule test")
    func everyBadgeCovered() {
        let missing = BadgeCatalog.all.map(\.id).filter { Self.setters[$0] == nil }
        #expect(missing.isEmpty, "\(missing)")
        #expect(Set(BadgeCatalog.all.map(\.id)).count == BadgeCatalog.all.count, "ids are unique")
        let hidden = BadgeCatalog.all.filter(\.hidden).count
        #expect(Double(hidden) / Double(BadgeCatalog.all.count) < 0.2, "about 15% hidden")
    }

    @Test("Each tier starts exactly at its threshold", arguments: BadgeCatalog.all.map(\.id))
    func tierBoundaries(_ id: String) throws {
        let definition = try #require(BadgeCatalog.byID[id])
        let set = try #require(Self.setters[id])
        for (index, threshold) in definition.thresholds.enumerated() {
            var below = AchievementFacts()
            set(&below, threshold - 1)
            #expect(definition.tier(for: below) == index, "\(id) at \(threshold - 1)")
            var reached = AchievementFacts()
            set(&reached, threshold)
            #expect(definition.tier(for: reached) == index + 1, "\(id) at \(threshold)")
        }
        #expect(definition.tier(for: AchievementFacts()) == 0, "\(id) with nothing")
    }

    @Test("Only notes and owned badges are private")
    func privateBadges() {
        #expect(Set(BadgeCatalog.all.filter(\.isPrivate).map(\.id)) == ["notes", "collector"])
    }
}

@Suite("Library write facts (GAM-001)")
struct LibraryWriteFactsTests {
    let item = LibraryItemID()

    @Test("Ticks and unticks come from the inverse, not the request")
    func ticks() throws {
        let one = try EpisodeKey(season: 1, episode: 1)
        let two = try EpisodeKey(season: 1, episode: 2)
        // Asked to watch 1 and 2; 1 was already watched, so the inverse unwatches only 2.
        let facts = LibraryWriteFacts.derive(
            op: .setEpisodes(item, watch: [one, two], unwatch: []),
            inverse: .setEpisodes(item, watch: [], unwatch: [two]), kind: "episode"
        )
        #expect(facts.ticked == [item: [two]])
        #expect(facts.unticked.isEmpty)
    }

    @Test("Finishing, unfinishing and book pages; imports and plans derive nothing")
    func fields() {
        let before = ItemFields(status: .inProgress, isOwned: false, bookPage: 10)
        var after = before
        after.status = .finished
        after.bookPage = 20
        let finished = LibraryWriteFacts.derive(
            op: .setFields(item, after), inverse: .setFields(item, before), kind: "update"
        )
        #expect(finished.finished == [item])
        #expect(finished.bookForward == [item])
        let undone = LibraryWriteFacts.derive(
            op: .setFields(item, before), inverse: .setFields(item, after), kind: "undo"
        )
        #expect(undone.unfinished == [item])
        #expect(LibraryWriteFacts.derive(
            op: .setFields(item, after), inverse: .setFields(item, before), kind: "import"
        ).isEmpty)
    }
}
