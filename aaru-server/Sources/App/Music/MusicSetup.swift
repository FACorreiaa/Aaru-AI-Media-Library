import aaruAPI
import Foundation

/// The scrobblers Settings offers for a music token (MUS-007). A token is named for its
/// scrobbler, so the list of connections says which is which.
enum MusicScrobbler: String, CaseIterable, Sendable {
    case webScrobbler = "web_scrobbler"
    case panoScrobbler = "pano_scrobbler"
    case navidrome
    case jellyfin
    case other

    init(_ dto: Components.Schemas.MusicScrobbler?) {
        self = dto.flatMap { Self(rawValue: $0.rawValue) } ?? .other
    }

    var title: String {
        switch self {
        case .webScrobbler: "Web Scrobbler"
        case .panoScrobbler: "Pano Scrobbler"
        case .navidrome: "Navidrome"
        case .jellyfin: "Jellyfin"
        case .other: "Music scrobbler"
        }
    }
}

/// MUS-007 · how to point each scrobbler at Aaru's ListenBrainz endpoint, written once here so
/// the web and Apple apps show the same steps. Only answered right after minting, with the real
/// token in it.
enum MusicSetup {
    typealias Step = Components.Schemas.MusicSetup.StepsPayloadPayload
    typealias Field = Step.FieldsPayloadPayload

    /// `https://api.aaruapp.com/listenbrainz/`, what clients that add `1/submit-listens` want.
    static func baseURL(_ publicBaseURL: URL) -> String {
        publicBaseURL.appendingPathComponent("listenbrainz").absoluteString + "/"
    }

    /// The full submit URL, for clients that ask for it.
    static func submitURL(_ publicBaseURL: URL) -> String {
        publicBaseURL.appendingPathComponent(ListenBrainzRoutes.path)
            .appendingPathComponent("submit-listens").absoluteString
    }

    static func setup(
        for scrobbler: MusicScrobbler,
        publicBaseURL: URL,
        secret: String
    ) -> Components.Schemas.MusicSetup {
        let base = baseURL(publicBaseURL)
        let submit = submitURL(publicBaseURL)
        let token = Field(label: "Token", value: secret, secret: true)
        return Components.Schemas.MusicSetup(
            scrobbler: .init(rawValue: scrobbler.rawValue) ?? .other,
            title: scrobbler.title,
            submitUrl: submit,
            baseUrl: base,
            steps: steps(scrobbler, base: base, submit: submit, token: token)
        )
    }

    private static func steps(_ scrobbler: MusicScrobbler, base: String, submit: String, token: Field) -> [Step] {
        // Verified against each client's source, 2026-10-21. They disagree on the address:
        // Web Scrobbler wants the submit URL, Pano the root with a slash, Navidrome the root with
        // `1/`, and Jellyfin the root with no slash at all.
        let root = String(base.dropLast())
        return switch scrobbler {
        case .webScrobbler: webScrobbler(submit: submit, token: token)
        case .panoScrobbler: panoScrobbler(base: base, token: token)
        case .navidrome: navidrome(base: base, token: token)
        case .jellyfin: jellyfin(root: root, token: token)
        case .other: other(root: root, submit: submit, token: token)
        }
    }

    private static let play = Step(text: "Play a song. It shows up here within a few seconds.")

    private static func webScrobbler(submit: String, token: Field) -> [Step] {
        [
            Step(
                text: "Install Web Scrobbler for Chrome, Firefox, Edge or Safari.",
                link: .init(label: "Get Web Scrobbler", url: "https://web-scrobbler.com")
            ),
            Step(
                text: "Open its options, then Accounts. On the ListenBrainz card, choose Use local instance and "
                    + "paste these. Don't use Love: it sends the token to listenbrainz.org.",
                fields: [Field(label: "API URL", value: submit), token]
            ),
            play,
        ]
    }

    private static func panoScrobbler(base: String, token: Field) -> [Step] {
        [
            Step(
                text: "Install Pano Scrobbler on Android, Windows or Linux.",
                link: .init(
                    label: "Get Pano Scrobbler",
                    url: "https://play.google.com/store/apps/details?id=com.arn.scrobble"
                )
            ),
            Step(
                text: "In Pano's settings, under Services, choose ListenBrainz-like instance 1. Paste these and "
                    + "verify.",
                fields: [Field(label: "API URL", value: base), Field(
                    label: "Authentication token",
                    value: token.value,
                    secret: true
                )]
            ),
            play,
        ]
    }

    private static func navidrome(base: String, token: Field) -> [Step] {
        [
            Step(
                text: "Set this in Navidrome's configuration and restart it. It applies to everyone on that "
                    + "Navidrome server.",
                fields: [Field(label: "ND_LISTENBRAINZ_BASEURL", value: base + "1/")]
            ),
            Step(
                text: "In Navidrome, open your user menu → Personal, turn on Scrobble to ListenBrainz, paste the "
                    + "token and save.",
                fields: [token]
            ),
            play,
        ]
    }

    private static func jellyfin(root: String, token: Field) -> [Step] {
        [
            Step(
                text: "In Jellyfin, add this repository under Dashboard → Plugins → Repositories, then install "
                    + "ListenBrainz from the catalog and restart.",
                fields: [Field(label: "Repository", value: "https://repo.xkrivo.net/jellyfin/manifest.json")]
            ),
            Step(
                text: "In the plugin's General tab, set the ListenBrainz API URL. It applies to everyone on that "
                    + "Jellyfin server.",
                fields: [Field(label: "ListenBrainz API URL", value: root)]
            ),
            Step(
                text: "In User Config, pick your user, paste the token, turn on Enable submitting listens and save. "
                    + "Leave favorites sync off.",
                fields: [Field(label: "ListenBrainz API token", value: token.value, secret: true)]
            ),
            play,
        ]
    }

    private static func other(root: String, submit: String, token: Field) -> [Step] {
        [
            Step(
                text: "In the app's ListenBrainz settings, use a custom server. Most ask for the server, some for "
                    + "the full submit URL. If it wants an address ending in /1/, add that to the server.",
                fields: [Field(label: "Server", value: root), Field(label: "Submit URL", value: submit), token]
            ),
            play,
        ]
    }
}
