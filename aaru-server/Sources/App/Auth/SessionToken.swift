import Crypto
import Foundation

/// Opaque bearer tokens (sessions, magic links). The secret is shown to the client
/// once; Postgres stores only its SHA-256, so a database dump cannot sign anyone in.
enum OpaqueToken {
    /// 32 random bytes, base64url without padding.
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        sha256Hex(token)
    }
}

/// The 6-digit code in a sign-in email. Hashed with its email, so a code alone matches nothing.
enum EmailCode {
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0 ... 999_999, using: &generator))
    }

    static func hash(_ code: String, email: String) -> String {
        sha256Hex("\(email):\(code)")
    }

    /// Digits only, so "123 456" and "123-456" both work. Nil unless exactly six digits remain.
    static func normalized(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.count == 6 && digits.allSatisfy(\.isASCII) ? digits : nil
    }
}

func sha256Hex(_ string: String) -> String {
    SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
}
