import AaruAPI
import SwiftUI

/// Insights (GAM-006c/d): the user's own numbers for the last 7 or 30 days, a month, a year or all
/// time, with a way into the Recap story for the same month or year. Reached from Home's week
/// strip and Library's menu.
struct InsightsView: View {
    let api: Client?
    /// Lets Music's album rows open their title page; only stacks that route library item ids
    /// pass it.
    let library: LibraryModel?

    @State private var model: InsightsModel
    @State private var recap: RecapPeriod?

    init(api: Client?, library: LibraryModel? = nil, model: InsightsModel? = nil) {
        self.api = api
        self.library = library
        _model = State(initialValue: model ?? InsightsModel(api: api))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Period", selection: $model.span) {
                    ForEach(InsightsSpan.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                PeriodStepper(model: model)
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Insights")
        .task(id: model.period) { await model.load() }
        .recapStory($recap, api: api)
        .safeAreaInset(edge: .bottom) {
            ProblemBanner(message: model.problem) { model.problem = nil }
        }
        .background(Color(.paper))
    }

    @ViewBuilder private var content: some View {
        if let stats = model.stats {
            if stats.totals.isZero, stats.ratings.mean == nil {
                ContentUnavailableView(
                    model.span.isRolling
                        ? "Nothing tracked in the \(model.period.label.lowercased())"
                        : "Nothing tracked in \(model.period.label)",
                    systemImage: "chart.bar",
                    description: Text("Tick episodes and finish titles, and they add up here.")
                )
            } else {
                if let period = model.period.recap {
                    Button("Play as a story", systemImage: "play.circle") { recap = period }
                        .buttonStyle(.bordered)
                }
                StatsPanel(stats: stats)
            }
            // MUS-008: listening is not library activity, so it shows even when nothing was tracked.
            if let music = stats.music {
                MusicInsights(music: music, period: model.period, api: api, library: library)
                    .padding(.top, 8)
            }
        } else if model.problem == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

/// "‹ October 2026 ›". All time and rolling windows have nothing to step through.
private struct PeriodStepper: View {
    let model: InsightsModel

    var body: some View {
        HStack {
            if model.canStep {
                Button("Previous", systemImage: "chevron.left") { model.step(-1) }
                    .labelStyle(.iconOnly)
            }
            Spacer()
            Text(model.period.label)
                .font(.aaruDisplay(.title2, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if model.canStep {
                Button("Next", systemImage: "chevron.right") { model.step(1) }
                    .labelStyle(.iconOnly)
                    .disabled(!model.canStepForward)
            }
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }
}
