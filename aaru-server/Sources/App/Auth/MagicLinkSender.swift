import Foundation

protocol MagicLinkSending: Sendable {
    func send(to email: String, link: URL) async throws
}

/// Resend's `POST /emails` body.
private struct ResendEmail: Encodable {
    let from: String
    let recipients: [String]
    let subject: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case from, subject, text
        case recipients = "to"
    }
}

/// Sends the sign-in link through Resend (the provider LuminaVault already uses).
struct ResendMagicLinkSender: MagicLinkSending {
    static let endpoint = URL(string: "https://api.resend.com/emails")!

    let transport: any HTTPTransport
    let apiKey: String
    let from: String

    func send(to email: String, link: URL) async throws {
        let payload = ResendEmail(
            from: from,
            recipients: [email],
            subject: "Your Aaru sign-in link",
            text: """
            Sign in to Aaru:

            \(link.absoluteString)

            The link works once and expires in 15 minutes. If you did not ask for it, ignore this email.
            """
        )
        let response = try await transport.send(OutboundRequest(
            method: "POST",
            url: Self.endpoint,
            headers: [("Authorization", "Bearer \(apiKey)"), ("Content-Type", "application/json")],
            body: JSONEncoder().encode(payload)
        ))
        guard (200 ..< 300).contains(response.status) else {
            throw AppError(
                status: .badGateway,
                code: "email_unavailable",
                message: "The sign-in email could not be sent."
            )
        }
    }
}
