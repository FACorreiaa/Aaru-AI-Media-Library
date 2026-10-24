import AaruAPI
import SwiftUI

/// A list member that is in the library, pushed as its Title room.
struct ListMemberRoute: Hashable {
    let libraryItemID: String
}

/// One list: its titles in order, swipe to remove, drag to reorder, "Add titles" to search into
/// it. Rows carry status, progress and the next airing (LST-003). A member not in the library
/// gets an Add control (UX-072). LIB-005: a filter over its titles, and 20 at a time with more
/// on scroll. Dragging waits for an empty filter, so a move lands where it looks.
struct ListDetailView: View {
    let listID: String
    let lists: ListsModel
    let library: LibraryModel
    let api: Client?

    @State private var detail: ListDetail?
    @State private var loading = false
    @State private var loadFailed = false
    @State private var showsSearch = false
    /// A failed add from a row.
    @State private var problem: String?
    @State private var query = ""
    @State private var shown = Paging.pageSize

    private var matching: [ListItem] {
        (detail?.items ?? []).filter { Paging.matches(query, $0.title.title, $0.title.byline) }
    }

    private var visible: [ListItem] {
        Array(matching.prefix(shown))
    }

    var body: some View {
        List {
            ForEach(visible, id: \.title.id) { item in
                row(for: item)
                    .listRowBackground(Color.clear)
                    .moveDisabled(!query.isEmpty)
                    .contextMenu {
                        Button("Remove from list", systemImage: "minus.circle", role: .destructive) {
                            Task { await remove([item.title.id]) }
                        }
                    }
            }
            .onDelete { offsets in
                let ids = offsets.map { visible[$0].title.id }
                Task { await remove(ids) }
            }
            .onMove(perform: move)
            LoadMore(shown: $shown, total: matching.count)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .overlay { state }
        .safeAreaInset(edge: .bottom) {
            ProblemBanner(message: problem ?? (detail == nil ? nil : lists.problem)) {
                problem = nil
                lists.problem = nil
            }
        }
        .navigationTitle(detail?.name ?? "List")
        .searchable(text: $query, prompt: "Filter this list")
        .onChange(of: query) { shown = Paging.pageSize }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add titles", systemImage: "plus") { showsSearch = true }
                    .disabled(detail == nil)
            }
            #if os(iOS)
                ToolbarItem(placement: .primaryAction) { EditButton() }
            #endif
        }
        .navigationDestination(for: ListMemberRoute.self) { route in
            LibraryEntryDestination(id: route.libraryItemID, api: api, library: library, lists: lists)
        }
        .sheet(isPresented: $showsSearch) {
            if let list = Binding($detail) {
                SearchView(api: api, library: library, lists: lists, intoList: list)
            }
        }
        .task(id: listID) { await load() }
        .refreshable { await load() }
    }

    /// Loading, a first load that failed (with Try again, UX-063), or an empty list.
    @ViewBuilder private var state: some View {
        if let detail {
            if detail.items.isEmpty {
                OwlUnavailableView(title: "Nothing on this list") {
                    Button("Add titles") { showsSearch = true }.buttonStyle(.borderedProminent)
                }
            } else if matching.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        } else if loadFailed, !loading {
            LoadFailedView(
                title: "This list didn't load",
                message: lists.problem ?? "Aaru could not reach the server.",
                retry: load
            )
        } else {
            ProgressView()
        }
    }

    @ViewBuilder private func row(for item: ListItem) -> some View {
        // A title in the library opens its Title room; one only on the list can be added. The
        // local library wins over the row's entry: it is the copy Title detail edits.
        if let entry = library.entry(forTitle: item.title.id) ?? item.entry {
            NavigationLink(value: ListMemberRoute(libraryItemID: entry.id)) { ListItemRow(item: item) }
        } else {
            HStack(spacing: 8) {
                ListItemRow(item: item)
                Spacer(minLength: 0)
                AddMemberButton(item: item, library: library, api: api) { problem = $0 }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let loaded = await lists.detail(listID) {
            detail = loaded
            loadFailed = false
        } else {
            loadFailed = detail == nil
        }
    }

    private func remove(_ ids: [String]) async {
        for id in ids {
            if let updated = await lists.remove(titleID: id, from: listID) {
                detail = updated
            }
        }
    }

    /// Drag to reorder (Edit on iPhone, a plain drag on iPad and the Mac). Optimistic; the old
    /// order comes back if the server says no.
    private func move(_ source: IndexSet, _ destination: Int) {
        guard var items = detail?.items else { return }
        let before = detail
        items.move(fromOffsets: source, toOffset: destination)
        detail?.items = items
        Task {
            if let saved = await lists.reorder(listID, titleIDs: items.map(\.title.id)) {
                detail = saved
            } else {
                detail = before
            }
        }
    }
}

/// "Add" on a list member not in the library: a tap plans it ("Plan to watch", "Plan to read"…);
/// touch and hold (or the Mac's menu arrow) picks another status.
private struct AddMemberButton: View {
    let item: ListItem
    let library: LibraryModel
    let api: Client?
    let onProblem: (String) -> Void

    @State private var adding = false

    private var kind: MediaKind {
        MediaKind(type: item.title._type, isAnime: item.title.isAnime)
    }

    var body: some View {
        Menu {
            ForEach([LibraryStatus.wishlist, .inProgress, .finished]) { status in
                Button(status.label(for: kind)) { add(status) }
            }
        } label: {
            Group {
                if adding {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundStyle(Color(.accent))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        } primaryAction: {
            add(.wishlist)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
        .disabled(adding)
        .accessibilityLabel("Add \(item.title.title) to your library")
        .accessibilityHint("Adds it as \(LibraryStatus.wishlist.label(for: kind)). Touch and hold for another status.")
    }

    private func add(_ status: LibraryStatus) {
        Task {
            adding = true
            defer { adding = false }
            let ref = MediaRef(titleId: item.title.id, _type: item.title._type)
            if let problem = await library.add(ref, named: item.title.title, status: status, api: api) {
                onProblem(problem)
            }
        }
    }
}
