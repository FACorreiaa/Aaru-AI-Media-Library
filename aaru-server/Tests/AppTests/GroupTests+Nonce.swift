import Foundation
import Testing
@testable import aaru

extension GroupTests {
    @Test("GRP-006: a retried nonce answers the first message; reused in another channel it is a conflict")
    func nonceRetryStaysInItsChannel() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let (group, general) = try await createGroup(env)
            let other = try await env.send(.post, "/v1/groups/\(group)/channels", json: ["name": "other"])
            let otherID = try #require(try other.json()["id"] as? String)
            let path = "/v1/groups/\(group)/channels/\(general)/messages"
            let first = try await env.send(.post, path, json: ["body": "hi", "clientNonce": "n-1"]).json()
            let retry = try await env.send(.post, path, json: ["body": "hi", "clientNonce": "n-1"]).json()
            #expect(retry["id"] as? String == first["id"] as? String)
            let elsewhere = try await env.send(
                .post, "/v1/groups/\(group)/channels/\(otherID)/messages", json: ["body": "hi", "clientNonce": "n-1"]
            )
            #expect(elsewhere.status == .conflict)
            let otherMessages = try await env.send(.get, "/v1/groups/\(group)/channels/\(otherID)/messages")
            #expect(try bodies(otherMessages).isEmpty)
        }
    }
}
