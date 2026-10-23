import Foundation
import JWTKit
import SwiftASN1
import X509

/// BIL-002 · App Store signed data, checked the way Apple's server library does it with online
/// checks off: the `x5c` chain must end at Apple Root CA - G3, carry Apple's marker extensions
/// (leaf 1.2.840.113635.100.6.11.1, intermediate 1.2.840.113635.100.6.2.1), and be valid when
/// Apple signed the payload; the JWS must verify with the leaf's key; the bundle id must be one of
/// Aaru's.
struct AppleSignedData: AppleSignedDataVerifying {
    let verifier: X5CVerifier
    let bundleIDs: Set<String>

    init(bundleIDs: Set<String>, rootCertificates: [Certificate]? = nil) throws {
        let roots = try rootCertificates ?? [Certificate(derEncoded: Array(Self.appleRootG3))]
        verifier = try X5CVerifier(rootCertificates: roots)
        self.bundleIDs = bundleIDs
    }

    func transaction(_ jws: String) async throws -> AppleTransaction {
        let payload = try await verify(jws, as: TransactionPayload.self)
        guard bundleIDs.contains(payload.bundleId) else { throw AppleSignedDataError.wrongBundle }
        return payload.transaction
    }

    func notification(_ jws: String) async throws -> AppleNotification {
        let payload = try await verify(jws, as: NotificationPayload.self)
        if let bundle = payload.data?.bundleId, !bundleIDs.contains(bundle) {
            throw AppleSignedDataError.wrongBundle
        }
        let transaction = try await payload.data?.signedTransactionInfo.asyncMap { try await self.transaction($0) }
        return AppleNotification(
            type: payload.notificationType, subtype: payload.subtype, bundleID: payload.data?.bundleId,
            transaction: transaction
        )
    }

    private func verify<Payload: JWTPayload>(_ jws: String, as _: Payload.Type) async throws -> Payload {
        do {
            return try await verifier.verifyJWS(
                Array(jws.utf8), as: Payload.self, jsonDecoder: JSONDecoder(), policy: { AppleMarkerPolicy() }
            )
        } catch {
            throw AppleSignedDataError.invalid
        }
    }

    /// Apple Root CA - G3 (DER), from apple.com/certificateauthority. SHA-256
    /// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79.
    static let appleRootG3 = Data(base64Encoded: """
    MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQL
    DB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMw
    MTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRp
    ZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IA
    BJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqX
    l5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8w
    DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWT
    xnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==
    """.filter { !$0.isWhitespace }) ?? Data()
}

enum AppleSignedDataError: Error, Equatable {
    case invalid
    case wrongBundle
}

/// Apple's marker extensions on the leaf and the intermediate.
struct AppleMarkerPolicy: VerifierPolicy {
    static let leaf: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 6, 11, 1]
    static let intermediate: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 6, 2, 1]

    let verifyingCriticalExtensions: [ASN1ObjectIdentifier] = []

    func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        guard chain.count == 3 else { return .failsToMeetPolicy(reason: "Not leaf, intermediate and root.") }
        guard chain[0].extensions[oid: Self.leaf] != nil, chain[1].extensions[oid: Self.intermediate] != nil else {
            return .failsToMeetPolicy(reason: "Missing Apple's marker extensions.")
        }
        return .meetsPolicy
    }
}

// MARK: Payloads

/// Apple's dates are milliseconds since 1970.
private extension Date {
    init(milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

struct TransactionPayload: JWTPayload, ValidationTimePayload {
    var originalTransactionId: String
    var transactionId: String
    var bundleId: String
    var productId: String
    var environment: String
    var appAccountToken: String?
    var expiresDate: Int64?
    var revocationDate: Int64?
    var signedDateMs: Int64

    enum CodingKeys: String, CodingKey {
        case originalTransactionId, transactionId, bundleId, productId, environment, appAccountToken
        case expiresDate, revocationDate
        case signedDateMs = "signedDate"
    }

    var signedDate: Date {
        Date(milliseconds: signedDateMs)
    }

    var transaction: AppleTransaction {
        AppleTransaction(
            originalTransactionID: originalTransactionId, transactionID: transactionId, bundleID: bundleId,
            productID: productId, environment: environment,
            appAccountToken: appAccountToken.flatMap { UUID(uuidString: $0) },
            expiresAt: expiresDate.map(Date.init(milliseconds:)),
            revokedAt: revocationDate.map(Date.init(milliseconds:)), signedAt: signedDate
        )
    }

    func verify(using _: some JWTAlgorithm) async throws {}
}

struct NotificationPayload: JWTPayload, ValidationTimePayload {
    struct Body: Codable, Sendable {
        var bundleId: String?
        var environment: String?
        var signedTransactionInfo: String?
    }

    var notificationType: String
    var subtype: String?
    var data: Body?
    var signedDateMs: Int64

    enum CodingKeys: String, CodingKey {
        case notificationType, subtype, data
        case signedDateMs = "signedDate"
    }

    var signedDate: Date {
        Date(milliseconds: signedDateMs)
    }

    func verify(using _: some JWTAlgorithm) async throws {}
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
