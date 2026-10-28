import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// `GET /internal/metrics`, the user count facorreia.com/apps reads with `METRICS_SECRET`.
@Suite("Internal metrics (facorreia.com/apps)", .serialized)
struct InternalMetricsTests {
    private static let secret = "shared-secret"

    private func withClient(
        secret: String = Self.secret,
        _ body: @escaping @Sendable (any TestClientProtocol, Stores) async throws -> Void
    ) async throws {
        try await withMigratedStores { stores in
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            let services = Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
            let app = try Application(router: buildRouter(
                stores: stores,
                services: services,
                secrets: .init(metrics: secret)
            ))
            try await app.test(.router) { client in
                try await body(client, stores)
            }
        }
    }

    @Test("the right bearer gets the number of accounts")
    func count() async throws {
        try await withClient { client, stores in
            _ = try await signedInUser(stores)
            try await client.execute(
                uri: InternalMetricsRoutes.path, method: .get, headers: [.authorization: "Bearer \(Self.secret)"]
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.cacheControl] == "no-store")
                let body = try #require(
                    JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                )
                #expect(Set(body.keys) == ["users"])
                #expect(try #require(body["users"] as? Int) >= 1)
            }
        }
    }

    @Test("no bearer, a wrong one and a bare secret are all 401", arguments: [
        nil, "Bearer not-the-secret", "Bearer shared-secreT", "shared-secret",
    ])
    func rejected(authorization: String?) async throws {
        try await withClient { client, _ in
            var headers = HTTPFields()
            headers[.authorization] = authorization
            try await client.execute(uri: InternalMetricsRoutes.path, method: .get, headers: headers) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("a session token is not the metrics secret")
    func sessionToken() async throws {
        try await withClient { client, stores in
            let (_, token) = try await signedInUser(stores)
            try await client.execute(
                uri: InternalMetricsRoutes.path, method: .get, headers: [.authorization: "Bearer \(token)"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("an empty METRICS_SECRET turns the route off")
    func disabled() async throws {
        try await withClient(secret: "") { client, _ in
            try await client.execute(
                uri: InternalMetricsRoutes.path, method: .get, headers: [.authorization: "Bearer anything"]
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }
}
