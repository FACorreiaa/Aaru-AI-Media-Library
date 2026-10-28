import Foundation

extension AuthMiddleware {
    /// The address per-address limits count. The web Worker reaches the API from Cloudflare's
    /// addresses, so every web visitor would share one bucket; it names the visitor in
    /// `X-Aaru-Visitor` and proves itself with `X-Aaru-Web-Secret`. Without the secret (or with
    /// none configured) the header is ignored and the forwarded hop counts, as before.
    static func rateLimitAddress(
        visitor: String?,
        presentedSecret: String?,
        secret: String,
        fallback: String
    ) -> String {
        guard !secret.isEmpty,
              let presentedSecret,
              InternalMetricsRoutes.constantTimeEquals(presentedSecret, secret),
              let visitor = visitor?.trimmingCharacters(in: .whitespaces),
              isAddress(visitor)
        else { return fallback }
        return visitor
    }

    /// One IPv4 or IPv6 address, nothing else (no list, no port, no name).
    private static func isAddress(_ text: String) -> Bool {
        (2 ... 45).contains(text.count)
            && text.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
            && (text.contains(".") || text.contains(":"))
    }
}
