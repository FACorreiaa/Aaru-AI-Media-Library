import AaruCore
import Foundation
import Testing
@testable import aaru

/// SHR-002: one concert by its Ticketmaster id, for a share link.
extension ConcertAdapterTests {
    static let oneEvent = #"""
    {"id":"E1","name":"Radiohead","url":"https://www.ticketmaster.pt/event/E1",
     "dates":{"start":{"localDate":"2026-11-02","localTime":"21:00:00","dateTime":"2026-11-02T21:00:00Z"},
              "status":{"code":"onsale"}},
     "_embedded":{"venues":[{"name":"MEO Arena","city":{"name":"Lisboa"},"country":{"name":"Portugal"}}],
                  "attractions":[{"name":"Radiohead"}]}}
    """#

    @Test("An event by id reads one event; a 404 is nil")
    func eventByID() async throws {
        let stub = StubTransport { request in
            request.url.path().hasSuffix("/events/E1.json")
                ? OutboundResponse(status: 200, body: Data(Self.oneEvent.utf8))
                : OutboundResponse(status: 404, body: Data())
        }
        let concert = try #require(try await adapter(stub).event(id: "E1"))
        #expect(concert.id == "E1")
        #expect(concert.name == "Radiohead")
        #expect(concert.venue == "MEO Arena")
        #expect(concert.url.absoluteString == "https://www.ticketmaster.pt/event/E1")
        #expect(try await adapter(stub).event(id: "E9") == nil)
    }
}

extension ConcertAPITests {
    @Test("A concert by id is cached; a failure or concerts off is nil, never an error")
    func concertByID() async throws {
        let fake = FakeConcerts()
        fake.events["Z1"] = sampleConcert("Z1", "2026-11-02")
        try await LibraryHarness.run(concerts: fake) { env in
            #expect(await env.services.concerts.concert(id: "Z1")?.name == "Show Z1")
            #expect(await env.services.concerts.concert(id: "Z1")?.name == "Show Z1")
            #expect(fake.eventCalls == ["Z1"], "the second open is served from the cache")
            fake.fail(true)
            #expect(await env.services.concerts.concert(id: "Z2") == nil)
        }
        try await LibraryHarness.run { env in
            #expect(await env.services.concerts.concert(id: "Z1") == nil)
        }
    }
}
