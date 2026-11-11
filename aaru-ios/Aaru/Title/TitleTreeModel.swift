import AaruAPI
import Foundation

typealias TitleTree = Components.Schemas.TitleTree
typealias TreeBranch = Components.Schemas.TreeBranch
typealias TreeNode = Components.Schemas.TreeNode
typealias TreeBranchKind = Components.Schemas.TreeBranchKind

/// GRAPH-005: a title tree ("From here") as the server picked it. The server chooses every title;
/// this model only loads it, and asks once more when the server cut a cold tree short. A failed
/// read leaves no tree: the section is a signpost, and its absence takes nothing away. It asks for
/// the cast (GRAPH-006): a film's or show's lead and second actor come as rows of their own.
@MainActor
@Observable
final class TitleTreeModel {
    private(set) var tree: TitleTree?
    @ObservationIgnored let api: Client?
    @ObservationIgnored let titleID: String

    /// A partial tree is read again after this long, once.
    static let partialRetry: Duration = .seconds(5)

    init(api: Client?, titleID: String, tree: TitleTree? = nil) {
        self.api = api
        self.titleID = titleID
        self.tree = tree
    }

    /// True when there is something to draw: a tree with no branch is not shown at all.
    var hasBranches: Bool {
        tree?.branches.contains { !$0.nodes.isEmpty } ?? false
    }

    /// Loads the tree; a partial one is asked for again once. A failure leaves the last tree.
    func load(retryPartial: Bool = true) async {
        guard let api else { return }
        do {
            guard case let .ok(response) = try await api.getTitleTree(
                path: .init(id: titleID), query: .init(cast: true)
            ) else { return }
            tree = try response.body.json
        } catch {
            return
        }
        if retryPartial, tree?.partial == true {
            try? await Task.sleep(for: Self.partialRetry)
            guard !Task.isCancelled else { return }
            await load(retryPartial: false)
        }
    }
}

// MARK: - Layout

/// Where a tree's tiles and lines go, the way a game's skill tree reads: the root on the left, a
/// trunk down from it, each branch a row to its right. Lines are straight or turn at right angles
/// and run through the middle of the tiles. The same numbers as the web's `treeLayout`.
struct TitleTreeLayout {
    static let tileWidth: CGFloat = 72
    static let tileHeight: CGFloat = 108
    /// Between tiles in a row.
    static let gap: CGFloat = 24
    /// Between the root and the first tile of each row: room for the trunk.
    static let trunkGap: CGFloat = 44
    /// A row's label, above its tiles.
    static let labelHeight: CGFloat = 24
    /// A tile's name and year, under it.
    static let captionHeight: CGFloat = 52
    static let rowGap: CGFloat = 12
    /// Room for a tile's ring.
    static let pad: CGFloat = 4

    struct Tile: Identifiable {
        let id: String
        let node: TreeNode
        let origin: CGPoint
        /// Its place in the order tiles arrive in.
        let index: Int
    }

    /// A row is known by its branch's kind, which a tree holds once: a row keeps its identity,
    /// and its tiles their posters, when a chip hides the rows above it (GRAPH-006).
    struct Row: Identifiable {
        let id: String
        let branch: TreeBranch
        let origin: CGPoint
        let tiles: [Tile]
    }

    struct Connector {
        let points: [CGPoint]
        /// True when the line leads into a title the person finished: drawn in the accent.
        let lit: Bool
    }

    let size: CGSize
    let root: Tile
    let rows: [Row]
    let connectors: [Connector]

    init(_ tree: TitleTree) {
        let rowHeight = Self.labelHeight + Self.tileHeight + Self.captionHeight + Self.rowGap
        let rootX = Self.pad
        let firstX = rootX + Self.tileWidth + Self.trunkGap
        let trunkX = rootX + Self.tileWidth + Self.trunkGap / 2
        func tileY(_ row: Int) -> CGFloat {
            Self.pad + CGFloat(row) * rowHeight + Self.labelHeight
        }
        func midY(_ row: Int) -> CGFloat {
            tileY(row) + Self.tileHeight / 2
        }

        var index = 0
        var rows: [Row] = []
        var connectors: [Connector] = []
        for branch in tree.branches where !branch.nodes.isEmpty {
            let row = rows.count
            let tiles = branch.nodes.enumerated().map { place, node in
                index += 1
                return Tile(
                    id: "\(branch.kind.rawValue):\(node.key)", node: node,
                    origin: CGPoint(x: firstX + CGFloat(place) * (Self.tileWidth + Self.gap), y: tileY(row)),
                    index: index
                )
            }
            let lineY = midY(row)
            // Root to the row's first tile: straight for the first row, down the trunk for the others.
            let start: [CGPoint] = row == 0
                ? [CGPoint(x: rootX + Self.tileWidth, y: lineY)]
                : [CGPoint(x: trunkX, y: midY(0)), CGPoint(x: trunkX, y: lineY)]
            connectors.append(Connector(points: start + [CGPoint(x: firstX, y: lineY)], lit: tiles[0].node.isLit))
            for (before, after) in zip(tiles, tiles.dropFirst()) {
                connectors.append(Connector(
                    points: [
                        CGPoint(x: before.origin.x + Self.tileWidth, y: lineY),
                        CGPoint(x: after.origin.x, y: lineY),
                    ],
                    lit: after.node.isLit
                ))
            }
            rows.append(Row(
                id: branch.kind.rawValue, branch: branch,
                origin: CGPoint(x: firstX, y: Self.pad + CGFloat(row) * rowHeight), tiles: tiles
            ))
        }
        let longest = CGFloat(rows.map(\.tiles.count).max() ?? 0)
        size = CGSize(
            width: firstX + max(0, longest * Self.tileWidth + (longest - 1) * Self.gap) + Self.pad,
            height: Self.pad + CGFloat(max(1, rows.count)) * rowHeight - Self.rowGap + Self.pad
        )
        root = Tile(id: "root", node: tree.root, origin: CGPoint(x: rootX, y: tileY(0)), index: 0)
        self.rows = rows
        self.connectors = connectors
    }
}

// MARK: - One person at a time (GRAPH-006)

/// A chip over the tree: every person's row, or one person's by its branch kind.
enum TitleTreeFilter: Hashable {
    case all
    case person(TreeBranchKind)
}

extension TreeBranch {
    /// A person's row, as against the series and the adaptations, which no chip hides.
    var isPerson: Bool {
        kind != .series && kind != .adaptation
    }

    /// The chip for this person's row. It names the part, not the person: the row's own label
    /// carries the name, so three chips always fit one line.
    var chip: String {
        switch kind {
        case .director: "Director"
        case .creator: "Creator"
        case .studio: "Studio"
        case .author: "Author"
        case .artist: "Artist"
        case .leadActor: "Lead"
        case .secondActor: "2nd"
        case .series, .adaptation: ""
        }
    }
}

extension TitleTree {
    /// The people whose rows have titles, in the order the server sent them.
    private var people: [TreeBranch] {
        branches.filter { $0.isPerson && !$0.nodes.isEmpty }
    }

    /// The chips for this tree: none unless it has two people or more. At compact width (iPhone)
    /// there is no "All", so one person's row shows at a time and the section stays as short as
    /// it was before the cast.
    func filters(compact: Bool) -> [TitleTreeFilter] {
        let people = people
        guard people.count > 1 else { return [] }
        let chips = people.map { TitleTreeFilter.person($0.kind) }
        return compact ? chips : [.all] + chips
    }

    /// The chip in force: the one chosen while it is still offered, else the first.
    func filter(chosen: TitleTreeFilter?, compact: Bool) -> TitleTreeFilter {
        let offered = filters(compact: compact)
        if let chosen, offered.contains(chosen) {
            return chosen
        }
        return offered.first ?? .all
    }

    /// The tree with only the chosen person's row; the series and the adaptations always stay.
    /// The server sent every row: this only chooses which are drawn, and reads nothing.
    func showing(_ filter: TitleTreeFilter) -> TitleTree {
        guard case let .person(kind) = filter else { return self }
        var tree = self
        tree.branches = branches.filter { !$0.isPerson || $0.kind == kind }
        return tree
    }

    /// A chip's label.
    func label(of filter: TitleTreeFilter) -> String {
        switch filter {
        case .all: "All"
        case let .person(kind): branches.first { $0.kind == kind }?.chip ?? ""
        }
    }
}

// MARK: - What the server sent, named

extension TreeBranch {
    /// "Director · Denis Villeneuve", "Series", "Adaptations".
    var title: String {
        let role: String
        switch kind {
        case .series: return "Series"
        case .adaptation: return "Adaptations"
        case .director: role = "Director"
        case .creator: role = "Creator"
        case .studio: role = "Studio"
        case .author: role = "Author"
        case .artist: role = "Artist"
        case .leadActor: role = "Lead"
        case .secondActor: role = "Also starring"
        }
        return label.map { "\(role) · \($0)" } ?? role
    }
}

extension TreeNode {
    var kind: MediaKind {
        MediaKind(type: ref._type, isAnime: isAnime ?? false)
    }

    var isRoot: Bool {
        pick == .root
    }

    /// A title the person finished: lit.
    var isLit: Bool {
        status == .finished
    }

    var year: String? {
        releaseDate.map { String($0.prefix(4)) } ?? ref.year.map(String.init)
    }

    /// What VoiceOver reads for a tile: "Dune, 2021, best known, Plan to watch".
    var spoken: String {
        [
            ref.title ?? "Untitled",
            year,
            pick == .bestKnown ? "best known" : nil,
            status.map { $0.label(for: kind) } ?? "not in your library",
            isRoot ? "this title" : nil,
        ].compactMap(\.self).joined(separator: ", ")
    }

    /// The catalog page for a title that is not in the library.
    var hit: CatalogHit {
        CatalogHit(
            _type: ref._type, title: ref.title ?? "", year: ref.year, posterUrl: posterUrl,
            isAnime: isAnime ?? false, ids: ref.ids ?? .init(), libraryItemId: libraryItemId,
            releaseDate: releaseDate
        )
    }
}
