import AaruAPI
import SwiftUI

/// The Friends tab (SOC-002 / SOC-003): friends' last two weeks, then invites, requests and
/// friends. A friend opens their profile. Without a handle there is nothing social yet, so the
/// tab asks for one first.
struct FriendsScreen: View {
    @State private var model: SocialModel

    init(api: Client?) {
        _model = State(initialValue: SocialModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.hasLoaded, model.handle == nil {
                    ContentUnavailableView {
                        Label("Choose a handle", systemImage: "at")
                    } description: {
                        Text("Friends see who you are by your handle. Nobody can search or browse for you.")
                    } actions: {
                        NavigationLink("Choose a handle") { ProfileEditor(model: model) }
                            .buttonStyle(.borderedProminent)
                    }
                    .background(Color(.paper))
                    .navigationTitle("Friends")
                } else {
                    FriendsView(model: model)
                }
            }
            .navigationDestination(for: SocialUser.self) { friend in
                FriendProfileView(api: model.api, friend: friend)
            }
        }
        .task { await model.load() }
    }
}

extension SocialUser: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}

/// One friend's day with one title: "Ana watched S1 · E3 Andor", with its poster.
struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.user.monogram)
                .font(.subheadline.weight(.medium))
                .frame(width: 36, height: 36)
                .background(Color(.medallion).opacity(0.2), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence).lineLimit(3)
                Text(ActivityWords.day(item.day))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 8)
            PosterView(
                url: item.title.posterUrl.flatMap(URL.init(string:)),
                kind: MediaKind(type: item.title._type, isAnime: item.title.isAnime)
            )
            .frame(width: 40)
        }
        .accessibilityElement(children: .combine)
    }

    private var sentence: AttributedString {
        var name = AttributedString(item.user.inviteName)
        name.font = .body.weight(.semibold)
        var title = AttributedString(item.title.title)
        title.font = .body.weight(.semibold)
        var line = name + AttributedString(" \(ActivityWords.verb(item)) ") + title
        if item.finished, let rating = item.rating {
            line += AttributedString(" · ★ \(ActivityWords.rating(rating))")
        }
        return line
    }
}

/// How activity reads, the same words as the web's.
enum ActivityWords {
    static func verb(_ item: ActivityItem) -> String {
        var watched: String?
        if let season = item.lastSeason, let episode = item.lastEpisode {
            let last = "S\(season) · E\(episode)"
            watched = item.episodes > 1 ? "watched \(item.episodes) episodes, up to \(last)" : "watched \(last)"
        }
        if item.finished {
            return watched.map { "\($0) and finished" } ?? "finished"
        }
        return watched ?? "watched"
    }

    /// "Today", "Yesterday", else "Sat 17 Oct". `day` is the UTC day the server grouped by.
    static func day(_ day: String, now: Date = .now) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // Noon UTC, so the weekday reads the same in every time zone.
        guard let date = try? Date(day + "T12:00:00Z", strategy: .iso8601) else { return day }
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func rating(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}
