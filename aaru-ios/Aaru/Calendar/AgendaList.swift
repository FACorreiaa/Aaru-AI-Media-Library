import SwiftUI

/// Stremio's sidebar: from the selected day on, a heading per date and a poster row per episode.
/// A row opens the episode sheet (CAL-003); its tick works on its own.
struct AgendaList: View {
    let model: MonthModel
    var onSearch: () -> Void

    var body: some View {
        let sections = model.agenda
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.entries, id: \.cellID) { entry in
                            CalendarEpisodeRow(entry: entry, feed: model.feed)
                        }
                    } header: {
                        AgendaHeader(day: section.day, isToday: model.isToday(section.day))
                    }
                }
                if sections.isEmpty, model.feed.hasLoaded {
                    empty
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.isEmptyMonth
                ? "Nothing from your shows airs this month."
                : "Nothing more from your shows this month.")
                .font(.callout)
                .foregroundStyle(Color(.muted))
            if model.isEmptyMonth {
                Button("Search", action: onSearch)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(16)
    }
}

/// "Mon 13 Oct", today in the accent. Pinned while its rows scroll.
private struct AgendaHeader: View {
    let day: Date
    let isToday: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            if isToday {
                Text("Today")
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color(.accent))
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.paper))
        .accessibilityAddTraits(.isHeader)
    }
}

extension CalendarEntry {
    /// "S2 · E5", the agenda's quieter code.
    var shortCode: String {
        "S\(season) · E\(number)"
    }

    /// The local time, or nil for a date-only air date.
    var timeText: String? {
        airTimeKnown ? airsAt.formatted(date: .omitted, time: .shortened) : nil
    }
}
