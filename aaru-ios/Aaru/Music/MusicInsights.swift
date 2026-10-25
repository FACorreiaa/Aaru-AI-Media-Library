import AaruAPI
import SwiftUI

/// MUS-008 · Insights' "Music": the period's listens and time against the window before, then
/// its top five artists, tracks or albums, and a way into the whole log on the Music page.
struct MusicInsights: View {
    let music: Components.Schemas.StatsMusic
    let period: InsightsPeriod
    let api: Client?
    let library: LibraryModel?

    @State private var model: TopListensModel
    @Environment(AppRouter.self) private var router

    init(music: Components.Schemas.StatsMusic, period: InsightsPeriod, api: Client?, library: LibraryModel?) {
        self.music = music
        self.period = period
        self.api = api
        self.library = library
        _model = State(initialValue: TopListensModel(api: api, limit: 5))
    }

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
                Picker("Rank", selection: $model.rank) {
                    ForEach(TopListenBy.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                top.frame(minHeight: 64, alignment: .top)
            }
            // The Music page's Listens view (NAV-002).
            Button {
                router.showListens()
            } label: {
                // The log's one name (UX-049).
                HStack(spacing: 4) {
                    Text("All listens")
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .task(id: "\(period.hashValue)-\(model.rank.rawValue)") {
            guard music.listens > 0 else { return }
            await model.load(span: period.span, year: period.year, month: period.month)
        }
    }

    @ViewBuilder private var top: some View {
        if let rows = model.rows {
            TopListenList(rows: rows, rank: model.rank, library: library)
        } else if model.problem != nil {
            Text("The top list could not be loaded.").font(.footnote).foregroundStyle(Color(.muted))
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}
