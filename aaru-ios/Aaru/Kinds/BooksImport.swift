import AaruAPI
import SwiftUI

/// The top of Books (BOOK-002): this year's reading, captures waiting, and, while the shelf is
/// empty, the import box itself. Once there are books the box moves behind the toolbar's `+`.
struct BooksTop: View {
    let api: Client?
    let imports: ImportsModel?
    let library: LibraryModel
    let lists: ListsModel
    /// A capture was taken: the page opens its review.
    let onStarted: (ImportJob) -> Void

    private var waiting: [ImportJob] {
        (imports?.jobs ?? []).filter(\.isWaitingCapture).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.section) {
            BooksYearStrip(api: api, library: library)
                .padding(.horizontal, 20)
            if let imports {
                if !waiting.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(waiting, id: \.id) { job in
                            NavigationLink {
                                ImportDetailView(id: job.id, imports: imports, library: library, lists: lists, api: api)
                            } label: {
                                CaptureCard(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if library.isBookShelfEmpty {
                    BooksImportBox(imports: imports, onStarted: onStarted)
                        .padding(.horizontal, 20)
                }
            }
        }
        .task { await imports?.load() }
    }
}

/// The import box: the composer for books only, and the way to a Goodreads export.
struct BooksImportBox: View {
    let imports: ImportsModel
    let onStarted: (ImportJob) -> Void
    /// The Goodreads shortcut. Nil opens Settings from here; the sheet closes itself first.
    var onGoodreads: (() -> Void)?

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            CaptureComposer(imports: imports, kind: .book, onStarted: onStarted)
            Button("Have a Goodreads export? Import it", systemImage: "square.and.arrow.down") {
                if let onGoodreads {
                    onGoodreads()
                } else {
                    router.openSettings(.imports)
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
    }
}

/// Read this year, reading now and planned, from the synced shelf and the year's stats. It opens
/// Insights, and is hidden while all three are zero.
struct BooksYearStrip: View {
    let api: Client?
    let library: LibraryModel

    @State private var read = 0

    private var reading: Int {
        library.rows(kind: .book, status: .inProgress).count
    }

    private var planned: Int {
        library.rows(kind: .book, status: .wishlist).count
    }

    var body: some View {
        Group {
            if read + reading + planned > 0 {
                NavigationLink {
                    InsightsView(api: api, library: library)
                } label: {
                    HStack(alignment: .top) {
                        figure(read, "Read this year")
                        figure(reading, LibraryStatus.inProgress.label(for: .book))
                        figure(planned, LibraryStatus.wishlist.label(for: .book))
                    }
                    .padding(AaruSpace.large)
                    .frame(maxWidth: .infinity)
                    .card()
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: library.revision) { await load() }
    }

    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.aaruDisplay(.title2, weight: .medium))
                .foregroundStyle(Color(.ink))
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let api else { return }
        let year = Calendar.current.component(.year, from: .now)
        let query = Operations.GetStats.Input.Query(year: year, tz: TimeZone.current.identifier)
        guard case let .ok(response) = try? await api.getStats(query: query),
              let stats = try? response.body.json
        else { return }
        read = stats.totals.booksFinished
    }
}

/// The toolbar's `+` once the shelf has books, its sheet, and the review a capture opens. A sheet
/// closes before the review or Settings opens: two at once would drop the second.
struct BooksImportPresenter: ViewModifier {
    /// Nil on Manga and Music, which have no import box.
    let imports: ImportsModel?
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    @Binding var opened: ImportJob?

    @State private var showsSheet = false
    @State private var startedInSheet: ImportJob?
    @State private var goodreadsNext = false
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .toolbar {
                if imports != nil, !library.isBookShelfEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Import books", systemImage: "plus") { showsSheet = true }
                    }
                }
            }
            .navigationDestination(item: $opened) { job in
                if let imports {
                    ImportDetailView(id: job.id, imports: imports, library: library, lists: lists, api: api)
                }
            }
            .sheet(isPresented: $showsSheet, onDismiss: afterSheet) {
                if let imports {
                    sheet(imports)
                }
            }
    }

    private func sheet(_ imports: ImportsModel) -> some View {
        NavigationStack {
            ScrollView {
                BooksImportBox(imports: imports) { job in
                    startedInSheet = job
                    showsSheet = false
                } onGoodreads: {
                    goodreadsNext = true
                    showsSheet = false
                }
                .padding(20)
            }
            .background(Color(.paper))
            .navigationTitle("Import books")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showsSheet = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .closesOnSheetsRequest()
    }

    private func afterSheet() {
        if let job = startedInSheet {
            startedInSheet = nil
            opened = job
        }
        if goodreadsNext {
            goodreadsNext = false
            router.openSettings(.imports)
        }
    }
}

extension LibraryModel {
    /// The shelf has synced and holds no book; before the first sync it is not known to be empty.
    var isBookShelfEmpty: Bool {
        hasSynced && rows(kind: .book, status: nil).isEmpty
    }
}
