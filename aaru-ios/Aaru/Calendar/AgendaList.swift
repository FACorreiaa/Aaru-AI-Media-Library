import SwiftUI

/// Stremio's sidebar: from the selected day on, a heading per date and a row per episode. The
/// chosen row opens up with the episode, its synopsis, a watched toggle and the way to the show.
struct AgendaList: View {
    let model: MonthModel
    var onSearch: () -> Void

    @State private var expanded: String?

    var body: some View {
        let sections = model.agenda
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.entries, id: \.cellID) { entry in
                            AgendaRow(
                                entry: entry,
                                isExpanded: expanded == entry.cellID,
                                isPending: model.feed.pending.contains(entry.cellID),
                                onSelect: { select(entry) },
                                onToggle: { Task { await model.feed.toggle(entry) } }
                            )
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
        .onChange(of: model.selection) { expanded = nil }
    }

    private func select(_ entry: CalendarEntry) {
        withAnimation(.snappy) {
            expanded = expanded == entry.cellID ? nil : entry.cellID
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
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.paper))
        .accessibilityAddTraits(.isHeader)
    }
}

private struct AgendaRow: View {
    let entry: CalendarEntry
    let isExpanded: Bool
    let isPending: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.ink))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.shortCode)
                        .monospacedDigit()
                    if let time = entry.timeText {
                        Text(time).monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(Color(.muted))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the episode" : "Shows the episode")
            if isExpanded {
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isExpanded ? Color.accentColor.opacity(0.10) : .clear)
        .opacity(entry.watched && !isExpanded ? 0.55 : 1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.episodeName {
                Text("“\(name)”")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let badge = entry.badge {
                WeekBadge(badge: badge)
            }
            if let overview = entry.episodeOverview {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(Color(.ink).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = entry.whereAndWhen {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    Label(
                        entry.watched ? "Watched" : "Mark watched",
                        systemImage: entry.watched ? "checkmark.circle.fill" : "circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(isPending)
                NavigationLink(value: entry.libraryItemId) {
                    Label("Open show", systemImage: "info.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
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
