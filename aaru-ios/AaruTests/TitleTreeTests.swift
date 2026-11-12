import CoreGraphics
import Foundation
import Testing
@testable import Aaru

/// The title tree's client side (GRAPH-005, GRAPH-006): which chips a tree offers, what a chip
/// leaves, and where the tiles go. The Swift twins of `aaru-client/src/lib/title/tree.test.ts`.
struct TitleTreeTests {
    // MARK: Chips

    @Test func oneFilmWithCastOffersAChipPerPerson() throws {
        let tree = try Self.tree([.director: 3, .leadActor: 2, .secondActor: 1, .series: 2])

        #expect(tree.filters(compact: false) == [.all, .person(.director), .person(.leadActor), .person(.secondActor)])
        // An iPhone shows one person's row at a time, so it has no "All".
        #expect(tree.filters(compact: true) == [.person(.director), .person(.leadActor), .person(.secondActor)])
    }

    @Test func oneOrNoPersonOffersNoChips() throws {
        #expect(try Self.tree([.director: 3, .series: 2]).filters(compact: false).isEmpty)
        #expect(try Self.tree([.series: 2, .adaptation: 1]).filters(compact: true).isEmpty)
    }

    @Test func aPersonWithNoTitlesGetsNoChip() throws {
        let tree = try Self.tree([.director: 3, .leadActor: 0, .secondActor: 1])

        #expect(tree.filters(compact: true) == [.person(.director), .person(.secondActor)])
    }

    @Test func theChosenChipHoldsWhileItIsOffered() throws {
        let tree = try Self.tree([.director: 3, .leadActor: 2])

        #expect(tree.filter(chosen: .person(.leadActor), compact: true) == .person(.leadActor))
        #expect(tree.filter(chosen: nil, compact: true) == .person(.director))
        #expect(tree.filter(chosen: nil, compact: false) == .all)
        // "All" was chosen on a wide window, which then narrowed: the first person takes over.
        #expect(tree.filter(chosen: .all, compact: true) == .person(.director))
        // A chip from another title's tree is not offered here.
        #expect(tree.filter(chosen: .person(.studio), compact: false) == .all)
    }

    @Test func aTreeWithoutChipsShowsEverything() throws {
        let tree = try Self.tree([.director: 3, .series: 2])

        #expect(tree.filter(chosen: .person(.director), compact: true) == .all)
        #expect(tree.showing(.all) == tree)
    }

    @Test func aChipKeepsItsPersonTheSeriesAndTheAdaptations() throws {
        let tree = try Self.tree([.director: 3, .leadActor: 2, .secondActor: 1, .series: 2, .adaptation: 1])

        let shown = tree.showing(.person(.leadActor))

        #expect(shown.branches.map(\.kind) == [.leadActor, .series, .adaptation])
        #expect(shown.root == tree.root)
    }

    // MARK: Layout

    @Test func rowsAreKnownByTheirBranchKind() throws {
        let tree = try Self.tree([.director: 3, .leadActor: 2, .series: 2])

        let all = TitleTreeLayout(tree)
        let one = TitleTreeLayout(tree.showing(.person(.leadActor)))

        #expect(all.rows.map(\.id) == ["director", "lead_actor", "series"])
        // Hiding the row above must not rename this one, or its posters would load again.
        #expect(one.rows.map(\.id) == ["lead_actor", "series"])
        #expect(one.rows[0].tiles.map(\.id) == all.rows[1].tiles.map(\.id))
    }

    @Test func anEmptyBranchTakesNoRow() throws {
        let layout = try TitleTreeLayout(Self.tree([.director: 0, .series: 2]))

        #expect(layout.rows.map(\.id) == ["series"])
    }

    @Test func everyTileIsJoinedToTheOneBeforeIt() throws {
        let layout = try TitleTreeLayout(Self.tree([.director: 3, .series: 2]))

        // One line into each tile: from the root for a row's first, from its neighbour for the rest.
        #expect(layout.connectors.count == 5)
        // The first row leaves the root straight; a later row goes down the trunk first.
        #expect(layout.connectors[0].points.count == 2)
        #expect(layout.connectors[3].points.count == 3)
    }

    @Test func aLineIntoAFinishedTitleIsLit() throws {
        let tree = try Self.tree([.director: 2], finished: ["director-1"])

        let layout = TitleTreeLayout(tree)

        #expect(layout.connectors.map(\.lit) == [false, true])
    }

    @Test func theCanvasFitsItsLongestRow() throws {
        let layout = try TitleTreeLayout(Self.tree([.director: 5, .series: 2]))

        let last = try #require(layout.rows[0].tiles.last)
        #expect(last.origin.x + TitleTreeLayout.tileWidth + TitleTreeLayout.pad == layout.size.width)
        #expect(layout.rows[1].origin.y > layout.rows[0].origin.y)
        #expect(layout.root.origin.y == layout.rows[0].tiles[0].origin.y)
    }

    @Test func aTreeWithNoRowsStillHasRoomForItsRoot() throws {
        let layout = try TitleTreeLayout(Self.tree([:]))

        #expect(layout.rows.isEmpty)
        #expect(layout.connectors.isEmpty)
        #expect(layout.size.height >= TitleTreeLayout.tileHeight)
    }

    // MARK: Fixture

    /// A tree with the given number of titles in each branch, in the server's order: people,
    /// then the series, then the adaptations. Decoded from JSON, as the app receives it.
    private static func tree(_ sizes: [TreeBranchKind: Int], finished: Set<String> = []) throws -> TitleTree {
        let order: [TreeBranchKind] = [
            .director, .creator, .studio, .author, .artist, .leadActor, .secondActor, .series, .adaptation,
        ]
        let branches = order.compactMap { kind -> [String: Any]? in
            guard let count = sizes[kind] else { return nil }
            let nodes = (0 ..< count).map { place -> [String: Any] in
                let key = "\(kind.rawValue.replacingOccurrences(of: "_", with: "-"))-\(place)"
                var node: [String: Any] = ["key": key, "ref": ["type": "movie"], "pick": "next"]
                if finished.contains(key) {
                    node["status"] = "finished"
                }
                return node
            }
            return ["kind": kind.rawValue, "label": "Someone", "nodes": nodes]
        }
        let json: [String: Any] = [
            "root": ["key": "root", "ref": ["type": "movie"], "pick": "root"],
            "branches": branches,
            "partial": false,
        ]
        return try JSONDecoder().decode(TitleTree.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
