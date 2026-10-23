import SwiftUI

/// Missed (CAL-003): what aired in the last four weeks without a tick, one card per show, oldest
/// miss first, so catching up starts where it should.
struct CatchUpView: View {
    let feed: CalendarFeed
    /// Missed's four weeks: "all caught up" only once this window has loaded (UX-062).
    let window: Range<Date>
    /// Set while a filter is on: the empty state offers "Clear filters" (UX-067).
    var onClearFilters: (() -> Void)?
    var retry: () async -> Void

    /// One request, inside the 42-day limit.
    static let days = 28

    var body: some View {
        let shows = feed.missed()
        ScrollView {
            if let failure = feed.loadProblem(for: window) {
                LoadFailedView(title: "Missed didn't load", message: failure, retry: retry)
                    .padding(.top, 40)
            } else if !feed.covers(window) {
                ProgressView().padding(40)
            } else if shows.isEmpty, let onClearFilters {
                ContentUnavailableView {
                    Label("No missed episodes match these filters", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear filters", action: onClearFilters)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            } else if shows.isEmpty {
                OwlUnavailableView(
                    title: "You are all caught up",
                    message: "Nothing from your shows aired in the last four weeks without a tick.",
                    pose: .sleeping
                )
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
                .clipShape(RoundedRectangle(cornerRadius: AaruRadius.row, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title.title)
                        .font(.aaruDisplay(.title3, weight: .semibold))
                        .lineLimit(3)
                        .accessibilityAddTraits(.isHeader)
                    Text(show.line)
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                    if let network = show.title.network {
                        Text(network).font(.caption).foregroundStyle(Color(.muted))
                    }
                }
            }
            .padding(.horizontal, AaruSpace.large)
            .padding(.top, AaruSpace.large)
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
        .card()
    }
}
