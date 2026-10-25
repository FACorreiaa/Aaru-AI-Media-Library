import AaruAPI
import SwiftUI

/// A title pushed from a search hit or a list member that is not in the library (LIB-006).
struct CatalogRoute: Hashable {
    let hit: CatalogHit
}

extension View {
    /// Registers the catalog page in a navigation stack: every stack that shows hits needs it.
    func catalogDestination(api: Client?, library: LibraryModel, lists: ListsModel) -> some View {
        navigationDestination(for: CatalogRoute.self) { route in
            TitlePreviewView(hit: route.hit, api: api, library: library, lists: lists)
        }
    }
}

/// LIB-006: the page for a title that is not in the library. The same facts as the Title room
/// (poster, kind, year, synopsis, seasons or tracklist) with Add and Add to list; nothing is
/// written until one is tapped. Once it is in the library, the Title room takes its place.
struct TitlePreviewView: View {
    let hit: CatalogHit
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var title: TitleDetail?
    /// The caller's item, when the server says the title is theirs already.
    @State private var itemID: String?
    @State private var loadFailed = false
    @State private var adding = false
    @State private var problem: String?
    @State private var showsLists = false

    private var kind: MediaKind {
        MediaKind(type: hit._type, isAnime: hit.isAnime)
    }

    var body: some View {
        if let entry = library.entry(matching: hit) {
            TitleDetailView(entry: entry, api: api, library: library, lists: lists)
        } else if let itemID {
            LibraryEntryDestination(id: itemID, api: api, library: library, lists: lists)
        } else if let title {
            page(title)
        } else if loadFailed {
            LoadFailedView(title: "This title didn't load", message: "Aaru could not reach the server.") {
                await load()
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await load() }
        }
    }

    private func page(_ title: TitleDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                    .frame(maxWidth: kind == .music ? 280 : 200)
                    .clipShape(RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.title)
                        .font(.aaruDisplay(.title, weight: .semibold))
                    if let original = title.originalTitle, original != title.title {
                        Text(original).foregroundStyle(Color(.muted))
                    }
                    Text(facts(title))
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
                actions
                if let synopsis = title.synopsis {
                    Text(synopsis)
                }
                if kind == .music {
                    AlbumTracklist(tracks: title.tracks, isLoading: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle(title.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: problem) { problem = nil } }
            .sheet(isPresented: $showsLists) {
                ListPickerSheet(
                    ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                    titleName: hit.title,
                    lists: lists
                )
            }
            .background(Color(.paper))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(LibraryStatus.addable) { status in
                    Button(status.label(for: kind)) { add(status) }
                }
            } label: {
                if adding {
                    ProgressView()
                } else {
                    Label(LibraryStatus.wishlist.label(for: kind), systemImage: "plus")
                }
            } primaryAction: {
                add(.wishlist)
            }
            .buttonStyle(.borderedProminent)
            .disabled(adding)
            .accessibilityHint("Touch and hold for another status.")
            Button("Add to list…", systemImage: "text.badge.plus") { showsLists = true }
                .buttonStyle(.bordered)
        }
    }

    /// "Show · 2016 · Returning · 4 seasons", or "Album · 1997 · Radiohead".
    private func facts(_ title: TitleDetail) -> String {
        let seasons = (title.seasons ?? []).filter { $0.number > 0 }
        let episodes = seasons.reduce(0) { $0 + $1.episodes.count }
        let parts: [String?] = [
            kind.label,
            title.year.map(String.init),
            title.byline,
            title.runtimeMinutes.map { "\($0) min" },
            title.status.map(\.label),
            seasons
                .isEmpty ? nil : "\(seasons.count) \(seasons.count == 1 ? "season" : "seasons") · \(episodes) episodes",
        ]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    private func load() async {
        guard let api else { return }
        loadFailed = false
        let ref = MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year)
        do {
            switch try await api.resolveTitle(body: .json(ref)) {
            case let .ok(response):
                let preview = try response.body.json
                itemID = preview.libraryItemId
                title = preview.title
            case .default:
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }

    /// Adds with a status, as Discover does; the Title room replaces this page once the
    /// library has it.
    private func add(_ status: LibraryStatus) {
        Task {
            adding = true
            defer { adding = false }
            problem = await library.add(hit, status: status, api: api)
        }
    }
}

extension CatalogHit {
    /// A list member as a hit, for its catalog page.
    init(_ title: Components.Schemas.TitleSummary) {
        self.init(
            _type: title._type, title: title.title, originalTitle: title.originalTitle, year: title.year,
            posterUrl: title.posterUrl, byline: title.byline, isAnime: title.isAnime, ids: title.ids
        )
    }
}
