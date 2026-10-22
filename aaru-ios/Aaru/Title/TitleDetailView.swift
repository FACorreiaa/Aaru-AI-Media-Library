import AaruAPI
import SwiftUI

/// APP-005: the Title room (DESIGN.md §4, "Mindspace"). A hero of the title's backdrop with its
/// poster and name, then the next step: for shows, the next episode to mark; for every kind, the
/// status. Then the user's own layer (rating, owned, page, notes) and the title's (About, the
/// tracklist, the season map and seasons with episode ticks). On wide screens the user's layer
/// is a side column. Only the season holding the next episode starts expanded. An album
/// (MUS-001) leads with its square cover.
struct TitleDetailView: View {
    @State private var model: TitleDetailModel
    @State private var notes = ""
    @State private var page = ""
    @State private var showsListPicker = false
    @State private var discusses = false
    @State private var recommends = false
    /// Nil in previews and outside the signed-in app.
    @Environment(GroupsModel.self) private var groups: GroupsModel?
    @State private var openEpisode: EpisodeKey?
    @State private var expandedSeasons: Set<Int> = []
    private let lists: ListsModel

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var compact: Bool {
            sizeClass == .compact
        }
    #else
        private let compact = false
    #endif

    /// `title` is for previews: the detail already loaded.
    init(entry: LibraryEntry, api: Client?, library: LibraryModel, lists: ListsModel, title: TitleDetail? = nil) {
        _model = State(initialValue: TitleDetailModel(entry: entry, api: api, library: library, title: title))
        self.lists = lists
    }

    private var entry: LibraryEntry {
        model.entry
    }

    private var kind: MediaKind {
        MediaKind(type: entry.title._type, isAnime: entry.title.isAnime)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if kind == .music {
                    AlbumHeader(
                        title: entry.title.title,
                        artist: model.title?.byline ?? entry.title.byline,
                        year: entry.title.year,
                        genres: model.title?.genres ?? [],
                        coverURL: entry.title.posterURL
                    )
                } else {
                    hero
                }
                actions
                if compact {
                    yours
                    titleLayer
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 24) { titleLayer }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 24) { yours }
                            .frame(width: 320)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // The rollback message sits where the tap was: at the bottom, not above a long season list.
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: model.problem) { model.problem = nil } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add to list", systemImage: "text.badge.plus") { showsListPicker = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Recommend to friends…", systemImage: "hand.thumbsup") { recommends = true }
            }
            if groups?.managedGroups.isEmpty == false {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Discuss in a group…", systemImage: "bubble.left.and.bubble.right") { discusses = true }
                }
            }
        }
        .sheet(isPresented: $recommends) {
            RecommendSheet(
                model: SocialModel(api: model.api),
                title: (MediaRef(titleId: entry.title.id, _type: entry.title._type), entry.title.title)
            )
        }
        .sheet(isPresented: $discusses) {
            if let groups {
                DiscussInGroupSheet(groups: groups, title: entry.title)
            }
        }
        .sheet(isPresented: $showsListPicker) {
            ListPickerSheet(
                ref: .init(titleId: entry.title.id, _type: entry.title._type),
                titleName: entry.title.title,
                lists: lists
            )
        }
        .sheet(item: $openEpisode) { key in
            EpisodeSheet(key: key, model: model)
        }
        .background { FieldBackground(seed: entry.title.id) }
        .navigationTitle(entry.title.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                notes = entry.notes ?? ""
                page = entry.bookProgress?.page.map(String.init) ?? ""
                await load()
            }
    }

    private func expansion(of season: Int) -> Binding<Bool> {
        Binding(get: { expandedSeasons.contains(season) }, set: { isExpanded in
            if isExpanded {
                expandedSeasons.insert(season)
            } else {
                expandedSeasons.remove(season)
            }
        })
    }

    private func load() async {
        await model.load()
        expandedSeasons = Set(model.nextEpisode.map { [$0.season] } ?? [])
    }

    // MARK: Writes

    private var statusBinding: Binding<LibraryStatus> {
        Binding(get: { entry.status }, set: { status in
            Task {
                await model.update(.init(status: status)) { $0.status = status }
            }
        })
    }

    private var ownedBinding: Binding<Bool> {
        Binding(get: { entry.isOwned }, set: { owned in
            Task {
                await model.update(.init(isOwned: owned)) { $0.isOwned = owned }
            }
        })
    }

    private func setRating(_ rating: Double?) async {
        if let rating {
            await model.update(.init(rating: rating)) { $0.rating = rating }
        } else {
            await model.update(.init(clear: [.rating])) { $0.rating = nil }
        }
    }

    private func saveNotes() async {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            await model.update(.init(clear: [.notes])) { $0.notes = nil }
        } else {
            await model.update(.init(notes: text)) { $0.notes = text }
        }
        notes = entry.notes ?? ""
    }

    private func savePage() async {
        guard let number = Int(page.filter(\.isNumber)) else { return }
        await model.update(.init(bookPage: number)) { $0.bookProgress = .init(page: number) }
        page = entry.bookProgress?.page.map(String.init) ?? page
    }
}

// MARK: The room's sections

extension TitleDetailView {
    // MARK: Hero

    /// The backdrop under a veil of Paper, the poster standing over its lower edge, the name.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroBackdrop(url: entry.title.backdropUrl.flatMap(URL.init(string:)), seed: entry.title.id)
                .frame(height: compact ? 200 : 300)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
            HStack(alignment: .top, spacing: 16) {
                PosterView(url: entry.title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                    .frame(width: compact ? 96 : 140)
                    .edgeLit(cornerRadius: 10)
                    .shadow(color: Color(.ink).opacity(0.18), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title.title)
                        .font(.aaruDisplay(.title, weight: .semibold))
                        .foregroundStyle(Color(.ink))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(meta)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color(.muted))
                    if let progress = entry.progress, progress.airedCount > 0 {
                        ProgressView(value: Double(progress.watchedCount), total: Double(progress.airedCount)) {
                            Text("\(progress.watchedCount) of \(progress.airedCount) episodes")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Color(.muted))
                        }
                        .tint(Color(.accent))
                    }
                }
                .padding(.top, compact ? 56 : 72)
            }
            .padding(.horizontal, compact ? 12 : 24)
            .padding(.top, compact ? -48 : -64)
        }
    }

    private var meta: String {
        let runtime = model.title?.runtimeMinutes.map { "\($0) min" }
        let status = model.title?.status.map { $0.rawValue.capitalized }
        return [entry.title.year.map(String.init), kind.label, runtime, status]
            .compactMap(\.self).joined(separator: " · ")
    }

    // MARK: Actions

    /// The next step: the next episode to mark, for a show with one aired and unwatched; then
    /// the status, in this kind's words.
    private var actions: some View {
        HStack(spacing: 12) {
            if model.isShow, let next = model.nextEpisode {
                Button {
                    Task { await model.toggle(next) }
                } label: {
                    Label("Mark S\(next.season) · E\(next.number) watched", systemImage: "checkmark")
                        .monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.pending.contains(next))
            }
            Picker("Status", selection: statusBinding) {
                ForEach(LibraryStatus.allCases) { Text($0.label(for: kind)).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
        .controlSize(.large)
    }

    // MARK: The user's layer

    @ViewBuilder private var yours: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Rating") {
                RatingStars(rating: entry.rating) { rating in
                    Task { await setRating(rating) }
                }
            }
            Divider()
            Toggle("Owned", isOn: ownedBinding)
                .tint(Color(.accent))
            if entry.title._type == .book {
                Divider()
                LabeledContent("Page") {
                    TextField("Page", text: $page)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .onSubmit { Task { await savePage() } }
                }
            }
        }
        .panel()

        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").eyebrow()
                .accessibilityAddTraits(.isHeader)
            TextField("Anything worth remembering", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
            if notes != (entry.notes ?? "") {
                Button("Save note") { Task { await saveNotes() } }
                    .buttonStyle(.bordered)
            }
        }
        .panel()

        if model.isShow {
            about
        }
    }

    // MARK: The title's layer

    @ViewBuilder private var titleLayer: some View {
        if !model.isShow {
            about
        }
        if kind == .music {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tracklist").eyebrow()
                    .accessibilityAddTraits(.isHeader)
                AlbumTracklist(tracks: model.title?.tracks, isLoading: model.title == nil && !model.loadFailed)
            }
            .panel()
        }
        if model.isShow {
            seasons
        }
    }

    @ViewBuilder private var about: some View {
        if let synopsis = model.title?.synopsis, !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").eyebrow()
                    .accessibilityAddTraits(.isHeader)
                Text(synopsis)
                    .font(.callout)
                    .foregroundStyle(Color(.ink).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .panel()
        }
    }

    // MARK: Seasons

    @ViewBuilder private var seasons: some View {
        if model.title != nil {
            if !model.orderedSeasons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Episodes").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    SeasonMap(model: model) { openEpisode = $0 }
                        .panel()
                    ForEach(model.orderedSeasons, id: \.number) { season in
                        SeasonSection(season: season, model: model, isExpanded: expansion(of: season.number)) {
                            openEpisode = $0
                        }
                    }
                }
            }
        } else if model.loadFailed {
            ContentUnavailableView {
                Label("Episodes did not load", systemImage: "exclamationmark.arrow.circlepath")
            } description: {
                Text("Aaru could not reach the server.")
            } actions: {
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
            .panel()
        } else {
            ProgressView().frame(maxWidth: .infinity).panel()
        }
    }
}
