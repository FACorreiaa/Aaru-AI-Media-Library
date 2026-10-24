import AaruAPI
import SwiftUI

/// On air (DISC-003): the shows with a new episode this week, one row per channel or streamer,
/// busiest first. Each card says the next episode, at its exact time when TVmaze knows it, and
/// where else it streams in the device's region. A "Where to watch" link opens TMDB's page.
struct OnAirView: View {
    let model: OnAirModel
    let compact: Bool
    let onAddToList: (CatalogHit) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let guide = model.guide, !guide.channels.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AaruSpace.section) {
                    Text("Shows with a new episode this week, by where they air.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                        .padding(.horizontal, 20)
                    ForEach(guide.channels, id: \.name) { channel in
                        HomeRow(title: channel.name, note: OnAirModel.count(channel)) {
                            ForEach(channel.shows, id: \.item.id) { show in
                                card(show)
                            }
                        }
                    }
                    DiscoverCredits(providers: ["TMDB", "TVmaze", "JustWatch"])
                }
                .padding(.vertical, 16)
            }
        } else if model.guide == nil, !model.failed {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.guide == nil {
            LoadFailedView(
                title: "Couldn't load On air",
                message: "This week's airings didn't load. Try again in a few minutes."
            ) { await model.load() }
        } else {
            ContentUnavailableView {
                Label("Nothing on air right now", systemImage: "tv")
            } description: {
                Text("The week's airings aren't answering right now. Try again in a few minutes.")
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func card(_ show: OnAirShow) -> some View {
        let hit = show.item
        return DiscoverCard(
            hit: hit,
            libraryItemID: model.libraryItemID(hit),
            lines: [OnAirModel.episodeLine(show.nextEpisode), OnAirModel.streamsLine(show)].compactMap(\.self),
            width: HomeCardSize.poster.width(compact: compact, dynamicType: dynamicType),
            isAdding: model.adding.contains(hit.id)
        ) { status in
            Task { await model.add(hit, status: status) }
        } onAddToList: {
            onAddToList(hit)
        }
        .contextMenu {
            if let link = show.watchLink.flatMap(URL.init(string:)) {
                Button("Where to watch", systemImage: "play.tv") { openURL(link) }
            }
        }
    }
}

// MARK: Previews

#Preview("On air") {
    NavigationStack {
        OnAirView(model: OnAirModel(preview: .sample), compact: true) { _ in }
            .background(Color(.paper))
    }
}

extension OnAirGuide {
    /// Two channels, one exact time and one day-only, for previews.
    static var sample: OnAirGuide {
        let hit = { (title: String, tmdb: String) in
            CatalogHit(_type: .show, title: title, isAnime: false, ids: .init(tmdb: tmdb))
        }
        return OnAirGuide(channels: [
            .init(name: "HBO", shows: [
                .init(
                    item: hit("The Night Shift", "1"),
                    nextEpisode: .init(
                        season: 2, number: 5, airsAt: .now.addingTimeInterval(86400), airTimeKnown: true
                    ),
                    streamsOn: [.init(name: "Max")]
                ),
            ]),
            .init(name: "Netflix", shows: [
                .init(
                    item: hit("Harbour Lights", "2"),
                    nextEpisode: .init(
                        season: 1, number: 3, airsAt: .now.addingTimeInterval(2 * 86400), airTimeKnown: false
                    )
                ),
            ]),
        ])
    }
}
