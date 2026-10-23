import AaruCore
import Crypto
import Foundation
import JWTKit
import SwiftASN1
import Testing
import X509
@testable import aaru

/// A chain shaped like Apple's (root, intermediate and leaf, with Apple's marker extensions),
/// made here so signed data can be verified end to end without Apple's keys.
struct TestAppleChain {
    let root: Certificate
    let x5c: [String]
    let leafKey: P256.Signing.PrivateKey

    init(markers: Bool = true) throws {
        let now = Date()
        let rootKey = P256.Signing.PrivateKey()
        let middleKey = P256.Signing.PrivateKey()
        leafKey = P256.Signing.PrivateKey()
        let rootName = try DistinguishedName { CommonName("Test Root") }
        let middleName = try DistinguishedName { CommonName("Test Intermediate") }
        let leafName = try DistinguishedName { CommonName("Test Leaf") }
        func certificate(
            _ key: P256.Signing.PrivateKey, subject: DistinguishedName, issuer: DistinguishedName,
            issuerKey: P256.Signing.PrivateKey, extensions: Certificate.Extensions
        ) throws -> Certificate {
            try Certificate(
                version: .v3, serialNumber: .init(), publicKey: .init(key.publicKey),
                notValidBefore: now.addingTimeInterval(-3600), notValidAfter: now.addingTimeInterval(86400),
                issuer: issuer, subject: subject, signatureAlgorithm: .ecdsaWithSHA256, extensions: extensions,
                issuerPrivateKey: .init(issuerKey)
            )
        }
        let authority = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            KeyUsage(keyCertSign: true)
        }
        var middleExtensions = authority
        var leafExtensions = Certificate.Extensions()
        if markers {
            try middleExtensions.append(Certificate.Extension(
                oid: AppleMarkerPolicy.intermediate,
                critical: false,
                value: [0x05, 0x00]
            ))
            try leafExtensions.append(Certificate.Extension(
                oid: AppleMarkerPolicy.leaf,
                critical: false,
                value: [0x05, 0x00]
            ))
        }
        root = try certificate(rootKey, subject: rootName, issuer: rootName, issuerKey: rootKey, extensions: authority)
        let middle = try certificate(
            middleKey, subject: middleName, issuer: rootName, issuerKey: rootKey, extensions: middleExtensions
        )
        let leaf = try certificate(
            leafKey, subject: leafName, issuer: middleName, issuerKey: middleKey, extensions: leafExtensions
        )
        // JWTKit takes the chain as PEM and writes it into the header as base64 DER, as Apple's is.
        x5c = try [leaf, middle, root].map { try $0.serializeAsPEM().pemString }
    }

    func sign(_ payload: some JWTPayload) async throws -> String {
        let keys = JWTKeyCollection()
        try await keys.add(ecdsa: ES256PrivateKey(backing: leafKey))
        return try await keys.sign(payload, header: ["x5c": .array(x5c.map(JWTHeaderField.string))])
    }
}

/// Signed data the tests hand out by name.
struct FakeAppleData: AppleSignedDataVerifying {
    var transactions: [String: AppleTransaction] = [:]
    var notifications: [String: AppleNotification] = [:]

    func transaction(_ jws: String) async throws -> AppleTransaction {
        guard let transaction = transactions[jws] else { throw AppleSignedDataError.invalid }
        return transaction
    }

    func notification(_ jws: String) async throws -> AppleNotification {
        guard let notification = notifications[jws] else { throw AppleSignedDataError.invalid }
        return notification
    }
}

@Suite("BIL: Aaru Plus on the App Store")
struct BillingTests {
    static let bundle = "com.fernandocorreia.aaru.beta"

    func payload(
        original: String = "2000000001", token: UUID? = UUID(), bundle: String = bundle,
        expires: Date? = Date().addingTimeInterval(30 * 86400), revoked: Date? = nil, signed: Date = Date()
    ) -> TransactionPayload {
        TransactionPayload(
            originalTransactionId: original, transactionId: original + "1", bundleId: bundle,
            productId: "aaru_plus_monthly", environment: "Sandbox", appAccountToken: token?.uuidString,
            expiresDate: expires.map { Int64($0.timeIntervalSince1970 * 1000) },
            revocationDate: revoked.map { Int64($0.timeIntervalSince1970 * 1000) },
            signedDateMs: Int64(signed.timeIntervalSince1970 * 1000)
        )
    }

    @Test("BIL-002: a transaction verifies up Apple-shaped chain, and nothing else does")
    func verifies() async throws {
        let chain = try TestAppleChain()
        let apple = try AppleSignedData(bundleIDs: [Self.bundle], rootCertificates: [chain.root])
        let token = UUID()
        let jws = try await chain.sign(payload(token: token))
        let transaction = try await apple.transaction(jws)
        #expect(transaction.originalTransactionID == "2000000001")
        #expect(transaction.appAccountToken == token)
        #expect(transaction.productID == "aaru_plus_monthly")
        #expect(transaction.expiresAt != nil)

        // Another bundle's purchase, a payload changed after signing, a chain without Apple's
        // markers, and a chain from another root.
        await #expect(throws: AppleSignedDataError.wrongBundle) {
            try await apple.transaction(chain.sign(payload(bundle: "com.example.other")))
        }
        let parts = jws.split(separator: ".")
        let forged = try await chain.sign(payload(original: "999"))
        let tampered = [parts[0], forged.split(separator: ".")[1], parts[2]].joined(separator: ".")
        await #expect(throws: AppleSignedDataError.invalid) { try await apple.transaction(tampered) }
        let unmarked = try TestAppleChain(markers: false)
        let lenient = try AppleSignedData(bundleIDs: [Self.bundle], rootCertificates: [unmarked.root])
        await #expect(throws: AppleSignedDataError.invalid) {
            try await lenient.transaction(unmarked.sign(payload()))
        }
        let production = try AppleSignedData(bundleIDs: [Self.bundle])
        await #expect(throws: AppleSignedDataError.invalid) { try await production.transaction(jws) }
    }

    @Test("BIL-002: Apple's root is the one bundled")
    func root() throws {
        let root = try Certificate(derEncoded: Array(AppleSignedData.appleRootG3))
        #expect(root.subject.description.contains("Apple Root CA - G3"))
        #expect(Data(SHA256.hash(data: AppleSignedData.appleRootG3)).map { String(format: "%02X", $0) }.joined()
            == "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179")
    }

    func transaction(
        _ env: LibraryHarness, original: String, token: UUID?, signed: Date = Date(),
        expires: Date? = Date().addingTimeInterval(86400), revoked: Date? = nil
    ) -> AppleTransaction {
        AppleTransaction(
            originalTransactionID: original, transactionID: original + "1", bundleID: Self.bundle,
            productID: "aaru_plus_yearly", environment: "Sandbox", appAccountToken: token, expiresAt: expires,
            revokedAt: revoked, signedAt: signed
        )
    }

    /// A film a capture link names by its numeric TMDB id.
    func stubFilm(_ env: LibraryHarness, _ name: String) -> String {
        let tmdb = String(Int.random(in: 10_000_000 ... 99_999_999))
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .movie, title: name, originalTitle: nil, year: 2001, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
            ),
            status: nil, runtimeMinutes: 100
        ))
        return tmdb
    }

    @Test("BIL-001: a purchase lifts the capture limit; another account's purchase is refused")
    func purchase() async throws {
        let original = uniqueID("orig")
        let other = uniqueID("other")
        let apple = FakeAppleData(transactions: [:])
        try await LibraryHarness.run(apple: apple) { env in
            var apple = apple
            apple.transactions["mine"] = transaction(env, original: original, token: env.userID.rawValue)
            apple.transactions["theirs"] = transaction(env, original: other, token: UUID())
            var services = env.services
            services.billing = BillingService(stores: env.stores, apple: apple)

            let free = try await services.billing.state(userID: env.userID)
            #expect(free.plus == nil)
            #expect(free.captureLimit == ImportService.freeCapturesPerMonth)

            let bought = try await services.billing.recordPurchase("mine", userID: env.userID)
            #expect(bought.plus?.originalTransactionID == original)
            #expect(bought.captureLimit == nil)
            // A restore sends it again: nothing changes.
            #expect(try await services.billing.recordPurchase("mine", userID: env.userID).plus != nil)

            await #expect(throws: AppError.self) {
                try await services.billing.recordPurchase("theirs", userID: env.userID)
            }
            await #expect(throws: AppError.self) {
                try await services.billing.recordPurchase("garbage", userID: env.userID)
            }

            let tmdb = stubFilm(env, uniqueID("Plus"))
            for _ in 0 ... ImportService.freeCapturesPerMonth {
                let created = try await env.send(
                    .post, "/v1/imports/capture", json: ["url": "https://www.themoviedb.org/movie/\(tmdb)"]
                )
                #expect(created.status == .accepted)
            }
            let entitlement = try await env.send(.get, "/v1/me/entitlement")
            let json = try entitlement.json()
            #expect(json["plus"] as? Bool == true)
            #expect(json["appAccountToken"] as? String == env.userID.description)
            #expect((json["capture"] as? [String: Any])?["limit"] == nil)
        }
    }

    @Test("BIL-003: notifications renew, refund and expire; a late one never undoes a newer state")
    func notifications() async throws {
        let original = uniqueID("orig")
        try await LibraryHarness.run { env in
            let now = Date()
            var apple = FakeAppleData()
            apple.transactions["bought"] = transaction(env, original: original, token: env.userID.rawValue)
            apple.notifications["refund"] = AppleNotification(
                type: "REFUND", subtype: nil, bundleID: Self.bundle,
                transaction: transaction(
                    env, original: original, token: env.userID.rawValue, signed: now.addingTimeInterval(60),
                    revoked: now
                )
            )
            apple.notifications["late"] = AppleNotification(
                type: "DID_RENEW", subtype: nil, bundleID: Self.bundle,
                transaction: transaction(
                    env, original: original, token: env.userID.rawValue, signed: now.addingTimeInterval(-60)
                )
            )
            apple.notifications["stranger"] = AppleNotification(
                type: "SUBSCRIBED", subtype: nil, bundleID: Self.bundle,
                transaction: transaction(env, original: uniqueID("x"), token: UUID())
            )
            apple.notifications["test"] = AppleNotification(
                type: "TEST", subtype: nil, bundleID: Self.bundle, transaction: nil
            )
            let billing = BillingService(stores: env.stores, apple: apple)
            _ = try await billing.recordPurchase("bought", userID: env.userID)
            try await billing.notify("refund")
            #expect(try await billing.state(userID: env.userID).plus == nil)
            try await billing.notify("late")
            #expect(try await billing.state(userID: env.userID).plus == nil)
            try await billing.notify("stranger")
            try await billing.notify("test")
            await #expect(throws: AppError.self) { try await billing.notify("forged") }
        }
    }

    @Test("BIL-003: Apple reaches the notification route without a session")
    func publicRoute() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(
                .post, "/v1/billing/apple/notifications", json: ["signedPayload": "x"], token: "not-a-session"
            )
            // No verifier configured in this harness: 503, not 401.
            #expect(reply.status == .serviceUnavailable)
        }
    }

    @Test("BIL-001: Plus keeps a fair-use cap of captures per UTC day")
    func fairUse() async throws {
        let original = uniqueID("orig")
        try await LibraryHarness.run { env in
            _ = try await env.stores.entitlements.record(Entitlement(
                originalTransactionID: original, userID: env.userID, productID: "aaru_plus_monthly",
                environment: "Sandbox", expiresAt: Date().addingTimeInterval(86400), revokedAt: nil, signedAt: Date()
            ), now: Date())
            let tmdb = stubFilm(env, uniqueID("Fair"))
            for _ in 0 ..< ImportService.plusCapturesPerDay {
                let created = try await env.send(
                    .post, "/v1/imports/capture", json: ["url": "https://www.themoviedb.org/movie/\(tmdb)"]
                )
                #expect(created.status == .accepted)
            }
            let refused = try await env.send(
                .post, "/v1/imports/capture", json: ["url": "https://www.themoviedb.org/movie/\(tmdb)"]
            )
            #expect(refused.status == .tooManyRequests)
            #expect(try refused.json()["code"] as? String == "capture_fair_use")
        }
    }
}
