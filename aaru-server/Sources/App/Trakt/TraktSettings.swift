import Crypto
import Foundation

/// IMP-002 configuration. Trakt issues no client secret to this app: sign-in is PKCE only, and
/// the client id is public.
struct TraktSettings: Sendable {
    static let authorizeURL = URL(string: "https://auth.trakt.tv/oauth/authorize")!
    static let apiURL = URL(string: "https://api.trakt.tv")!

    var clientID: String
    /// Must be registered on the Trakt app exactly. `https://` on Aaru's own API host.
    var redirectURI: URL
    /// Where a finished connect may send the browser: the apps' URL scheme and the web origin.
    var returnPrefixes: [String]
    var tokenCipher: TokenCipher

    func allowsReturn(to url: String) -> Bool {
        returnPrefixes.contains { url.hasPrefix($0) }
    }
}

/// Encrypts provider tokens at rest (AES-GCM). A database dump without the key reads nothing.
struct TokenCipher: Sendable {
    let key: SymmetricKey

    init(base64Key: String) throws {
        guard let data = Data(base64Encoded: base64Key), data.count == 32 else {
            throw TokenCipherError.invalidKey
        }
        key = SymmetricKey(data: data)
    }

    func seal(_ plaintext: String) throws -> String {
        guard let combined = try AES.GCM.seal(Data(plaintext.utf8), using: key).combined else {
            throw TokenCipherError.sealFailed
        }
        return combined.base64EncodedString()
    }

    func open(_ sealed: String) throws -> String {
        guard let data = Data(base64Encoded: sealed) else { throw TokenCipherError.openFailed }
        let box = try AES.GCM.SealedBox(combined: data)
        guard let text = try String(bytes: AES.GCM.open(box, using: key), encoding: .utf8) else {
            throw TokenCipherError.openFailed
        }
        return text
    }
}

enum TokenCipherError: Error {
    case invalidKey, sealFailed, openFailed
}

/// PKCE (RFC 7636, S256 only, as Trakt requires).
enum PKCE {
    /// 64 characters from the unreserved set.
    static func verifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0 ..< 64).map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)] })
    }

    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
