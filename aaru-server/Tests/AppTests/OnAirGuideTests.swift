import AaruCore
import Foundation
import Testing
@testable import aaru

/// The on-air guide (DISC-003) and its "streams on" (CAT-014) against canned JSON. No network.
@Suite("On the air by channel (DISC-003)")
struct OnAirGuideTests {
    /// 2026-10-20T12:00:00Z.
    static let now = DiscoverTests.now

    /// A listed day, midnight UTC.
    static func day(_ day: String) -> Date {
        Date.catalogDay(day) ?? .distantPast
    }

    static func instant(_ stamp: String) -> Date {
        ISO8601DateFormatter().date(from: stamp) ?? .distantPast
    }

    func client(_ transport: StubTransport, _ name: String) -> ProviderClient {
        ProviderClient(name: name, transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100))
    }

    static func show(
        _ title: String, tmdb: String, channel: String?, day: String, providers: [String: [String]] = [:]
    ) -> OnAirShow {
        OnAirShow(
            hit: DiscoverTests.hit(title, type: .show, tmdb: tmdb),
            channel: channel.map { OnAirChannel(name: $0) },
            next: OnAirEpisode(season: 1, number: 2, airsAt: Self.day(day)),
            providers: providers.mapValues { names in
                WatchProviders(
                    link: URL(string: "https://www.themoviedb.org/tv/\(tmdb)/watch"),
                    streaming: names.map { WatchProvider(name: $0) }
                )
            }
        )
    }

    static func entry(_ show: OnAirShow) -> (OnAirChannel?, OnAirEntry) {
        (show.channel, OnAirEntry(item: DiscoverItem(hit: show.hit), next: show.next, streamsOn: []))
    }

    // MARK: TMDB

    @Test("TMDB's on-the-air shows come with their network, next episode and every region's services")
    func tmdbOnAir() async throws {
        let stub = StubTransport { request in
            let body: String
            switch request.url.path {
            case "/3/tv/on_the_air":
                body = #"""
                {"total_pages":1,"results":[
                  {"id":101,"name":"Drama","poster_path":"/d.jpg","genre_ids":[18],"original_language":"en"},
                  {"id":102,"name":"Anime","poster_path":"/a.jpg","genre_ids":[16],"original_language":"ja"},
                  {"id":103,"name":"Later","poster_path":"/l.jpg","genre_ids":[18],"original_language":"en"},
                  {"id":104,"name":"No cover","genre_ids":[18],"original_language":"en"}]}
                """#
            case "/3/tv/101":
                #expect(request.url.query?.contains("append_to_response=external_ids,watch/providers") == true)
                body = #"""
                {"networks":[{"name":"HBO","logo_path":"/hbo.png"},{"name":"Other"}],
                 "next_episode_to_air":{"air_date":"2026-10-22","season_number":2,"episode_number":5,"name":"Five"},
                 "external_ids":{"imdb_id":"tt1","tvdb_id":81189},
                 "watch/providers":{"results":{
                   "US":{"link":"https://www.themoviedb.org/tv/101/watch?locale=US","flatrate":[
                     {"provider_name":"Max","logo_path":"/max.png","display_priority":2},
                     {"provider_name":"Hulu","logo_path":"/hulu.png","display_priority":1}]},
                   "PT":{"link":"https://x","flatrate":[]}}}}
                """#
            case "/3/tv/103":
                body = #"{"next_episode_to_air":{"air_date":"2026-12-01","season_number":1,"episode_number":1}}"#
            default:
                return OutboundResponse(status: 404, body: Data())
            }
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
        let shows = try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "k").onAir(now: Self.now)
        #expect(shows.map(\.hit.title) == ["Drama"], "anime, a far-off episode and a poster-less show are left out")
        let drama = try #require(shows.first)
        #expect(drama.channel == OnAirChannel(
            name: "HBO",
            logoURL: URL(string: "https://image.tmdb.org/t/p/w92/hbo.png")
        ))
        #expect(drama.hit.network == "HBO")
        #expect(drama.next == OnAirEpisode(
            season: 2,
            number: 5,
            name: "Five",
            airsAt: Self.day("2026-10-22")
        ))
        #expect(drama.hit.ids.tvdb == "81189" && drama.hit.ids.imdb == "tt1")
        #expect(drama.providers.keys.sorted() == ["US"], "a region with no streaming services is dropped")
        #expect(drama.providers["US"]?.streaming.map(\.name) == ["Hulu", "Max"], "by JustWatch's display priority")
    }

    // MARK: Grouping

    @Test("Channels with the most shows first, then by name, Other last; shows soonest first")
    func grouping() {
        let entries = [
            Self.show("B", tmdb: "1", channel: "Netflix", day: "2026-10-23"),
            Self.show("Lost", tmdb: "2", channel: nil, day: "2026-10-21"),
            Self.show("A", tmdb: "3", channel: "Netflix", day: "2026-10-21"),
            Self.show("C", tmdb: "4", channel: "BBC One", day: "2026-10-22"),
            Self.show("D", tmdb: "5", channel: "ABC", day: "2026-10-22"),
        ].map(Self.entry)
        let groups = DiscoverService.grouped(entries)
        #expect(groups.map(\.channel.name) == ["Netflix", "ABC", "BBC One", "Other"])
        #expect(groups.first?.shows.map(\.item.hit.title) == ["A", "B"])
    }

    @Test("Streams on leaves out the channel itself, resellers and repeats, three at most")
    func streamsOn() {
        let providers = [
            "Netflix",
            "Netflix Standard with Ads",
            "Hulu",
            "Max Amazon Channel",
            "Hulu",
            "Max",
            "Peacock",
            "Paramount Plus",
        ].map { WatchProvider(name: $0) }
        let names = DiscoverService.streamsOn(providers, channel: OnAirChannel(name: "Netflix")).map(\.name)
        #expect(names == ["Hulu", "Max", "Peacock"])
    }

    // MARK: Air times

    @Test("TVmaze gives the next episode's exact instant, found by TVDB id")
    func tvmazeNextAirTime() async throws {
        let stub = StubTransport { request in
            switch request.url.path {
            case "/lookup/shows" where request.url.query == "thetvdb=81189":
                return OutboundResponse(status: 200, body: Data(#"{"id":169,"network":{"name":"AMC"}}"#.utf8))
            case "/shows/169":
                #expect(request.url.query == "embed=nextepisode")
                return OutboundResponse(status: 200, body: Data(#"""
                {"id":169,"network":{"name":"AMC"},
                 "_embedded":{"nextepisode":{"season":2,"number":5,"airstamp":"2026-10-23T01:00:00+00:00"}}}
                """#.utf8))
            default:
                return OutboundResponse(status: 404, body: Data())
            }
        }
        let times = TVmazeAirTimes(client: client(stub, "tvmaze"))
        let stamp = try await times.nextAirTime(ids: ExternalIDs(tvdb: "81189"))
        #expect(stamp == Self.instant("2026-10-23T01:00:00Z"))
        #expect(try await times.nextAirTime(ids: ExternalIDs(imdb: "tt404")) == nil, "not on TVmaze")
    }

    @Test("An exact time far from TMDB's day is ignored; a failing lookup keeps the day")
    func refineTolerance() async throws {
        let shows = [
            Self.show("Close", tmdb: "1", channel: "HBO", day: "2026-10-22"),
            Self.show("Far", tmdb: "2", channel: "HBO", day: "2026-10-22"),
            Self.show("Down", tmdb: "3", channel: "HBO", day: "2026-10-22"),
        ]
        let timing = try StubTiming(stamps: [
            "1": Self.instant("2026-10-23T01:00:00Z"),
            "2": Self.instant("2026-11-05T01:00:00Z"),
        ])
        let refined = await DiscoverService.refine(shows, timing: timing)
        #expect(refined.map(\.next.airTimeKnown) == [true, false, false])
        #expect(refined[0].next.airsAt == Self.instant("2026-10-23T01:00:00Z"))
        #expect(refined[1].next.airsAt == Self.day("2026-10-22"))
    }

    // MARK: Cache

    @Test("The guide is served with dates first, then exact times once TVmaze answers")
    func publishesBeforeRefining() async throws {
        let gate = Gate()
        let timing = try StubTiming(
            stamps: ["1": Self.instant("2026-10-22T20:00:00Z")], gate: gate
        )
        let cache = OnAirCache()
        let fetches = Counter()
        let shows = [Self.show("Drama", tmdb: "1", channel: "HBO", day: "2026-10-22")]
        let read = { @Sendable in
            await cache.shows(
                now: Self.now,
                fetch: { await fetches.bump(); return shows },
                refine: { await DiscoverService.refine($0, timing: timing) }
            )
        }
        let first = await read()
        #expect(first?.shows.first?.next.airTimeKnown == false)
        await gate.open()
        var known = false
        for _ in 0 ..< 200 where !known {
            try await Task.sleep(for: .milliseconds(10))
            known = await read()?.shows.first?.next.airTimeKnown == true
        }
        #expect(known)
        #expect(await fetches.value == 1, "one fetch for the TTL")
    }

    @Test("A provider that fails with nothing cached gives an empty guide")
    func failureIsEmpty() async throws {
        let fake = FakeCatalog()
        fake.fail(with: ProviderError(provider: "tmdb", kind: .unavailable))
        let service = DiscoverService(stores: fakeStores(), providers: [fake])
        #expect(try await service.onAir(userID: UserID(), region: "US").channels.isEmpty)
    }

    // MARK: Route

    @Test("GET /v1/discover/on-air groups by channel, marks owned shows, lists the region's services")
    func route() async throws {
        try await LibraryHarness.run { env in
            let owned = env.stubShow("Owned", status: .returning)
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "show", "ids": ["tmdb": owned]],
            ])
            let itemID = try #require(try added.json()["id"] as? String)
            env.fake.stubOnAir([
                Self.show(
                    "Owned",
                    tmdb: owned,
                    channel: "Netflix",
                    day: "2026-10-22",
                    providers: ["US": ["Netflix", "Hulu"]]
                ),
                Self.show("New", tmdb: "x-1", channel: nil, day: "2026-10-21"),
            ])

            let reply = try await env.send(.get, "/v1/discover/on-air?region=us")
            #expect(reply.status == .ok)
            let channels = try #require(try reply.json()["channels"] as? [[String: Any]])
            #expect(channels.map { $0["name"] as? String } == ["Netflix", "Other"])
            let show = try #require((channels.first?["shows"] as? [[String: Any]])?.first)
            #expect((show["item"] as? [String: Any])?["libraryItemId"] as? String == itemID)
            #expect((show["streamsOn"] as? [[String: Any]])?.map { $0["name"] as? String } == ["Hulu"])
            #expect(show["watchLink"] is String)
            let next = try #require(show["nextEpisode"] as? [String: Any])
            #expect(next["airTimeKnown"] as? Bool == false && next["season"] as? Int == 1)

            let other = try #require((channels.last?["shows"] as? [[String: Any]])?.first)
            #expect(other["streamsOn"] == nil, "no data for the region: nothing rather than an empty list")

            let bad = try await env.send(.get, "/v1/discover/on-air?region=usa")
            #expect(bad.status == .unprocessableContent)
        }
    }
}

/// Exact times by TMDB id; with a gate, every answer waits until it opens.
private struct StubTiming: NextEpisodeTiming {
    var stamps: [String: Date]
    var gate: Gate?

    func nextAirTime(ids: ExternalIDs) async throws -> Date? {
        await gate?.wait()
        guard let stamp = ids.tmdb.flatMap({ stamps[$0] }) else {
            throw ProviderError(provider: "tvmaze", kind: .unavailable)
        }
        return stamp
    }
}

private actor Counter {
    private(set) var value = 0

    func bump() {
        value += 1
    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
