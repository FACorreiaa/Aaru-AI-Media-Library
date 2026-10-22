import Foundation

/// One import source's stamp badge. CAT's list and ICS share one stamp.
struct ImportStamp: Sendable {
    let id: String
    let label: String
    let sources: Set<String>
}

/// The catalog, continued: imports, discovery, streaks and social.
extension BadgeCatalog {
    /// Import sources by stamp, in CLAUDE.md's import order. CAT's list and ICS share one stamp.
    static let stamps: [ImportStamp] = [
        .init(id: "trakt", label: "Trakt", sources: ["trakt"]),
        .init(id: "stremio", label: "Stremio", sources: ["stremio"]),
        .init(id: "imdb", label: "IMDb", sources: ["imdb_csv"]),
        .init(id: "letterboxd", label: "Letterboxd", sources: ["letterboxd_csv"]),
        .init(id: "goodreads", label: "Goodreads", sources: ["goodreads_csv"]),
        .init(id: "cat", label: "Pogdesign CAT", sources: ["cat_list", "cat_ics"]),
        .init(id: "netflix", label: "Netflix", sources: ["netflix_csv"]),
        .init(id: "tvtime", label: "TV Time", sources: ["tvtime_csv"]),
        .init(id: "mal", label: "MyAnimeList", sources: ["mal_xml"]),
        .init(id: "anilist", label: "AniList", sources: ["anilist"]),
        .init(id: "csv", label: "Any CSV", sources: ["csv"]),
    ]

    static let imports: [BadgeDefinition] = [
        .init(
            "first_import", .imports, "Moving In", describe: { _ in "Bring your history in" }, value: \.importsApplied
        ),
        .init(
            "sources",
            .imports,
            "Well Travelled",
            tiers: [2, 4, 6],
            describe: { "Import from \(plural($0, "source", "sources"))" },
            value: { facts in stamps.filter { !$0.sources.isDisjoint(with: facts.importSources) }.count }
        ),
    ] + stamps.map { stamp in
        BadgeDefinition(
            "stamp_\(stamp.id)", .imports, "\(stamp.label) stamp",
            describe: { _ in "Import from \(stamp.label)" },
            value: { $0.importSources.isDisjoint(with: stamp.sources) ? 0 : 1 }
        )
    }

    static let discovery: [BadgeDefinition] = [
        .init(
            "genres",
            .discovery,
            "Genre Hopper",
            tiers: [5, 10, 15],
            describe: { "Finish titles in \(plural($0, "genre", "genres"))" },
            value: \.genres
        ),
        .init(
            "decades",
            .discovery,
            "Time Traveller",
            tiers: [4, 6, 8],
            describe: { "Finish titles from \(plural($0, "decade", "decades"))" },
            value: \.decades
        ),
        .init(
            "networks",
            .discovery,
            "Channel Surfer",
            tiers: [5, 15, 30],
            describe: { "Watch shows from \(plural($0, "network", "networks"))" },
            value: \.networks
        ),
        .init(
            "all_rounder",
            .discovery,
            "All-Rounder",
            describe: { _ in "Finish a film, a show, an anime, a book and an album" },
            value: { $0.kindsFinished == 5 ? 1 : 0 }
        ),
    ]

    static let streaks: [BadgeDefinition] = [
        .init(
            "streak",
            .streaks,
            "Unbroken",
            tiers: [7, 30, 100, 365],
            describe: { "Keep a \(plural($0, "day", "day")) streak" },
            value: \.longestStreak
        ),
        .init(
            "comeback",
            .streaks,
            "Comeback",
            hidden: true,
            describe: { _ in "Lose a week-long streak, then build another" },
            value: { $0.comeback ? 1 : 0 }
        ),
        .init(
            "night_owl",
            .streaks,
            "Night Owl",
            tiers: [10, 50, 200],
            describe: { "Log progress after midnight \(plural($0, "time", "times"))" },
            value: \.nightOwlWrites
        ),
    ]

    static let social: [BadgeDefinition] = [
        .init("first_friend", .social, "Plus One", describe: { _ in "Make a friend" }, value: \.friends),
        .init(
            "friends",
            .social,
            "Inner Circle",
            tiers: [5, 10, 25],
            describe: { "Have \(plural($0, "friend", "friends"))" },
            value: \.friends
        ),
        .init(
            "ambassador",
            .social,
            "Ambassador",
            tiers: [1, 5, 10],
            describe: { "Bring \(plural($0, "friend", "friends")) in with an invite" },
            value: \.invitesRedeemed
        ),
        .init(
            "tastemaker",
            .social,
            "Tastemaker",
            tiers: [1, 10, 50],
            describe: { "Recommend \(plural($0, "title", "titles")) to friends" },
            value: \.recommendationsSent
        ),
        .init(
            "good_call",
            .social,
            "Good Call",
            tiers: [5],
            hidden: true,
            describe: { _ in "Have five recommendations added by friends" },
            value: \.recommendationsAdded
        ),
        .init(
            "applause",
            .social,
            "Applause",
            tiers: [10, 100],
            describe: { "React to friends \(plural($0, "time", "times"))" },
            value: \.reactions
        ),
        .init(
            "watch_party",
            .social,
            "Watch Party",
            tiers: [1, 5, 25],
            describe: { "Join \(plural($0, "watch party", "watch parties"))" },
            value: \.watchParties
        ),
    ]
}
