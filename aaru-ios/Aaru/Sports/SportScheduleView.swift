import SwiftUI

/// Sports → Schedule: a strip of days (three back, seven ahead, Today marked), and the chosen
/// local day's events for the followed leagues, grouped by league under its badge. Events a
/// followed team plays in carry the amber edge.
struct SportScheduleView: View {
    @Bindable var model: SportsModel
    let onFind: () -> Void
    let onOpen: (SportEvent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SportDateStrip(days: model.days, selection: $model.day)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        if let schedule = model.schedule {
            if schedule.groups.isEmpty {
                emptyDay(pending: schedule.pending)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: .sectionHeaders) {
                        ForEach(schedule.groups, id: \.groupKey) { group in
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                        if index > 0 {
                                            Divider().padding(.leading, 12)
                                        }
                                        SportEventRow(event: event) { onOpen(event) }
                                    }
                                }
                                .card()
                            } header: {
                                LeagueHeader(group: group)
                            }
                        }
                        if schedule.pending {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                QuietNote("Fetching more leagues…")
                            }
                        }
                        SportsCredit()
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                }
            }
        } else if model.failedDays.contains(model.day.key) {
            LoadFailedView(
                title: "Couldn't load the schedule",
                message: "This day's events didn't load."
            ) { await model.loadSchedule(model.day) }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func emptyDay(pending: Bool) -> some View {
        if pending {
            VStack(spacing: 8) {
                ProgressView()
                QuietNote("Fetching your leagues…")
            }
        } else {
            ContentUnavailableView {
                Label("Nothing on \(model.day.isToday ? "today" : model.day.spoken)", systemImage: "calendar")
            } description: {
                Text("The leagues you follow have no events this day.")
            } actions: {
                Button("Find leagues and teams", action: onFind)
                    .buttonStyle(.bordered)
            }
        }
    }
}

extension SportScheduleGroup {
    /// A group's identity on screen: its league id, else its name.
    var groupKey: String {
        leagueId ?? "\(sport)|\(league)"
    }
}

/// A league's pinned header: badge, name and sport, on Paper so rows pass under it.
private struct LeagueHeader: View {
    let group: SportScheduleGroup

    var body: some View {
        HStack(spacing: 10) {
            SportBadge(url: group.badgeUrl, sport: group.sport, size: 24)
            Text(group.league)
                .font(.aaruDisplay(.headline, weight: .semibold))
                .foregroundStyle(Color(.ink))
            Text(group.sport)
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.paper))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The days, side by side, scrolled to the chosen one: weekday over the day's number, Today
/// in the accent, the chosen day filled.
struct SportDateStrip: View {
    let days: [SportDay]
    @Binding var selection: SportDay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(days) { day in
                        DayButton(day: day, isSelected: day == selection) { selection = day }
                            .id(day.key)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selection.key, anchor: .center) }
            .onChange(of: selection) { _, day in
                withAnimation(reduceMotion ? nil : AaruMotion.ease()) {
                    proxy.scrollTo(day.key, anchor: .center)
                }
            }
        }
    }
}

private struct DayButton: View {
    let day: SportDay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(day.weekday)
                    .font(.caption.weight(.semibold))
                Text(day.dayNumber)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(foreground)
            .frame(minWidth: 52)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                isSelected ? Color(.accent) : .clear,
                in: .rect(cornerRadius: AaruRadius.field, style: .continuous)
            )
            .contentShape(.rect(cornerRadius: AaruRadius.field, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected {
            return Color(.onAccent)
        }
        return Color(day.isToday ? .accent : .ink)
    }
}
