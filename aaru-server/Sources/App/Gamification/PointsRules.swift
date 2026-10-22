import AaruCore
import Foundation

/// What earns points, how many, and the most one kind can earn in a local day (GAM-001). Values
/// live here, not in the database, so tuning them is a code change with a test.
enum PointsKind: String, Sendable, CaseIterable, Codable {
    case episode
    case movieFinished = "movie_finished"
    case bookFinished = "book_finished"
    case albumFinished = "album_finished"
    case seasonBonus = "season_bonus"
    case scrobbleBonus = "scrobble_bonus"
    case bookProgress = "book_progress"
    case listen
    case roomAttended = "room_attended"
    case friendAdded = "friend_added"
    case importFirst = "import_first"
    case streakMilestone = "streak_milestone"

    var points: Int {
        switch self {
        case .episode: 10
        case .movieFinished: 25
        case .bookFinished: 50
        case .albumFinished: 10
        case .seasonBonus: 30
        case .scrobbleBonus: 5
        case .bookProgress: 5
        case .listen: 1
        case .roomAttended: 15
        case .friendAdded: 20
        case .importFirst: 50
        case .streakMilestone: 0
        }
    }

    /// Nil: no daily cap (one-off kinds and streak milestones).
    var dailyCap: Int? {
        switch self {
        case .episode: 300
        case .movieFinished: 100
        case .bookFinished: 150
        case .albumFinished: 50
        case .seasonBonus: 90
        case .scrobbleBonus: 50
        case .bookProgress: 15
        case .listen: 25
        case .roomAttended: 45
        case .friendAdded: 60
        case .importFirst, .streakMilestone: nil
        }
    }

    /// Whether the kind counts on the weekly friends board. Making friends and moving in are not
    /// a week's watching (owner decision 2026-10-22).
    var onBoard: Bool {
        self != .friendAdded && self != .importFirst
    }

    /// Kinds whose root is spent by its first award, even once revoked: re-friending, a second
    /// first import, rejoining a party or a rebuilt streak earn nothing again.
    var oncePerRoot: Bool {
        switch self {
        case .friendAdded, .importFirst, .roomAttended, .streakMilestone: true
        default: false
        }
    }

    /// Kinds that make a day a streak day.
    var marksStreakDay: Bool {
        switch self {
        case .episode, .movieFinished, .bookFinished, .albumFinished, .bookProgress: true
        default: false
        }
    }

    static func streakBonus(days: Int) -> Int {
        switch days {
        case 7: 50
        case 30: 200
        case 100: 500
        case 365: 1000
        default: 0
        }
    }
}

/// One award to make: the root ties it to its later revocation.
struct PointsAward: Sendable, Equatable {
    var kind: PointsKind
    var root: String
    var points: Int
    var titleID: TitleID?
    var actionID: UUID?

    init(_ kind: PointsKind, root: String, points: Int? = nil, titleID: TitleID? = nil, actionID: UUID? = nil) {
        self.kind = kind
        self.root = root
        self.points = points ?? kind.points
        self.titleID = titleID
        self.actionID = actionID
    }
}

/// Dedupe roots. Keyed by title, not library item, so removing a title and adding it back earns
/// nothing twice.
enum PointsRoot {
    static func episode(_ title: TitleID, _ key: EpisodeKey) -> String {
        "ep:\(title.rawValue.uuidString):\(key.season):\(key.episode)"
    }

    static func scrobble(_ title: TitleID, _ key: EpisodeKey) -> String {
        "scrobble:\(title.rawValue.uuidString):\(key.season):\(key.episode)"
    }

    static func scrobbleFinish(_ title: TitleID) -> String {
        "scrobble:\(title.rawValue.uuidString)"
    }

    static func season(_ title: TitleID, _ season: Int) -> String {
        "season:\(title.rawValue.uuidString):\(season)"
    }

    static func finish(_ title: TitleID) -> String {
        "finish:\(title.rawValue.uuidString)"
    }

    static func bookDay(_ title: TitleID, _ date: String) -> String {
        "book:\(title.rawValue.uuidString):\(date)"
    }

    static func friend(_ first: UserID, _ second: UserID) -> String {
        let pair = [first.rawValue.uuidString, second.rawValue.uuidString].sorted()
        return "friend:\(pair[0]):\(pair[1])"
    }

    static func room(_ session: UUID) -> String {
        "room:\(session.uuidString)"
    }

    /// A listen is one play of one track at one moment, as the listens table keys it.
    static func listen(_ listen: NewListen) -> String {
        let seconds = Int(listen.listenedAt.timeIntervalSince1970)
        return "listen:\(seconds):\(listen.artist.lowercased()):\(listen.track.lowercased())"
    }

    static let importFirst = "import:first"

    static func streak(runStart: String, days: Int) -> String {
        "streak:\(runStart):\(days)"
    }
}

/// What one library write changed that points care about, read from the op and the inverse the
/// store computed for it. The inverse holds exactly what changed (the ticks added and removed,
/// the previous fields), so the journal needs no finer kinds.
struct LibraryWriteFacts: Equatable, Sendable {
    var ticked: [LibraryItemID: [EpisodeKey]] = [:]
    var unticked: [LibraryItemID: [EpisodeKey]] = [:]
    var finished: Set<LibraryItemID> = []
    var unfinished: Set<LibraryItemID> = []
    var bookForward: Set<LibraryItemID> = []

    var isEmpty: Bool {
        ticked.isEmpty && unticked.isEmpty && finished.isEmpty && unfinished.isEmpty && bookForward.isEmpty
    }

    var itemIDs: Set<LibraryItemID> {
        Set(ticked.keys).union(unticked.keys).union(finished).union(unfinished).union(bookForward)
    }

    /// Journal kinds that are live writes. Imports, approved plans and list edits earn nothing
    /// per item.
    static let liveKinds: Set<String> = ["add", "update", "remove", "episode", "season", "undo"]

    static func derive(op: LibraryOp, inverse: LibraryOp, kind: String) -> LibraryWriteFacts {
        var facts = LibraryWriteFacts()
        guard liveKinds.contains(kind) else { return facts }
        facts.collect(op: op, inverse: inverse, kind: kind)
        return facts
    }

    private mutating func collect(op: LibraryOp, inverse: LibraryOp, kind: String) {
        switch (op, inverse) {
        case let (.batch(ops), .batch(inverses)):
            // The store returns a batch's inverses reversed.
            for (child, childInverse) in zip(ops, inverses.reversed()) {
                collect(op: child, inverse: childInverse, kind: kind)
            }
        case let (.setEpisodes(id, _, _), .setEpisodes(_, removed, added)):
            if !added.isEmpty {
                ticked[id, default: []] += added
            }
            if !removed.isEmpty {
                unticked[id, default: []] += removed
            }
        case let (.setFields(id, new), .setFields(_, previous)):
            collect(id, new: new, previous: previous)
        case let (.insertItem(snapshot), _):
            // A new item added as finished counts; an undo restoring a removed item does not
            // (its finish was never revoked). Restored ticks are not activity either.
            if kind == "add", snapshot.fields.status == .finished {
                finished.insert(snapshot.id)
            }
        default:
            break
        }
    }

    private mutating func collect(_ id: LibraryItemID, new: ItemFields, previous: ItemFields) {
        if new.status == .finished, previous.status != .finished {
            finished.insert(id)
        } else if previous.status == .finished, new.status != .finished {
            unfinished.insert(id)
        }
        if (new.bookPage ?? 0) > (previous.bookPage ?? 0) || (new.bookPercent ?? 0) > (previous.bookPercent ?? 0) {
            bookForward.insert(id)
        }
    }
}

/// GAM-002: `50·L·(L−1)` points to reach level L. Level 1 at 0 points.
enum Levels {
    static func threshold(_ level: Int) -> Int {
        50 * level * (level - 1)
    }

    static func level(for total: Int) -> Int {
        guard total > 0 else { return 1 }
        var level = Int(((1 + (1 + 4 * Double(total) / 50).squareRoot()) / 2).rounded(.down))
        // Guard against floating point at exact boundaries.
        while threshold(level + 1) <= total {
            level += 1
        }
        while level > 1, threshold(level) > total {
            level -= 1
        }
        return max(1, level)
    }
}
