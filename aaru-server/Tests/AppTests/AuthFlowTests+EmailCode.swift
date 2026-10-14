import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// APP-002: the 6-digit code that rides in every sign-in email.
extension AuthFlowTests {
    func requestLink(_ client: any TestClientProtocol, _ email: String) async throws {
        try await client.execute(
            uri: "/v1/auth/email/link", method: .post, headers: [.contentType: "application/json"],
            body: json(["email": email])
        ) { response in
            #expect(response.status == .accepted)
        }
    }

    func verify(_ client: any TestClientProtocol, _ body: [String: String]) async throws -> HTTPResponse.Status {
        try await client.execute(
            uri: "/v1/auth/email/verify", method: .post, headers: [.contentType: "application/json"],
            body: json(body)
        ) { $0.status }
    }

    @Test("APP-002: the emailed code signs in once, and using it kills the link too")
    func codeSignsInOnce() async throws {
        let outbox = Outbox()
        try await withApp(outbox: outbox) { client, _ in
            let email = "\(UUID().uuidString)@example.com"
            try await requestLink(client, email)
            let code = try #require(outbox.lastCode)
            let link = try #require(outbox.last)
            let token = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "token" }?.value)
            let spaced = "\(code.prefix(3)) \(code.suffix(3))"
            #expect(try await verify(client, ["email": email.uppercased(), "code": spaced]) == .ok)
            #expect(try await verify(client, ["email": email, "code": code]) == .unauthorized)
            #expect(try await verify(client, ["token": token]) == .unauthorized)
        }
    }

    @Test("APP-002: five wrong codes lock the link, even for the right code")
    func wrongCodesLock() async throws {
        let outbox = Outbox()
        try await withApp(outbox: outbox) { client, _ in
            let email = "\(UUID().uuidString)@example.com"
            try await requestLink(client, email)
            let code = try #require(outbox.lastCode)
            let wrong = code == "000000" ? "000001" : "000000"
            for _ in 0 ..< AuthService.maxCodeAttempts {
                #expect(try await verify(client, ["email": email, "code": wrong]) == .unauthorized)
            }
            #expect(try await verify(client, ["email": email, "code": code]) == .unauthorized)
        }
    }

    @Test("APP-002: a code only works with the email it was sent to")
    func codeBoundToEmail() async throws {
        let outbox = Outbox()
        try await withApp(outbox: outbox) { client, _ in
            let email = "\(UUID().uuidString)@example.com"
            try await requestLink(client, email)
            let code = try #require(outbox.lastCode)
            #expect(try await verify(client, ["email": "other-\(email)", "code": code]) == .unauthorized)
            #expect(try await verify(client, ["email": email, "code": code]) == .ok)
        }
    }

    @Test("APP-002: verify needs a token or an email and code; a malformed code is 422")
    func verifyValidation() async throws {
        try await withApp { client, _ in
            let empty = try await verify(client, [:])
            let short = try await verify(client, ["email": "a@b.test", "code": "12345"])
            #expect(empty == .unprocessableContent)
            #expect(short == .unprocessableContent)
        }
    }
}
