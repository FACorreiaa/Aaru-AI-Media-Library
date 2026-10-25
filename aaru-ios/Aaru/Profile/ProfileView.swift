import AaruAPI
import SwiftUI

/// The profile (GAM-006b, pulled forward 2026-10-22): who you are and everything the library adds
/// up to, all time. Opens as a sheet from the medallion in Home's toolbar. Top to bottom: the
/// header, the time watched, four count tiles that open Library, where the time went, genres,
/// most watched, where you watch, ratings, favorites, and the way to Insights and the Recap. Static,
/// like Insights (DESIGN.md §13b): numbers and bars appear at their final value.
struct ProfileView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// Closes the sheet and shows Library filtered to one kind.
    var onShowKind: (MediaKind) -> Void

    @State private var model: ProfileModel
    @State private var recap: RecapPeriod?
    @Environment(\.dismiss) private var dismiss

    init(
        api: Client?,
        library: LibraryModel,
        lists: ListsModel,
        model: ProfileModel? = nil,
        onShowKind: @escaping (MediaKind) -> Void = { _ in }
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.onShowKind = onShowKind
        _model = State(initialValue: model ?? ProfileModel(api: api))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profile")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .task { await model.load() }
                .refreshable { await model.load() }
                .recapStory($recap, api: api)
                .background(Color(.paper))
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 640, idealHeight: 760)
        #endif
    }

    @ViewBuilder private var content: some View {
        if let stats = model.stats {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    ProfileHeader(account: model.account, memberSince: stats.memberSince)
                    if model.isEmpty {
                        Label(
                            "Your stats fill in as you watch. Mark a show you've finished to start.",
                            systemImage: "sparkles.tv"
                        )
                        .foregroundStyle(Color(.muted))
                        .panel()
                        ProfileFavorites(model: model.favorites, library: library)
                    } else {
                        sections(stats)
                        ProfileFavorites(model: model.favorites, library: library)
                        footer
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // Insights' motion rules: nothing counts up, no bar grows.
            .transaction { $0.animation = nil }
        } else if model.failed {
            ContentUnavailableView {
                Label("Couldn't load your profile", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Aaru could not reach the server.")
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func sections(_ stats: ProfileStats) -> some View {
        ProfileTimeHero(minutes: stats.minutesWatched, episodes: stats.episodesWatched)
        ProfileCountTiles(stats: stats, onShowKind: onShowKind)
        let kinds = ProfileTimeSplit.parts(stats.byKind)
        if !kinds.isEmpty {
            PanelSection(title: "Where the time went") { ProfileTimeSplit(parts: kinds) }
        }
        if !stats.topGenres.isEmpty {
            PanelSection(title: "Genres") { ProfileGenreBars(genres: stats.topGenres) }
        }
        if !stats.mostWatched.isEmpty {
            PanelSection(title: "Most watched") {
                ProfileMostWatched(titles: Array(stats.mostWatched.prefix(3)), library: library)
            }
        }
        if !stats.topNetworks.isEmpty {
            PanelSection(title: "Where you watch") { ProfileNetworkChips(networks: stats.topNetworks) }
        }
        if stats.ratings.mean != nil {
            PanelSection(title: "Ratings") { RatingsHistogram(ratings: stats.ratings) }
        }
    }

    private var footer: some View {
        let year = Calendar.current.component(.year, from: .now)
        return VStack(alignment: .leading, spacing: AaruSpace.large) {
            Divider()
            NavigationLink {
                InsightsView(api: api, library: library, model: InsightsModel(api: api, span: .all))
            } label: {
                Label("Insights", systemImage: "chart.bar.xaxis")
            }
            Button("Your \(String(year)) recap", systemImage: "play.circle") { recap = RecapPeriod(year: year) }
            Text("Includes episodes without a watch date, so these numbers can be higher than Insights.")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(.accent))
    }
}

// MARK: Header

/// The user's initials on the medallion tint. Aaru has no avatar uploads; with no name or handle
/// yet, a person symbol.
struct ProfileMedallion: View {
    let account: Components.Schemas.Me?
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let initials = ProfileModel.initials(account) {
                Text(initials)
                    .font(size > 40 ? .aaruDisplay(size: size * 0.4) : .system(size: size * 0.4, weight: .semibold))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
            }
        }
        .foregroundStyle(Color(.ink))
        .frame(width: size, height: size)
        .background(Color(.medallion).opacity(AaruAlpha.ghost), in: .circle)
        .overlay { Circle().strokeBorder(Color(.medallion).opacity(AaruAlpha.half), lineWidth: 1) }
    }
}

/// Home's way to the profile: the medallion with the user's initials. "Your profile" to VoiceOver.
struct ProfileButton: View {
    let api: Client?
    let action: () -> Void

    @State private var account: Components.Schemas.Me?

    var body: some View {
        Button(action: action) {
            ProfileMedallion(account: account, size: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your profile")
        .task {
            guard let api, case let .ok(response)? = try? await api.getMe() else { return }
            account = (try? response.body.json) ?? account
        }
    }
}

extension View {
    /// Home's profile: the medallion as a leading toolbar item, opening the profile as a large
    /// sheet. `onShowKind` runs after the sheet closes for a count tile.
    func profileEntry(
        api: Client?, library: LibraryModel, lists: ListsModel, onShowKind: @escaping (MediaKind) -> Void
    ) -> some View {
        modifier(ProfileEntry(api: api, library: library, lists: lists, onShowKind: onShowKind))
    }
}

private struct ProfileEntry: ViewModifier {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let onShowKind: (MediaKind) -> Void

    @State private var showsProfile = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .profile) {
                    ProfileButton(api: api) { showsProfile = true }
                }
            }
            .sheet(isPresented: $showsProfile) {
                ProfileView(api: api, library: library, lists: lists) { kind in
                    showsProfile = false
                    onShowKind(kind)
                }
                .presentationDetents([.large])
            }
    }
}

extension ToolbarItemPlacement {
    /// Leading on iPhone and iPad. The Mac's toolbar has no leading bar item: the navigation spot.
    static var profile: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .navigation
        #endif
    }
}

/// Medallion, name in the serif face, "@ana", "In Aaru since Oct 2026".
private struct ProfileHeader: View {
    let account: Components.Schemas.Me?
    let memberSince: Date?

    var body: some View {
        HStack(spacing: 16) {
            ProfileMedallion(account: account, size: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(account?.displayName ?? account?.handle.map { "@\($0)" } ?? "You")
                    .font(.aaruDisplay(.title, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .accessibilityAddTraits(.isHeader)
                if account?.displayName != nil, let handle = account?.handle {
                    Text("@\(handle)")
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
                if let memberSince {
                    Text(ProfileModel.sinceLine(memberSince))
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
            }
        }
    }
}

// MARK: Previews

#Preview("Profile") {
    let counts = { (finished: Int, watching: Int) in
        LibraryCounts(wishlist: 4, inProgress: watching, onHold: 0, finished: finished, dropped: 1)
    }
    let stats = ProfileStats(
        memberSince: .now.addingTimeInterval(-86400 * 12),
        episodesWatched: 4812,
        minutesWatched: 59460,
        pagesRead: 3200,
        shows: counts(38, 6),
        anime: counts(12, 2),
        movies: counts(140, 0),
        books: counts(22, 1),
        byKind: [
            .init(kind: .show, episodes: 3900, minutes: 37200, finished: 38),
            .init(kind: .anime, episodes: 912, minutes: 12600, finished: 12),
            .init(kind: .movie, episodes: 0, minutes: 9660, finished: 140),
        ],
        topGenres: [
            .init(name: "Drama", minutes: 21000, titles: 41),
            .init(name: "Sci-Fi & Fantasy", minutes: 12400, titles: 18),
            .init(name: "Comedy", minutes: 9100, titles: 27),
            .init(name: "Animation", minutes: 8800, titles: 15),
        ],
        topNetworks: [
            .init(name: "HBO", minutes: 9000, titles: 6),
            .init(name: "Netflix", minutes: 8000, titles: 11),
            .init(name: "Crunchyroll", minutes: 7000, titles: 9),
        ],
        mostWatched: [],
        ratings: .init(count: 64, mean: 7.6, distribution: [0, 1, 1, 2, 4, 8, 14, 18, 10, 6])
    )
    ProfileView(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: ProfileModel(
            preview: stats,
            account: .init(userId: "u", displayName: "Fernando Correia", handle: "fernando", providers: [.apple])
        )
    )
}

#Preview("New account") {
    let zero = LibraryCounts(wishlist: 0, inProgress: 0, onHold: 0, finished: 0, dropped: 0)
    ProfileView(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: ProfileModel(preview: ProfileStats(
            episodesWatched: 0, minutesWatched: 0, pagesRead: 0, shows: zero, anime: zero, movies: zero,
            books: zero, byKind: [], topGenres: [], topNetworks: [], mostWatched: [],
            ratings: .init(count: 0, distribution: Array(repeating: 0, count: 10))
        ))
    )
}
