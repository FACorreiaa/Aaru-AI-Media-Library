import SwiftUI

/// Stremio's sidebar: from the selected day on, a heading per date and a poster row per episode.
/// Grouped by channel (CAL-005), the whole grid instead, a heading per channel. A row opens the
/// episode sheet (CAL-003); its tick works on its own.
struct AgendaList: View {
    let model: MonthModel
    var onSearch: () -> Void
    var onClearFilters: (() -> Void)?

    var body: some View {
        let byChannel = model.isGroupedByChannel
        let sections = byChannel ? [] : model.agenda
        let channels = byChannel ? model.channels : []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if byChannel {
                    AiringChannelSections(groups: channels, feed: model.feed)
                } else {
                    ForEach(sections, id: \.day) { section in
                        Section {
                            ForEach(section.entries, id: \.cellID) { entry in
                                CalendarEpisodeRow(entry: entry, feed: model.feed)
                            }
                        } header: {
                            AgendaHeader(day: section.day, isToday: model.isToday(section.day))
                        }
                    }
                }
                if sections.isEmpty, channels.isEmpty, model.isLoaded {
                    empty
                } else if !model.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(24)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(Color(.muted))
            if let onClearFilters {
                Button("Clear filters", action: onClearFilters)
                    .buttonStyle(.bordered)
            } else if model.isEmptyMonth {
                Button("Search", action: onSearch)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}

extension AgendaList {
    private var emptyText: String {
        switch (onClearFilters != nil, model.isEmptyMonth) {
        case (true, true): "No episodes this month match these filters."
        case (true, false): "No more episodes this month match these filters."
        case (false, true): "Nothing from your shows airs this month."
        case (false, false): "Nothing more from your shows this month."
        }
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
        .padding(.horizontal, AaruSpace.large)
        .padding(.top, AaruSpace.large)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.paper))
        .accessibilityAddTraits(.isHeader)
    }
}

extension CalendarEntry {
    /// "S2 · E5", the agenda's quieter code.
    var shortCode: String {
        EpisodeCode.short(season: season, number: number)
    }

    /// The local time, or nil for a date-only air date.
    var timeText: String? {
        airTimeKnown ? airsAt.formatted(date: .omitted, time: .shortened) : nil
    }
}
