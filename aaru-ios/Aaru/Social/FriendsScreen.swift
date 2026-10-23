import AaruAPI
import SwiftUI

/// Friends (SOC-002 / SOC-003): friends' last two weeks, then invites, requests and friends. A
/// friend opens their profile. A sidebar destination on iPad and Mac; on iPhone, Groups pushes
/// `FriendsContent` (the five tabs are full, §18). Shares Settings' `SocialModel`, so the handle
/// and the sharing switch read the same everywhere.
struct FriendsScreen: View {
    let social: SocialModel

    var body: some View {
        NavigationStack {
            FriendsContent(model: social)
        }
    }
}

/// Friends without a stack of its own, for a sidebar's stack or Groups' on iPhone. Without a
/// handle there is nothing social yet, so it asks for one first.
struct FriendsContent: View {
    let model: SocialModel

    var body: some View {
        Group {
            if let problem = model.loadProblem, !model.hasLoaded {
                LoadFailedView(title: "Friends didn't load", message: problem) { await model.load() }
                    .navigationTitle("Friends")
            } else if !model.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Friends")
            } else if model.handle == nil {
                OwlUnavailableView(
                    title: "Choose a handle",
                    message: "Friends see who you are by your handle. Nobody can search or browse for you."
                ) {
                    NavigationLink("Choose a handle") { ProfileEditor(model: model) }
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Friends")
            } else {
                FriendsView(model: model)
            }
        }
        .background(Color(.paper))
        .task { await model.load() }
    }
}

/// One friend's day with one title: "Ana watched S1 · E3 Andor", with its poster.
struct ActivityRow: View {
    let item: ActivityItem
    /// Your own row shows what friends left but takes no reaction.
    var own = false
    var onReact: (String) -> Void = { _ in }
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            Text(item.user.monogram)
                .font(.subheadline.weight(.medium))
                .frame(width: side, height: side)
                .background(Color(.medallion).opacity(0.2), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence).lineLimit(3)
                Text(ActivityWords.day(item.day))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                ReactionStrip(item: item, own: own, onReact: onReact)
            }
            Spacer(minLength: 8)
            PosterView(
                url: item.title.posterUrl.flatMap(URL.init(string:)),
                kind: MediaKind(type: item.title._type, isAnime: item.title.isAnime)
            )
            .frame(width: 40)
        }
    }

    private var sentence: AttributedString {
        var name = AttributedString(own ? "You" : item.user.inviteName)
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
            let last = EpisodeCode.short(season: season, number: episode)
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

/// The reactions on a row, and (on a friend's row) a menu of the six to add or change yours.
private struct ReactionStrip: View {
    let item: ActivityItem
    let own: Bool
    let onReact: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(item.reactions ?? [], id: \.emoji) { reaction in
                let mine = item.myReaction == reaction.emoji
                Button {
                    onReact(reaction.emoji)
                } label: {
                    Text("\(reaction.emoji) \(reaction.count)")
                        .font(.footnote)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(mine ? Color(.accent).opacity(0.15) : Color(.surface), in: .capsule)
                        .overlay {
                            if mine {
                                Capsule().strokeBorder(Color(.accent))
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(own)
                .accessibilityLabel("\(reaction.emoji), \(reaction.count)")
                .accessibilityAddTraits(mine ? .isSelected : [])
            }
            if !own {
                Menu {
                    ForEach(SocialModel.reactions, id: \.self) { emoji in
                        Button(emoji) { onReact(emoji) }
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.footnote)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.surface), in: .capsule)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("React")
            }
        }
    }
}
