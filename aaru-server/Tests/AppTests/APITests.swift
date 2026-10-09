import AaruCore
import Configuration
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

@Suite("API contract")
struct APITests {
    @Test("GET /v1/health is 200 ok when the database answers")
    func healthOK() async throws {
        let app = try Application(router: fakeRouter())
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .ok)
                let status = try healthStatus(response.body)
                #expect(status == "ok")
            }
        }
    }

    @Test("GET /v1/health is 503 with no database detail when the database is down")
    func healthUnavailable() async throws {
        let app = try Application(router: fakeRouter(databaseReachable: false))
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                let status = try healthStatus(response.body)
                #expect(status == "unavailable")
                #expect(String(buffer: response.body).count < 40, "no database detail in the body")
            }
        }
    }

    @Test("An unknown route returns 404 in the shared error shape")
    func notFoundShape() async throws {
        let app = try Application(router: fakeRouter())
        try await app.test(.router) { client in
            try await client.execute(uri: "/does-not-exist", method: .get) { response in
                #expect(response.status == .notFound)
                let body = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                #expect(body.code == "not_found")
                #expect(!body.message.isEmpty)
            }
        }
    }

    @Test("A /v1 route without a session is 401 in the shared shape, and does not reveal whether it exists")
    func anonymousIsUnauthorized() async throws {
        let app = try Application(router: fakeRouter())
        try await app.test(.router) { client in
            for uri in ["/v1/me", "/v1/does-not-exist"] {
                try await client.execute(uri: uri, method: .get) { response in
                    #expect(response.status == .unauthorized)
                    let body = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                    #expect(body.code == "unauthorized")
                }
            }
        }
    }

    @Test("A validation failure returns 422 naming the field")
    func validationShape() async throws {
        let router = try fakeRouter()
        router.get("/test/rating") { _, _ -> String in
            _ = try Rating(11)
            return "unreachable"
        }
        let app = Application(router: router)
        try await app.test(.router) { client in
            try await client.execute(uri: "/test/rating", method: .get) { response in
                #expect(response.status == .unprocessableContent)
                let body = try JSONDecoder().decode(ErrorBody.self, from: Data(buffer: response.body))
                #expect(body.code == "validation_failed")
                #expect(body.details?["rating"] != nil)
            }
        }
    }

    @Test("An unexpected error is an opaque 500")
    func internalErrorIsOpaque() async throws {
        struct Secret: Error {}
        let router = try fakeRouter()
        router.get("/test/boom") { _, _ -> String in throw Secret() }
        let app = Application(router: router)
        try await app.test(.router) { client in
            try await client.execute(uri: "/test/boom", method: .get) { response in
                #expect(response.status == .internalServerError)
                let text = String(buffer: response.body)
                #expect(text.contains(#""code":"internal""#))
                #expect(!text.contains("Secret"))
            }
        }
    }

    @Test("Serving without TMDB_API_KEY fails naming the key")
    func missingTMDBKey() throws {
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "postgres.user": "u",
            "postgres.password": "p",
            "postgres.database": "d",
        ]))
        #expect {
            try AppConfig.load(from: reader)
        } throws: { error in
            (error as? MissingConfigError)?.environmentName == "TMDB_API_KEY"
                && "\(error)".contains("TMDB_API_KEY")
        }
    }
}

private func healthStatus(_ body: ByteBuffer) throws -> String {
    struct Health: Decodable { let status: String }
    return try JSONDecoder().decode(Health.self, from: Data(buffer: body)).status
}

private struct ErrorBody: Decodable {
    let code: String
    let message: String
    let details: [String: String]?
}
