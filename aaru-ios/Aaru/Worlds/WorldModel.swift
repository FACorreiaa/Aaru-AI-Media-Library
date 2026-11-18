import AaruAPI
import Foundation

typealias StoryWorld = Components.Schemas.World
typealias WorldLane = Components.Schemas.WorldLane
typealias WorldTitle = Components.Schemas.WorldTitle
typealias WorldLaneKind = Components.Schemas.WorldLaneKind
typealias WorldSummary = Components.Schemas.WorldSummary

/// A World opened from one of its titles.
struct WorldRoute: Hashable {
    let titleID: String
}

/// GRAPH-007: a title's World, as the server built and laid it out. The server chooses every
/// title, lane and place; this model only loads it. A World that is still being built is asked
/// for again a few times, then left: the surface that shows it is an extra, and its absence takes
/// nothing away.
@MainActor
@Observable
final class WorldModel {
    private(set) var world: StoryWorld?
    private(set) var loading = false
    /// The last read failed and there is nothing to show.
    private(set) var failed = false
    var problem: String?
    @ObservationIgnored let api: Client?
    @ObservationIgnored let titleID: String

    /// A World being built is asked for again after this long, this many times.
    static let buildingRetry: Duration = .seconds(4)
    static let buildingTries = 6

    init(api: Client?, titleID: String, world: StoryWorld? = nil) {
        self.api = api
        self.titleID = titleID
        self.world = world
    }

    /// True when there is a map to draw: a built World of two titles or more.
    var isReady: Bool {
        world.map { $0.state == .ready && $0.total >= 2 } ?? false
    }

    var isBuilding: Bool {
        world?.state == .building
    }

    /// Loads the World, asking again while the server is still building it.
    func load() async {
        guard let api else { return }
        loading = true
        defer { loading = false }
        for attempt in 0 ..< Self.buildingTries {
            do {
                guard case let .ok(response) = try await api.getTitleWorld(path: .init(id: titleID)) else {
                    failed = world == nil
                    return
                }
                world = try response.body.json
                failed = false
            } catch {
                if !Task.isCancelled, !(error is CancellationError) {
                    failed = world == nil
                }
                return
            }
            guard world?.state == .building, attempt < Self.buildingTries - 1 else { return }
            try? await Task.sleep(for: Self.buildingRetry)
            guard !Task.isCancelled else { return }
        }
    }

    /// "Add the rest": the titles the user does not have, as a capture to review. Its id, or nil
    /// after saying why not.
    func planRest() async -> String? {
        guard let api else { return nil }
        do {
            guard case let .accepted(response) = try await api.planWorldRest(path: .init(id: titleID)) else {
                problem = String(localized: "Aaru could not plan the rest of this world.")
                return nil
            }
            return try response.body.json.id
        } catch {
            problem = String(localized: "Aaru could not reach the server.")
            return nil
        }
    }
}

/// The user's Worlds, for the Worlds page.
@MainActor
@Observable
final class WorldsModel {
    private(set) var worlds: [WorldSummary]?
    private(set) var failed = false
    @ObservationIgnored let api: Client?

    init(api: Client?, worlds: [WorldSummary]? = nil) {
        self.api = api
        self.worlds = worlds
    }

    func load() async {
        guard let api else { return }
        do {
            guard case let .ok(response) = try await api.listMyWorlds() else {
                failed = worlds == nil
                return
            }
            worlds = try response.body.json.worlds
            failed = false
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                failed = worlds == nil
            }
        }
    }
}

// MARK: - Words

extension WorldLaneKind {
    var kind: MediaKind {
        switch self {
        case .book: .book
        case .manga: .manga
        case .film: .film
        case .show: .show
        case .anime: .anime
        case .album: .music
        }
    }
}

enum WorldWords {
    /// "5 of 11".
    static func count(finished: Int, total: Int) -> String {
        String(localized: "\(finished) of \(total)")
    }

    /// "Books, Films and Shows".
    static func kinds(_ kinds: [WorldLaneKind]) -> String {
        kinds.map(\.kind.label).formatted(.list(type: .and))
    }

    /// How far along, from 0 to 1; 0 for an empty World.
    static func share(finished: Int, total: Int) -> Double {
        total > 0 ? min(1, Double(finished) / Double(total)) : 0
    }
}

extension StoryWorld {
    /// How many titles the user does not have: what "Add the rest" would plan.
    var missing: Int {
        lanes.flatMap(\.titles).count(where: { $0.libraryItemId == nil })
    }

    /// One line per lane for the share card: "Books 3 of 6".
    var shareLines: [String] {
        lanes.map { lane in
            let done = lane.titles.count(where: { $0.status == .finished })
            return "\(lane.kind.kind.label) \(WorldWords.count(finished: done, total: lane.titles.count))"
        }
    }
}

extension WorldTitle {
    /// The year it came out, when the catalog knows.
    var year: String? {
        releaseDate.map { String($0.prefix(4)) } ?? ref.year.map(String.init)
    }

    /// What VoiceOver reads for one title on the map: its name, year, and where the user stands.
    func spoken(in lane: WorldLaneKind, startHere: Bool) -> String {
        var parts = [ref.title ?? String(localized: "Untitled")]
        if let year {
            parts.append(year)
        }
        if side {
            parts.append(String(localized: "side story"))
        }
        if let status {
            parts.append(status.label(for: lane.kind))
        } else {
            parts.append(String(localized: "not in your library"))
        }
        if startHere {
            parts.append(String(localized: "start here"))
        } else if next {
            parts.append(String(localized: "next in this lane"))
        }
        return parts.joined(separator: ", ")
    }

    /// The catalog page for a title that is not in the library.
    func hit(in lane: WorldLaneKind) -> CatalogHit {
        CatalogHit(
            _type: ref._type, title: ref.title ?? "", year: ref.year, posterUrl: posterUrl,
            isAnime: lane == .anime, ids: ref.ids ?? .init(), libraryItemId: libraryItemId,
            releaseDate: releaseDate
        )
    }
}

// MARK: - Layout

/// Where a World's tiles and lines go: a row per lane, a column per place in it. Lines run along
/// a lane through the middle of its posters; a link between lanes is a rung from the bottom of the
/// upper tile to the top of the lower. The same numbers as the web's `worldLayout`.
struct WorldLayout {
    static let tileWidth: CGFloat = 72
    static let posterHeight: CGFloat = 108
    static let column: CGFloat = 96
    /// A lane's label, above its tiles.
    static let labelHeight: CGFloat = 28
    /// A tile's name and year, under its poster.
    static let captionHeight: CGFloat = 56
    static let laneGap: CGFloat = 32
    static let pad: CGFloat = 16

    static var rowHeight: CGFloat {
        labelHeight + posterHeight + captionHeight + laneGap
    }

    let world: StoryWorld
    /// Each title's lane and place, by key.
    let place: [String: (lane: Int, column: Int)]

    init(_ world: StoryWorld) {
        self.world = world
        var place: [String: (lane: Int, column: Int)] = [:]
        for (laneIndex, lane) in world.lanes.enumerated() {
            for (column, title) in lane.titles.enumerated() where place[title.key] == nil {
                place[title.key] = (laneIndex, column)
            }
        }
        self.place = place
    }

    var size: CGSize {
        let longest = world.lanes.map(\.titles.count).max() ?? 0
        return CGSize(
            width: Self.pad * 2 + CGFloat(max(longest - 1, 0)) * Self.column + Self.tileWidth,
            height: Self.pad + CGFloat(world.lanes.count) * Self.rowHeight
        )
    }

    /// The top-left corner of a lane's label.
    func labelOrigin(lane: Int) -> CGPoint {
        CGPoint(x: Self.pad, y: Self.pad + CGFloat(lane) * Self.rowHeight)
    }

    /// The top-left corner of a tile's poster.
    func origin(lane: Int, column: Int) -> CGPoint {
        CGPoint(
            x: Self.pad + CGFloat(column) * Self.column,
            y: Self.pad + CGFloat(lane) * Self.rowHeight + Self.labelHeight
        )
    }

    /// The links between two lanes, as pairs of tile places: the rungs to draw. Links inside one
    /// lane are the lane's own rail and are not listed.
    var rungs: [(upper: (lane: Int, column: Int), lower: (lane: Int, column: Int))] {
        world.links.compactMap { link in
            guard let one = place[link.from], let other = place[link.to], one.lane != other.lane else { return nil }
            return one.lane < other.lane ? (one, other) : (other, one)
        }
    }
}
