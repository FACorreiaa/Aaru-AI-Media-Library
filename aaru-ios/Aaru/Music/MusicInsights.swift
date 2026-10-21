import AaruAPI
import SwiftUI

/// MUS-008 · Insights' "Music": the period's listens and time against the window before, then
/// its top five artists, tracks or albums, and a way into the whole log.
struct MusicInsights: View {
    let music: Components.Schemas.StatsMusic
    let period: InsightsPeriod
    let api: Client?
    let library: LibraryModel?

    @State private var rank = TopListenBy.artist
    @State private var rows: [TopListenRow]?
    @State private var failed = false

    var body: some View {
        PanelSection(title: "Music") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                StatTile(
                    value: music.listens.formatted(),
                    caption: music.listens == 1 ? "listen" : "listens",
                    delta: music.priorListens.flatMap { StatTile.Delta.count(music.listens, $0) }
                )
                StatTile(
                    value: hoursValue(minutes: music.minutes), caption: "hours",
                    delta: music.priorMinutes.flatMap { StatTile.Delta.hours(music.minutes, $0) }
                )
            }
            if music.listens > 0 {
                Picker("Rank", selection: $rank) {
                    ForEach(TopListenBy.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                top.frame(minHeight: 64, alignment: .top)
            }
            NavigationLink {
                MusicView(api: api, library: library)
            } label: {
                HStack(spacing: 4) {
                    Text("All listening")
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
            }
            .font(.body.weight(.semibold))
        }
        .task(id: "\(period.hashValue)-\(rank.rawValue)") { await load() }
    }

    @ViewBuilder private var top: some View {
        if let rows {
            TopListenList(rows: rows, rank: rank, library: library)
        } else if failed {
            Text("The top list could not be loaded.").font(.footnote).foregroundStyle(Color(.muted))
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        guard let api, music.listens > 0 else { return }
        rows = nil
        failed = false
        do {
            rows = try await Listening.top(
                api, by: rank, span: period.span, year: period.year, month: period.month, limit: 5
            )
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}
