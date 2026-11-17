import AaruAPI
import Testing
@testable import Aaru

/// Where to watch (CAT-014): which groups the section shows, and which titles ask at all.
@MainActor
struct TitleWatchTests {
    @Test func onlyGroupsWithAServiceAreShownStreamingFirst() {
        let places = TitleWatchPlaces(
            region: "PT",
            streaming: [.init(name: "Netflix")],
            rent: [],
            buy: [.init(name: "Apple TV"), .init(name: "Rakuten TV")]
        )
        let groups = TitleWatchModel.groups(places)
        #expect(groups.map(\.kind) == [.stream, .buy])
        #expect(groups[1].services.map(\.name) == ["Apple TV", "Rakuten TV"])
    }

    @Test func nothingToShowIsNoGroups() {
        #expect(TitleWatchModel.groups(nil).isEmpty)
        #expect(TitleWatchModel.groups(.init(region: "JP", streaming: [], rent: [], buy: [])).isEmpty)
    }

    @Test func onlyWatchedKindsAskAndOnlyWithARegion() {
        #expect(TitleWatchModel.asks(kind: .film, region: "PT"))
        #expect(TitleWatchModel.asks(kind: .show, region: "US"))
        #expect(TitleWatchModel.asks(kind: .anime, region: "US"))
        #expect(!TitleWatchModel.asks(kind: .book, region: "PT"))
        #expect(!TitleWatchModel.asks(kind: .manga, region: "PT"))
        #expect(!TitleWatchModel.asks(kind: .music, region: "PT"))
        #expect(!TitleWatchModel.asks(kind: .film, region: nil))
    }

    @Test func theLinkIsTheProvidersPage() {
        let model = TitleWatchModel(
            api: nil, titleID: "t",
            places: .init(
                region: "PT",
                streaming: [.init(name: "Max")],
                rent: [],
                buy: [],
                link: "https://www.themoviedb.org/movie/603/watch?locale=PT"
            )
        )
        #expect(model.link?.host() == "www.themoviedb.org")
        #expect(TitleWatchModel(api: nil, titleID: "t").link == nil)
    }
}
