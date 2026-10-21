import AaruAPI
import SwiftUI

/// "September  October  November": the month in the middle, its neighbours a tap away (Stremio).
struct MonthSwitcher: View {
    let model: MonthModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            neighbour(-1)
            Text(model.title())
                .font(.aaruDisplay(.title2, weight: .semibold))
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
        .font(.aaruDisplay(.body))
        .foregroundStyle(Color(.muted))
        .lineLimit(1)
        .accessibilityLabel(offset < 0 ? "Previous month, \(model.title(offset: offset))"
            : "Next month, \(model.title(offset: offset))")
    }
}

/// The Monday-start weeks of the month. Three posters per day on Mac and iPad; two small ones and
/// "+N" on iPhone (CAL-003), where a tapped day also opens as a sheet.
struct MonthGridView: View {
    enum Style {
        case posters, compact
    }

    let model: MonthModel
    let style: Style
    /// iPhone: the tapped day opens as a sheet.
    var onOpenDay: ((Date) -> Void)?

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
            case .compact:
                grid(rowHeight: 68)
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
                    onOpenDay?(day)
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

    private var shown: Int {
        style == .posters ? 3 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color(.paper) : Color(.ink))
                .frame(minWidth: 26, minHeight: 26)
                .background(isToday ? Color(.accent) : .clear, in: Circle())
            posters
            Spacer(minLength: 0)
        }
        .opacity(isMuted ? 0.45 : 1)
        .padding(style == .posters ? 6 : 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Past the posters that fit, the last slot says "+N".
    private var visible: ArraySlice<CalendarEntry> {
        entries.count <= shown ? entries[...] : entries.prefix(shown - 1)
    }

    private var overflow: Int {
        entries.count - visible.count
    }

    private var posters: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(visible, id: \.cellID) { entry in
                PosterThumb(entry: entry)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(.ink))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(.ink).opacity(0.1), in: Capsule())
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if let badge = entry.badge {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(badge.tint, lineWidth: 1.5)
                }
            }
            .opacity(entry.watched ? 0.4 : 1)
            .frame(maxWidth: 72)
    }

    private var initials: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.accent).opacity(0.55), Color(.gold).opacity(0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Text(entry.title.initials)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
    }
}

extension Components.Schemas.TitleSummary {
    /// "SH" for Slow Horses, "S" for Severance.
    var initials: String {
        title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
