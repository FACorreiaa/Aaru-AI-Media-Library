import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Sports: the TheSportsDB adapter (SPT-001)")
struct SportsAdapterTests {
    func adapter(_ stub: StubTransport) -> TheSportsDBSports {
        TheSportsDBSports(
            client: ProviderClient(
                name: "thesportsdb", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            apiKey: "test-key"
        )
    }

    func header(_ request: OutboundRequest, _ name: String) -> String? {
        request.headers.first { $0.0 == name }?.1
    }

    @Test("Search sends the key as a header and the name as an underscored slug; reads teams and fighters")
    func search() async throws {
        let stub = StubTransport { request in
            let body = request.url.path.contains("/player/")
                ? #"""
                {"search":[{"idPlayer":"34215679","strPlayer":"Alex Pereira","idTeam":"135481",
                  "strTeam":"UFC Heavyweight","strSport":"Fighting","strCutout":"https://r2.thesportsdb.com/p.png"}]}
                """#
                : #"""
                {"search":[{"idTeam":133604,"strTeam":"Arsenal","idLeague":"4328","strSport":"Soccer",
                  "strBadge":"https://r2.thesportsdb.com/b.png","strCountry":"England"},{"strTeam":"no id"}]}
                """#
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
        let teams = try await adapter(stub).search(.team, "  Arsenal  FC ")
        let request = try #require(stub.requests.first)
        #expect(request.url.absoluteString == "https://www.thesportsdb.com/api/v2/json/search/team/arsenal_fc")
        #expect(header(request, "X-API-KEY") == "test-key")
        #expect(!request.url.absoluteString.contains("test-key"), "v2 keeps the key out of the URL")
        #expect(teams == [SportEntity(
            kind: .team, id: "133604", name: "Arsenal", sport: "Soccer",
            badgeURL: URL(string: "https://r2.thesportsdb.com/b.png"), country: "England", leagueID: "4328"
        )], "a number id is read as text; a row without an id is skipped")

        let fighters = try await adapter(stub).search(.player, "Alex Pereira")
        #expect(fighters.first?.teamID == "135481" && fighters.first?.sport == "Fighting")
        #expect(fighters.first?.badgeURL?.absoluteString == "https://r2.thesportsdb.com/p.png")
    }

    @Test("Schedules read scores given as text, the UTC timestamp, and cards without sides")
    func schedule() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(#"""
        {"schedule":[
          {"idEvent":"1","strEvent":"Arsenal vs Everton","strSport":"Soccer","idLeague":"4328",
           "strLeague":"English Premier League","idHomeTeam":"133604","strHomeTeam":"Arsenal",
           "idAwayTeam":"133615","strAwayTeam":"Everton","intHomeScore":"2","intAwayScore":"0",
           "strTimestamp":"2026-10-18T14:00:00","dateEvent":"2026-10-18","strStatus":"Match Finished","intRound":"8"},
          {"idEvent":"2558809","strEvent":"UFC 333 Volkanovski vs Evloev","strSport":"Fighting","idLeague":"4443",
           "strLeague":"UFC","idHomeTeam":null,"strHomeTeam":null,"strTimestamp":"2026-10-24T16:00:00+00:00",
           "dateEvent":"2026-10-24","strStatus":"","strPoster":"https://r2.thesportsdb.com/poster.jpg"}
        ]}
        """#.utf8)) }
        let events = try await adapter(stub).schedule(.previous, .team, id: "133604")
        #expect(stub.requests.first?.url.path == "/api/v2/json/schedule/previous/team/133604")
        let match = try #require(events.first)
        #expect(match.home?.score == 2 && match.away?.score == 0 && match.status == .finished)
        #expect(match.startsAt == ISO8601DateFormatter().date(from: "2026-10-18T14:00:00Z"))
        #expect(match.round == "Round 8" && match.involves(team: "133615"))
        let card = try #require(events.last)
        #expect(card.home == nil && card.away == nil && card.status == .scheduled)
        #expect(card.imageURL?.absoluteString == "https://r2.thesportsdb.com/poster.jpg")

        #expect(try await adapter(stub).schedule(.next, .player, id: "1").isEmpty, "players have no schedule")
    }

    @Test("A league's day and an event's TV go through v1 with the key in the path")
    func v1Calls() async throws {
        let stub = StubTransport { request in
            let body = request.url.path.hasSuffix("lookuptv.php")
                ? #"""
                {"tvevent":[{"strChannel":"Sky Sports Main Event","strCountry":"United Kingdom",
                  "strLogo":"https://r2.thesportsdb.com/sky.png"},{"strCountry":"Nowhere"}]}
                """#
                : #"{"events":null}"#
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
        let day = try await adapter(stub).events(day: "2026-10-24", leagueID: "4328")
        #expect(day.isEmpty, "TheSportsDB says null for an empty day")
        let dayURL = try #require(stub.requests.first?.url.absoluteString)
        #expect(dayURL == "https://www.thesportsdb.com/api/v1/json/test-key/eventsday.php?d=2026-10-24&l=4328")
        let channels = try await adapter(stub).broadcasts(eventID: "42")
        #expect(channels == [SportBroadcast(
            channel: "Sky Sports Main Event", country: "United Kingdom",
            logoURL: URL(string: "https://r2.thesportsdb.com/sky.png")
        )])
    }

    @Test("Livescores become events with the clock; a sentence instead of rows is no rows")
    func live() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(#"""
        {"livescore":[
          {"idEvent":"9","strSport":"Soccer","idLeague":"4328","strLeague":"English Premier League",
           "idHomeTeam":"133604","strHomeTeam":"Arsenal","idAwayTeam":"133615","strAwayTeam":"Everton",
           "intHomeScore":1,"intAwayScore":"1","strStatus":"2H","strProgress":"67","dateEvent":"2026-10-24"},
          {"idEvent":"10","strHomeTeam":"A","strAwayTeam":"B","strStatus":"","strProgress":"NS",
           "dateEvent":"2026-10-24"}
        ]}
        """#.utf8)) }
        let live = try await adapter(stub).live()
        #expect(stub.requests.first?.url.path == "/api/v2/json/livescore/all")
        #expect(live.first?.status == .live && live.first?.progress == "67")
        #expect(live.first?.home?.score == 1 && live.first?.away?.score == 1)
        #expect(live.last?.status == .scheduled, "a blank status falls back to the clock: NS")

        stub.respond { _ in OutboundResponse(status: 200, body: Data(#"{"livescore":"No data found"}"#.utf8)) }
        #expect(try await adapter(stub).live().isEmpty)
    }

    @Test("Statuses: the provider's many spellings map to five")
    func statuses() {
        #expect(TheSportsDBSports.status(nil) == .scheduled)
        #expect(TheSportsDBSports.status("Not Started") == .scheduled)
        #expect(TheSportsDBSports.status("FT") == .finished)
        #expect(TheSportsDBSports.status("Match Finished") == .finished)
        #expect(TheSportsDBSports.status("AET") == .finished)
        #expect(TheSportsDBSports.status("PST") == .postponed)
        #expect(TheSportsDBSports.status("NS", postponed: "yes") == .postponed)
        #expect(TheSportsDBSports.status("CANC") == .cancelled)
        #expect(TheSportsDBSports.status("Abandoned") == .cancelled)
        #expect(TheSportsDBSports.status("HT") == .live)
        #expect(TheSportsDBSports.status("Q3") == .live)
    }
}
