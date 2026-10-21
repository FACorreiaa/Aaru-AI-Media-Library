import SwiftUI

/// iPhone: the same cells, one day at a time. A strip of the seven days on top; swipe between
/// days. Stepping past either end moves the week a day, as the grid does.
struct WeekDayPager: View {
    let model: WeekModel
    @Binding var selection: Date

    var body: some View {
        VStack(spacing: 0) {
            strip
            pages
        }
    }

    private var strip: some View {
        HStack(spacing: 4) {
            ForEach(model.days, id: \.self) { day in
                let isSelected = model.calendar.isDate(day, inSameDayAs: selection)
                Button {
                    withAnimation(.snappy) { selection = day }
                } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Circle()
                            .fill(model.entries(on: day).isEmpty ? .clear : Color(.accent))
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(isSelected ? Color(.paper) : model.isToday(day) ? Color(.accent) : Color(.ink))
                    .background(isSelected ? Color(.accent) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.paper))
    }

    @ViewBuilder private var pages: some View {
        #if os(iOS)
            TabView(selection: $selection) {
                ForEach(model.days, id: \.self) { day in
                    WeekDayList(model: model, day: day).tag(day)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        #else
            WeekDayList(model: model, day: selection)
        #endif
    }
}

private struct WeekDayList: View {
    let model: WeekModel
    let day: Date

    var body: some View {
        let entries = model.entries(on: day)
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(entries, id: \.cellID) { entry in
                    Button { model.feed.open(entry) } label: {
                        WeekCell(entry: entry, isPending: model.pending.contains(entry.cellID)) {
                            Task { await model.toggle(entry) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if entries.isEmpty, model.hasLoaded {
                    Text("Nothing from your shows on \(day.formatted(.dateTime.weekday(.wide))).")
                        .font(.callout)
                        .foregroundStyle(Color(.muted))
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
