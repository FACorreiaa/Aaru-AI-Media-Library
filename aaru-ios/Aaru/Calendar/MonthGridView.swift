import AaruAPI
import SwiftUI

/// "September  October  November": the month in the middle, its neighbours a tap away (Stremio).
struct MonthSwitcher: View {
    let model: MonthModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            neighbour(-1)
            Text(model.title())
                .font(.system(.title2, design: .serif, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            neighbour(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func neighbour(_ offset: Int) -> some View {
        Button(model.title(offset: offset)) {
            Task { await model.step(months: offset) }
        }
        .buttonStyle(.plain)
        .font(.system(.body, design: .serif))
        .foregroundStyle(Color(.muted))
        .lineLimit(1)
        .accessibilityLabel(offset < 0 ? "Previous month, \(model.title(offset: offset))"
            : "Next month, \(model.title(offset: offset))")
    }
}

/// The Monday-start weeks of the month. Posters per day on Mac and iPad; dots on iPhone.
struct MonthGridView: View {
    enum Style {
        case posters, dots
    }

    let model: MonthModel
    let style: Style

    private static let spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(model.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(.muted))
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            switch style {
            case .posters:
                GeometryReader { proxy in
                    grid(rowHeight: rowHeight(in: proxy.size.height))
                }
            case .dots:
                grid(rowHeight: 46)
            }
        }
    }

    private func rowHeight(in height: CGFloat) -> CGFloat {
        let rows = CGFloat(max(1, model.gridDays.count / 7))
        return max(84, (height - Self.spacing * (rows - 1)) / rows)
    }

    private func grid(rowHeight: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 7),
            spacing: Self.spacing
        ) {
            ForEach(model.gridDays, id: \.self) { day in
                Button {
                    withAnimation(.snappy) { model.select(day) }
                } label: {
                    MonthDayCell(
                        day: day, entries: model.entries(on: day), style: style,
                        isMuted: !model.isInMonth(day) || model.isPast(day),
                        isToday: model.isToday(day), isSelected: model.isSelected(day)
                    )
                    .frame(height: rowHeight)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One day: its number (today on an accent disc), then up to three posters or dots and "+N".
private struct MonthDayCell: View {
    let day: Date
    let entries: [CalendarEntry]
    let style: MonthGridView.Style
    let isMuted: Bool
    let isToday: Bool
    let isSelected: Bool

    private static let shown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color(.paper) : Color(.ink))
                .frame(minWidth: 26, minHeight: 26)
                .background(isToday ? Color(.accent) : .clear, in: Circle())
            switch style {
            case .posters: posters
            case .dots: dots
            }
            Spacer(minLength: 0)
        }
        .opacity(isMuted ? 0.45 : 1)
        .padding(style == .posters ? 6 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style == .posters ? .topLeading : .top)
        .background(Color(.ink).opacity(isMuted ? 0.02 : 0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.accent), lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var overflow: Int {
        max(0, entries.count - Self.shown)
    }

    private var posters: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(entries.prefix(Self.shown), id: \.cellID) { entry in
                PosterThumb(entry: entry)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.muted))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(entries.prefix(Self.shown), id: \.cellID) { entry in
                Circle()
                    .fill(entry.dotColor)
                    .opacity(entry.watched ? 0.35 : 1)
                    .frame(width: 5, height: 5)
            }
            if overflow > 0 {
                Text("+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(.muted))
            }
        }
        .frame(height: 6)
    }

    private var accessibilityText: String {
        let date = day.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : "")
        switch entries.count {
        case 0: return date
        case 1: return "\(date), \(entries[0].title.title)"
        default: return "\(date), \(entries.count) episodes"
        }
    }
}

/// A 2:3 poster, else a teal-to-gold tile with the show's initials. Dimmed once watched.
private struct PosterThumb: View {
    let entry: CalendarEntry

    var body: some View {
        Color(.medallion)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                AsyncImage(url: entry.title.posterUrl.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                if let badge = entry.badge {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(badge.tint, lineWidth: 1.5)
                }
            }
            .opacity(entry.watched ? 0.4 : 1)
            .frame(maxWidth: 72)
    }

    private var initials: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.accent).opacity(0.55), Color.weekGold.opacity(0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(entry.title.initials)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
    }
}

extension CalendarEntry {
    /// iPhone's month dots: gold finale, teal premiere or new season, ink otherwise.
    var dotColor: Color {
        switch badge {
        case .finale: .weekGold
        case .premiere, .newSeason: Color(.accent)
        case nil: Color(.ink).opacity(0.55)
        }
    }
}

extension Components.Schemas.TitleSummary {
    /// "SH" for Slow Horses, "S" for Severance.
    var initials: String {
        title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
