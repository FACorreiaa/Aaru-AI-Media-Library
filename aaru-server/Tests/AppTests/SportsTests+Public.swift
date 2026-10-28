import AaruCore
import Foundation
import Testing
@testable import aaru

/// SHR-002: a shared match opens for anyone, so the lookup reads no user.
extension SportsAPITests {
    @Test("A public event needs no user, keeps its score and shares the event cache")
    func publicEventNeedsNoUser() async throws {
        let fake = provider()
        fake.events["42"] = sampleMatch(
            "42", home: "133604", away: "133615", at: "2026-10-18T14:00:00Z", homeScore: 2, awayScore: 1
        )
        try await LibraryHarness.run(sports: fake) { env in
            let event = try #require(try await env.services.sports.publicEvent(id: "42"))
            #expect(event.home?.score == 2)
            #expect(event.away?.score == 1)
            #expect(event.status == .finished, "a past event with a score is finished")
            _ = try await env.services.sports.publicEvent(id: "42")
            #expect(fake.asked.filter { $0 == "event:42" }.count == 1, "the second open is served from the cache")
            #expect(try await env.services.sports.publicEvent(id: "999") == nil)
        }
    }

    @Test("A public event with sports off is SportsOff")
    func publicEventOff() async throws {
        try await LibraryHarness.run { env in
            await #expect(throws: SportsOff.self) {
                _ = try await env.services.sports.publicEvent(id: "42")
            }
        }
    }
}
