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
    @State private var confirmsRemoval = false
    /// Nil in previews and outside the signed-in app.
    @Environment(GroupsModel.self) private var groups: GroupsModel?
    @State private var openEpisode: EpisodeKey?
    @State private var expandedSeasons: Set<Int> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    TitleHero(entry: entry, kind: kind, meta: meta, compact: compact)
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
            ToolbarItem(placement: .secondaryAction) { moreMenu }
        }
        // Outside the menu: a dialog attached inside one closes with it.
        .confirmationDialog(
            "Remove “\(entry.title.title)” from your library?",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from library", role: .destructive) {
                Task {
                    if await model.remove() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text(TitleRemoval.message)
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

    private func load() async {
        await model.load()
        expandedSeasons = Set(model.nextEpisode.map { [$0.season] } ?? [])
    }

    private var statusBinding: Binding<LibraryStatus> {
        Binding(get: { entry.status }, set: { status in
            Task {
                await model.update(.init(status: status)) { $0.status = status }
            }
        })
    }
}

// MARK: The room's sections

extension TitleDetailView {
    /// "Discuss in a group…" for anyone in a group (UX-083); "Remove from library…", confirmed
    /// and journaled, so History can undo it (UX-061).
    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            if groups?.groups.isEmpty == false {
                Button("Discuss in a group…", systemImage: "bubble.left.and.bubble.right") { discusses = true }
            }
            Button("Recommend to friends…", systemImage: "hand.thumbsup") { recommends = true }
            Button("Remove from library…", systemImage: "trash", role: .destructive) { confirmsRemoval = true }
        }
    }

    /// One item, one kind: "2022 · Show · 48 min · Returning series" (UX-046, UX-047).
    private var meta: String {
        let runtime = model.title?.runtimeMinutes.map { "\($0) min" }
        let status = model.title?.status.map(\.label)
        return [entry.title.year.map(String.init), kind.noun, runtime, status]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// The next step: the next episode to mark, for a show with one aired and unwatched; then
    /// the status, in this kind's words. Stacked at accessibility sizes.
    private var actions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if model.isShow, let next = model.nextEpisode {
                Button {
                    Task { await model.toggle(next) }
                } label: {
                    Label("Mark \(EpisodeCode.short(season: next.season, number: next.number)) watched", systemImage: "checkmark")
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

    @ViewBuilder private var yours: some View {
        TitleYourLayer(model: model, notes: $notes, page: $page)
        if model.isShow {
            TitleAbout(synopsis: model.title?.synopsis)
        }
    }

    @ViewBuilder private var titleLayer: some View {
        if !model.isShow {
            TitleAbout(synopsis: model.title?.synopsis)
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
            TitleSeasons(model: model, expanded: $expandedSeasons, onOpen: { openEpisode = $0 }, retry: load)
        }
    }
}
