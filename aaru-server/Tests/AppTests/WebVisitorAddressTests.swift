import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// The web Worker reaches the API from Cloudflare's addresses, so it names the visitor in
/// `X-Aaru-Visitor` and proves itself with `X-Aaru-Web-Secret`. Only then do per-address limits
/// count the visitor; anyone else naming a visitor is ignored.
struct WebVisitorAddressTests {
    @Test("the visitor counts only with the Worker's secret")
    func visitorNeedsSecret() {
        let address = { (visitor: String?, presented: String?, secret: String) in
            AuthMiddleware.rateLimitAddress(
                visitor: visitor, presentedSecret: presented, secret: secret, fallback: "10.0.0.1"
            )
        }
        #expect(address("198.51.100.7", "s3cret", "s3cret") == "198.51.100.7")
        #expect(address("2001:db8::1", "s3cret", "s3cret") == "2001:db8::1")
        #expect(address("198.51.100.7", "wrong", "s3cret") == "10.0.0.1")
        #expect(address("198.51.100.7", nil, "s3cret") == "10.0.0.1")
        #expect(address("198.51.100.7", "", "") == "10.0.0.1")
        #expect(address(nil, "s3cret", "s3cret") == "10.0.0.1")
        #expect(address("not an ip", "s3cret", "s3cret") == "10.0.0.1")
        #expect(address("1.2.3.4, 5.6.7.8", "s3cret", "s3cret") == "10.0.0.1")
    }

    @Test("a sign-in email limit is per visitor behind the Worker, not per Worker")
    func magicLinkLimitPerVisitor() async throws {
        let secret = "s3cret-for-tests"
        try await withMigratedStores { stores in
            let auth = AuthService(
                stores: stores,
                apple: AuthFlowTests.FixedApple(subject: UUID().uuidString),
                magicLinks: (AuthFlowTests.Outbox(), URL(string: "https://aaru.test/auth/verify")!)
            )
            let services = Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
            let app = try Application(router: buildRouter(
                stores: stores, services: services, secrets: .init(webClient: secret)
            ))
            try await app.test(.router) { client in
                func send(_ headers: HTTPFields) async throws -> HTTPResponse.Status {
                    var all = headers
                    all[.contentType] = "application/json"
                    let body = try ByteBuffer(bytes: JSONSerialization.data(
                        withJSONObject: ["email": "\(UUID().uuidString)@example.com"]
                    ))
                    return try await client.execute(
                        uri: "/v1/auth/email/link", method: .post, headers: all, body: body
                    ) { $0.status }
                }
                let worker: HTTPFields = [.xForwardedFor: "104.28.0.1"]
                for _ in 0 ..< 20 {
                    let status = try await send(worker)
                    #expect(status == .accepted)
                }
                let over = try await send(worker)
                #expect(over == .tooManyRequests)

                var visitor = worker
                visitor[.aaruVisitor] = "198.51.100.7"
                visitor[.aaruWebSecret] = secret
                let named = try await send(visitor)
                #expect(named == .accepted)

                var forged = worker
                forged[.aaruVisitor] = "198.51.100.8"
                forged[.aaruWebSecret] = "guess"
                let guessed = try await send(forged)
                #expect(guessed == .tooManyRequests)
            }
        }
    }
}
