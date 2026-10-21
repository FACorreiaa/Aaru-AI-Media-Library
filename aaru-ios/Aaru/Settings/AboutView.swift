import SwiftUI

/// PRV-001: who Aaru is, which build this is, and the credits every catalog provider requires
/// (`docs/providers.md`, column "Credit Aaru shows"). In Settings it also holds the way out.
struct AboutView: View {
    /// Settings → About ends with Delete account; nil leaves it out.
    var onDeleteAccount: (() async -> String?)?

    @State private var confirmsDelete = false
    @State private var deleteProblem: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(.wordmark)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        .accessibilityLabel("Aaru")
                    Text("A private library for everything you watch and read.")
                        .foregroundStyle(Color(.muted))
                }
                .padding(.vertical, 6)
                LabeledContent("Version", value: Self.version)
                LabeledContent("Channel", value: AppEnvironment.channel)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
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
                CreditLink("Anime data from AniList", url: "https://anilist.co")
                CreditLink(
                    "Anime id mappings from Fribb/anime-lists",
                    detail: "Licensed under MIT",
                    url: "https://github.com/Fribb/anime-lists",
                    licence: "https://opensource.org/license/mit"
                )
                CreditLink("Book data from Open Library", url: "https://openlibrary.org")
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
            }

            if onDeleteAccount != nil {
                Section {
                    Button("Delete account", role: .destructive) { confirmsDelete = true }
                    if let deleteProblem {
                        Text(deleteProblem).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(
                        "Deletes your library, lists, imports and sessions from Aaru for good. Export your data "
                            + "first, in Imports & export, if you want to keep it."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("About")
        .confirmationDialog(
            "Delete your Aaru account?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account and library", role: .destructive) {
                Task { deleteProblem = await onDeleteAccount?() }
            }
        } message: {
            Text("This cannot be undone. Export your data first if you want to keep it.")
        }
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
