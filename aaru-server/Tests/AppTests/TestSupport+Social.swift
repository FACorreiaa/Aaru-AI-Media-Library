import Foundation
import Testing
@testable import aaru

/// A second signed-in user, for the social suites.
struct Person {
    let id: String
    let token: String
    let handle: String
}

func freshHandle() -> String {
    "g" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(15)
}

/// Gives the harness user a handle and returns it.
func claimHandle(_ env: LibraryHarness) async throws -> String {
    let handle = freshHandle()
    #expect(try await env.send(.put, "/v1/me/profile", json: ["handle": handle]).status == .ok)
    return handle
}

/// A second user with a handle, friends with the harness user.
func friend(_ env: LibraryHarness, of handle: String) async throws -> Person {
    let (id, token) = try await signedInUser(env.stores)
    let theirs = freshHandle()
    _ = try await env.send(.put, "/v1/me/profile", json: ["handle": theirs], token: token)
    _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": theirs])
    let accepted = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": handle], token: token)
    #expect(try accepted.json()["relationship"] as? String == "friend")
    return Person(id: id.description, token: token, handle: theirs)
}
