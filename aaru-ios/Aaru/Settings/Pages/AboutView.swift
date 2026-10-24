import SwiftUI

/// PRV-001: who Aaru is, which build this is, and the credits every catalog provider requires
/// (`docs/providers.md`, column "Credit Aaru shows"). Delete account is its own page (UX-021).
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: AaruSpace.medium) {
                    Image(.wordmark)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        .foregroundStyle(Color(.ink))
                        .accessibilityLabel("Aaru")
                    Text("A private library for everything you watch, read and listen to.")
                        .foregroundStyle(Color(.muted))
                }
                .padding(.vertical, 6)
                LabeledContent("Version", value: Self.version)
                LabeledContent("Channel", value: AppEnvironment.channel)
            }

            Section {
                VStack(alignment: .leading, spacing: AaruSpace.medium) {
                    // Smaller than Aaru's own wordmark, as TMDB's terms require.
                    Image(.tmdbLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 12)
                        .accessibilityLabel("The Movie Database (TMDB)")
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                }
                .padding(.vertical, 4)
                CreditLink(
                    "Air times from TVmaze",
                    detail: "Licensed under CC BY-SA 4.0",
                    url: "https://www.tvmaze.com",
                    licence: "https://creativecommons.org/licenses/by-sa/4.0/"
                )
                CreditLink("Where to stream from JustWatch", url: "https://www.justwatch.com")
                CreditLink("Anime data from AniList", url: "https://anilist.co")
                CreditLink(
                    "Anime id mappings from Fribb/anime-lists",
                    detail: "Licensed under MIT",
                    url: "https://github.com/Fribb/anime-lists",
                    licence: "https://opensource.org/license/mit"
                )
                CreditLink("Book data from Open Library", url: "https://openlibrary.org")
                CreditLink("Music data from MusicBrainz", url: "https://musicbrainz.org")
                CreditLink("Album rows from ListenBrainz", url: "https://listenbrainz.org")
                CreditLink("Covers from the Cover Art Archive", url: "https://coverartarchive.org")
                CreditLink("Concerts from Ticketmaster", url: "https://www.ticketmaster.com")
                CreditLink("Sports data from TheSportsDB", url: "https://www.thesportsdb.com")
                CreditLink("City search by Open-Meteo", url: "https://open-meteo.com")
                CreditLink(
                    "History import from Trakt",
                    detail: "Aaru uses Trakt but is not endorsed or certified by Trakt.",
                    url: "https://trakt.tv"
                )
            } header: {
                Text("Credits")
            }

            Section {
                Link("Privacy policy", destination: Self.url("https://aaruapp.com/privacy"))
                Link("About Aaru on the web", destination: Self.url("https://aaruapp.com/about"))
                Link("Contact", destination: Self.url("mailto:privacy@aaruapp.com"))
                Link("Join us on Discord", destination: Self.url("https://discord.gg/GG55YPANC"))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("About")
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// Literal URLs only; a malformed one would be a typo caught in review.
    fileprivate static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }
}

/// A credit line that opens the provider's site, with an optional licence link under it.
private struct CreditLink: View {
    let title: String
    var detail: String?
    let url: String
    var licence: String?

    init(_ title: String, detail: String? = nil, url: String, licence: String? = nil) {
        self.title = title
        self.detail = detail
        self.url = url
        self.licence = licence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(title, destination: AboutView.url(url))
            if let detail, let licence {
                Link(detail, destination: AboutView.url(licence))
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
        }
    }
}

#Preview("Light") {
    NavigationStack { AboutView() }
}

#Preview("Dark") {
    NavigationStack { AboutView() }
        .preferredColorScheme(.dark)
}
