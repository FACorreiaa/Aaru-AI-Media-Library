import AaruAPI
import CoreGraphics
import Testing
@testable import Aaru

/// Worlds (GRAPH-007): the words a World is read in, what its share card says, and where its
/// tiles and rungs go.
@MainActor
struct WorldMapTests {
    private func title(
        _ key: String, _ name: String, year: Int? = nil, status: Components.Schemas.LibraryStatus? = nil,
        side: Bool = false, next: Bool = false
    ) -> WorldTitle {
        WorldTitle(
            key: key, ref: .init(_type: .movie, title: name, year: year), side: side, next: next,
            libraryItemId: status == nil ? nil : "item-\(key)", status: status
        )
    }

    private var dune: StoryWorld {
        StoryWorld(
            state: .ready, id: "w", name: "Dune", total: 5, finished: 2, kinds: [.book, .film, .show],
            lanes: [
                .init(kind: .book, titles: [
                    title("b1", "Dune", year: 1965, status: .finished),
                    title("b2", "Dune Messiah", year: 1969, next: true),
                ]),
                .init(kind: .film, titles: [
                    title("f1", "Dune: Part One", year: 2021, status: .finished),
                    title("f2", "Dune: Part Two", year: 2024, status: .inProgress),
                ]),
                .init(kind: .show, titles: [title("s1", "Dune: Prophecy", year: 2024, side: true)]),
            ],
            links: [
                .init(from: "b1", to: "b2", relation: .sequel),
                .init(from: "b1", to: "f1", relation: .adaptation),
                .init(from: "f1", to: "f2", relation: .sequel),
                .init(from: "s1", to: "f1", relation: .spinOff),
            ],
            startHere: "f2", anchor: "f1", truncated: false, partial: false
        )
    }

    @Test func theCountAndKindsReadAsWords() {
        #expect(WorldWords.count(finished: 5, total: 11) == "5 of 11")
        #expect(WorldWords.kinds([.book, .film, .show]) == "Books, Films, and Shows")
        #expect(WorldWords.share(finished: 1, total: 4) == 0.25)
        #expect(WorldWords.share(finished: 0, total: 0) == 0)
        #expect(WorldWords.share(finished: 9, total: 4) == 1)
    }

    @Test func aTitleIsSpokenWithWhereTheUserStands() {
        let lanes = dune.lanes
        #expect(lanes[0].titles[0].spoken(in: .book, startHere: false) == "Dune, 1965, Read")
        #expect(lanes[0].titles[1].spoken(in: .book, startHere: false)
            == "Dune Messiah, 1969, not in your library, next in this lane")
        #expect(lanes[1].titles[1].spoken(in: .film, startHere: true) == "Dune: Part Two, 2024, Watching, start here")
        #expect(lanes[2].titles[0].spoken(in: .show, startHere: false)
            == "Dune: Prophecy, 2024, side story, not in your library")
    }

    @Test func theShareCardSaysEachLanesCountAndAddTheRestCountsWhatIsMissing() {
        #expect(dune.shareLines == ["Books 1 of 2", "Films 1 of 2", "Shows 0 of 1"])
        #expect(dune.missing == 2)
    }

    @Test func tilesSitInARowPerLaneAndRungsJoinLanes() {
        let layout = WorldLayout(dune)
        let first = layout.origin(lane: 0, column: 0)
        let second = layout.origin(lane: 0, column: 1)
        #expect(second.x - first.x == WorldLayout.column)
        #expect(second.y == first.y)
        #expect(layout.origin(lane: 1, column: 0).y - first.y == WorldLayout.rowHeight)
        #expect(layout.size.width == WorldLayout.pad * 2 + WorldLayout.column + WorldLayout.tileWidth)
        #expect(layout.size.height == WorldLayout.pad + 3 * WorldLayout.rowHeight)

        // Two links cross lanes; each is drawn from the upper lane down, whichever way it points.
        let rungs = layout.rungs
        #expect(rungs.count == 2)
        #expect(rungs.allSatisfy { $0.upper.lane < $0.lower.lane })
        #expect(rungs.contains { $0.upper == (0, 0) && $0.lower == (1, 0) })
        #expect(rungs.contains { $0.upper == (1, 0) && $0.lower == (2, 0) })
    }

    @Test func aWorldIsReadyOnlyOnceBuiltWithTwoTitles() {
        #expect(WorldModel(api: nil, titleID: "t", world: dune).isReady)
        let building = StoryWorld(
            state: .building, total: 0, finished: 0, kinds: [], lanes: [], links: [], truncated: false, partial: false
        )
        #expect(!WorldModel(api: nil, titleID: "t", world: building).isReady)
        #expect(WorldModel(api: nil, titleID: "t", world: building).isBuilding)
        #expect(!WorldModel(api: nil, titleID: "t").isReady)
    }
}
