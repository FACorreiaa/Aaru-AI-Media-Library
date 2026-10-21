import AaruAPI
import SwiftUI

/// MUS-008: the listening log and its top lists. Recent and Top sit side by side when there is
/// room and behind a switch when there is not. Reached from Library's menu, Insights and
/// Settings → Connected apps → Music.
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
        .navigationTitle("Music")
        .background(Color(.paper))
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Listens newest first under day headings, fifty at a time.
private struct RecentListens: View {
    let api: Client?
    let library: LibraryModel?

    @State private var listens: [Listen] = []
    @State private var next: Date?
    @State private var loading = false
    @State private var loaded = false
    @State private var problem: String?

    private static let page = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loaded, listens.isEmpty, problem == nil {
                ContentUnavailableView(
                    "No listens yet",
                    systemImage: "music.note",
                    description: Text(
                        "Connect a scrobbler in Settings → Connected apps, and what you play shows up here."
                    )
                )
            }
            ForEach(Listening.byDay(listens, now: .now), id: \.heading) { day in
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
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red).padding(.top, 12)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if let next {
                Button("Load more") { Task { await load(before: next) } }
                    .buttonStyle(.bordered)
                    .padding(.top, 16)
            }
        }
        .task { await load(before: nil) }
    }

    private func load(before: Date?) async {
        guard let api, !loading, before != nil || !loaded else { return }
        loading = true
        defer {
            loading = false
            loaded = true
        }
        do {
            switch try await api.listListens(query: .init(before: before, limit: Self.page)) {
            case let .ok(response):
                let page = try response.body.json
                listens += page.items
                next = page.next
                problem = nil
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your listens could not be loaded."
            }
        } catch is CancellationError {
            return
        } catch {
            problem = "Your listens could not be loaded. Aaru could not reach the server."
        }
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

/// The top twenty for 7 days, 30 days, this year or all time.
private struct TopListens: View {
    let api: Client?
    let library: LibraryModel?

    @State private var span = InsightsSpan.last30
    @State private var rank = TopListenBy.artist
    @State private var rows: [TopListenRow]?
    @State private var problem: String?

    private static let spans: [InsightsSpan] = [.last7, .last30, .year, .all]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $span) {
                ForEach(Self.spans) { Text($0 == .year ? "This year" : $0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Rank", selection: $rank) {
                ForEach(TopListenBy.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if let rows {
                if rows.isEmpty {
                    Text("Nothing played then.").font(.footnote).foregroundStyle(Color(.muted))
                } else {
                    TopListenList(rows: rows, rank: rank, library: library)
                }
            } else if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: "\(span.rawValue)-\(rank.rawValue)") { await load() }
    }

    private func load() async {
        guard let api else { return }
        rows = nil
        problem = nil
        let year = Calendar.current.component(.year, from: .now)
        do {
            rows = try await Listening.top(api, by: rank, span: span, year: year, limit: 20)
        } catch is CancellationError {
            return
        } catch {
            problem = "The top list could not be loaded."
        }
    }
}
