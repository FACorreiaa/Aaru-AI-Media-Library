import SwiftUI

/// Missed (CAL-003): what aired in the last four weeks without a tick, one card per show, oldest
/// miss first, so catching up starts where it should.
struct CatchUpView: View {
    let feed: CalendarFeed
    var onSearch: () -> Void

    /// One request, inside the 42-day limit.
    static let days = 28

    var body: some View {
        let shows = feed.missed()
        ScrollView {
            if !feed.hasLoaded, feed.isLoading {
                ProgressView().padding(40)
            } else if shows.isEmpty {
                ContentUnavailableView {
                    Label("You are all caught up", systemImage: "checkmark.seal")
                } description: {
                    Text("Nothing from your shows aired in the last four weeks without a tick.")
                }
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(shows) { show in
                        card(show)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.paper))
    }

    private func card(_ show: MissedShow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                PosterView(
                    url: show.title.posterUrl.flatMap(URL.init(string:)),
                    kind: show.title.isAnime ? .anime : .show
                )
                .frame(width: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .lineLimit(2)
                    Text(show.line)
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                    if let network = show.title.network {
                        Text(network).font(.caption).foregroundStyle(Color(.muted))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            ForEach(show.episodes, id: \.cellID) { entry in
                CalendarEpisodeRow(
                    entry: entry, feed: feed,
                    detail: "Aired " + entry.airsAt.formatted(
                        Date.FormatStyle(timeZone: entry.airTimeKnown ? .current : .gmt)
                            .weekday(.abbreviated).day().month(.abbreviated)
                    )
                )
            }
        }
        .padding(.bottom, 8)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 20))
    }
}
