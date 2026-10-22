import AaruAPI
import SwiftUI

/// MUS-008: Listens, the log of what the user played, and its top lists (UX-049: the page is
/// "Listens"; "Listening" stays for albums in progress). Recent and Top sit side by side when there is
/// room and behind a switch when there is not. Reached from Library's menu, Insights and
/// Settings → Connections → Music.
struct MusicView: View {
    let api: Client?
    /// Album rows open their title page only when this is passed and the album is in it.
    var library: LibraryModel?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var pane = Pane.recent

    enum Pane: String, CaseIterable {
        case recent = "Recent"
        case top = "Top"
    }

    var body: some View {
        ScrollView {
            if sizeClass == .compact {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Show", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch pane {
                    case .recent: RecentListens(api: api, library: library)
                    case .top: TopListens(api: api, library: library)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                HStack(alignment: .top, spacing: 40) {
                    pane("Recent") { RecentListens(api: api, library: library) }
                    pane("Top") { TopListens(api: api, library: library) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Listens")
        .background(Color(.paper))
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.aaruDisplay(.title2, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Listens newest first under day headings, fifty at a time.
private struct RecentListens: View {
    let library: LibraryModel?

    @State private var model: RecentListensModel
    @Environment(AppRouter.self) private var router

    init(api: Client?, library: LibraryModel?) {
        self.library = library
        _model = State(initialValue: RecentListensModel(api: api))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.loaded, model.listens.isEmpty, model.problem == nil {
                ContentUnavailableView {
                    Label("No listens yet", systemImage: "music.note")
                } description: {
                    Text("Connect a scrobbler, and what you play shows up here.")
                } actions: {
                    // The words used to name the place; now the button goes there (UX-077).
                    Button("Connect a scrobbler") { router.openSettings(.connections) }
                        .buttonStyle(.borderedProminent)
                }
            }
            ForEach(Listening.byDay(model.listens, now: .now), id: \.heading) { day in
                Text(day.heading.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color(.muted))
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(day.listens, id: \.id) { listen in
                    ListenRow(listen: listen, library: library)
                    if listen.id != day.listens.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            if let problem = model.problem {
                Text(problem).font(.footnote).foregroundStyle(Color(.danger)).padding(.top, 12)
            }
            if model.loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if let next = model.next {
                Button("Load more") { Task { await model.load(before: next) } }
                    .buttonStyle(.bordered)
                    .padding(.top, 16)
            }
        }
        .task { await model.load(before: nil) }
    }
}

private struct ListenRow: View {
    let listen: Listen
    let library: LibraryModel?

    var body: some View {
        AlbumLink(titleID: listen.albumRef?.titleId, library: library) {
            HStack(spacing: 12) {
                ListenCover(url: listen.coverUrl)
                VStack(alignment: .leading, spacing: 2) {
                    Text(listen.track).font(.body.weight(.medium)).lineLimit(1)
                    Text(Listening.subtitle(listen)).font(.footnote).foregroundStyle(Color(.muted)).lineLimit(1)
                }
                Spacer()
                Text(listen.listenedAt, format: .dateTime.hour().minute())
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

/// The top twenty for 7 days, 30 days, a year or all time.
private struct TopListens: View {
    let library: LibraryModel?

    @State private var model: TopListensModel

    init(api: Client?, library: LibraryModel?) {
        self.library = library
        _model = State(initialValue: TopListensModel(api: api))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Year", as on Insights (UX-053).
            Picker("Period", selection: $model.span) {
                ForEach(TopListensModel.spans) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Rank", selection: $model.rank) {
                ForEach(TopListenBy.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if let rows = model.rows {
                if rows.isEmpty {
                    Text("Nothing played then.").font(.footnote).foregroundStyle(Color(.muted))
                } else {
                    TopListenList(rows: rows, rank: model.rank, library: library)
                }
            } else if let problem = model.problem {
                Text(problem).font(.footnote).foregroundStyle(Color(.danger))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: model.key) { await model.load() }
    }
}
