import AaruAPI
import SwiftUI

typealias FriendProfile = Components.Schemas.FriendProfile
typealias FriendItem = Components.Schemas.FriendItem

/// A friend's profile, shelf first (SOC-001 / SOC-003): what they are watching, what you share,
/// what they finished. Friends only; the server answers 404 for anyone else.
struct FriendProfileView: View {
    let api: Client?
    let friend: SocialUser

    private enum Stage {
        case loading
        case gone
        case failed
        case loaded(FriendProfile)
    }

    @State private var stage = Stage.loading
    @State private var recommending = false
    @State private var invitingToGroup = false

    var body: some View {
        Group {
            switch stage {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gone:
                ContentUnavailableView(
                    "Not your friend",
                    systemImage: "person.slash",
                    description: Text("Only friends see each other's libraries.")
                )
            case .failed:
                LoadFailedView(
                    title: "Couldn't load this profile",
                    message: "Aaru could not reach the server. Check your connection and try again."
                ) { await load() }
            case let .loaded(profile):
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        ProfileHeader(profile: profile)
                        // GAM-005: shown only while they keep the switch on, whatever they share.
                        if let achievements = profile.achievements {
                            FriendBadgeRow(name: profile.user.inviteName, achievements: achievements)
                        }
                        if profile.sharing {
                            shelves(profile)
                        } else {
                            Text("\(profile.user.inviteName) keeps their library to themselves.")
                                .foregroundStyle(Color(.muted))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
            }
        }
        .background(Color(.paper))
        .navigationTitle(friend.inviteName)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task { await load() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Recommend a title", systemImage: "hand.thumbsup") { recommending = true }
                        Button("Invite to a group", systemImage: "bubble.left.and.bubble.right") {
                            invitingToGroup = true
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $recommending) {
                RecommendSheet(model: SocialModel(api: api), friend: friend)
            }
            .sheet(isPresented: $invitingToGroup) {
                GroupInviteSheet(api: api, friend: friend)
            }
    }

    @ViewBuilder
    private func shelves(_ profile: FriendProfile) -> some View {
        CoverShelf(title: "Watching", empty: "Nothing in progress.", covers: (profile.watching ?? []).map {
            Cover(title: $0.title, caption: $0.progress)
        })
        if let compare = profile.compare {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You both").font(.aaruDisplay(.title3))
                    Text(Self.bothFinished(compare.bothFinished))
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
                if !compare.bothWant.isEmpty {
                    CoverShelf(title: "Want to watch", small: true, covers: compare.bothWant.map { Cover(title: $0) })
                }
                if !compare.theyLoved.isEmpty {
                    CoverShelf(
                        title: "\(profile.user.inviteName) loved, you haven't", small: true,
                        covers: compare.theyLoved.map { Cover(title: $0) }
                    )
                }
            }
            .padding(16)
            .background(Color(.surface), in: .rect(cornerRadius: AaruRadius.field, style: .continuous))
        }
        CoverShelf(
            title: "Recently finished", empty: "Nothing finished yet.",
            covers: (profile.recentlyFinished ?? []).map {
                Cover(title: $0.title, caption: $0.rating.map { "★ \(ActivityWords.rating($0))" })
            }
        )
        // FAV-001: their top 10s, one row per kind they filled. Sent only while they share.
        if let favorites = profile.favorites, !favorites.filledKinds.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Favorites").font(.aaruDisplay(.title3))
                ForEach(favorites.filledKinds) { kind in
                    CoverShelf(title: kind.label, small: true, covers: favorites[kind].map { Cover(title: $0) })
                }
            }
        }
    }

    static func bothFinished(_ count: Int) -> String {
        switch count {
        case 0: "Nothing finished by both of you yet."
        case 1: "1 title finished by both of you"
        default: "\(count) titles finished by both of you"
        }
    }

    private func load() async {
        guard let api else { return }
        do {
            switch try await api.getFriendProfile(path: .init(userId: friend.userId)) {
            case let .ok(response): stage = try .loaded(response.body.json)
            case .default: stage = .gone
            }
        } catch {
            stage = .failed
        }
    }
}

private struct ProfileHeader: View {
    let profile: FriendProfile
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var typeSize

    private var since: String {
        profile.friendsSince.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        // Stacked at the accessibility sizes, so the name keeps the width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            Text(profile.user.monogram)
                .font(.aaruDisplay(.title))
                .frame(width: side, height: side)
                .background(Color(.medallion).opacity(AaruAlpha.ghost), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.user.inviteName)
                    .font(.aaruDisplay(.largeTitle))
                Text("@\(profile.user.handle) · Friends since \(since)")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                if let counts = profile.counts.flatMap(Self.countsLine) {
                    Text(counts).font(.subheadline).foregroundStyle(Color(.muted))
                }
            }
        }
    }

    /// "42 films · 12 shows · 8 books", leaving out kinds they have none of.
    static func countsLine(_ counts: Components.Schemas.KindCounts) -> String? {
        let parts = [
            Self.count(counts.movie, "film", "films"), Self.count(counts.show, "show", "shows"),
            Self.count(counts.anime, "anime", "anime"), Self.count(counts.manga ?? 0, "manga", "manga"),
            Self.count(counts.book, "book", "books"),
            Self.count(counts.album, "album", "albums"),
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func count(_ number: Int, _ one: String, _ many: String) -> String? {
        number > 0 ? "\(number) \(number == 1 ? one : many)" : nil
    }
}

private struct Cover: Identifiable {
    let title: Components.Schemas.TitleSummary
    var caption: String?

    var id: String {
        title.id
    }
}

/// A titled row of covers that scrolls sideways.
private struct CoverShelf: View {
    let title: String
    var empty: String?
    var small = false
    let covers: [Cover]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(small ? .subheadline.weight(.semibold) : .aaruDisplay(.title3))
            if covers.isEmpty, let empty {
                Text(empty).font(.subheadline).foregroundStyle(Color(.muted))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(covers) { cover in
                            VStack(alignment: .leading, spacing: 4) {
                                PosterView(
                                    url: cover.title.posterUrl.flatMap(URL.init(string:)),
                                    kind: MediaKind(type: cover.title._type, isAnime: cover.title.isAnime)
                                )
                                Text(cover.title.title).font(.footnote.weight(.medium)).lineLimit(2)
                                if let caption = cover.caption {
                                    Text(caption).font(.caption).foregroundStyle(Color(.muted))
                                }
                            }
                            .frame(width: 96)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

private extension FriendItem {
    /// "S2 · E4", "Page 120", or nothing.
    var progress: String? {
        if let season = lastSeason, let episode = lastEpisode {
            return EpisodeCode.short(season: season, number: episode)
        }
        return bookPage.map { "Page \($0)" } ?? mangaChapter.map { "Ch. \($0)" }
    }
}
