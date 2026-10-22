import SwiftUI

/// A concert's day and time as the venue announces them. Both are read as text in a fixed zone
/// and formatted for the viewer's locale; nothing is converted to the viewer's time zone.
struct ConcertDay {
    let date: Date
    let time: Date?

    private static let zone = TimeZone.gmt

    init?(_ concert: Concert) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        let day = concert.localDate.split(separator: "-").compactMap { Int($0) }
        guard day.count == 3,
              let date = calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: 12))
        else { return nil }
        self.date = date
        let clock = (concert.localTime ?? "").split(separator: ":").compactMap { Int($0) }
        time = clock.count >= 2
            ? calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: clock[0], minute: clock[1]))
            : nil
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(timeZone: Self.zone)
    }

    /// "NOV".
    var month: String {
        date.formatted(style.month(.abbreviated)).uppercased()
    }

    /// "2".
    var day: String {
        date.formatted(style.day())
    }

    /// "Sat".
    var weekday: String {
        date.formatted(style.weekday(.abbreviated))
    }

    /// "Sat 2 Nov", in the locale's order.
    var short: String {
        date.formatted(style.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Saturday 2 November", with the year when it is not this one.
    var spoken: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        let thisYear = calendar.component(.year, from: .now) == calendar.component(.year, from: date)
        let format = style.weekday(.wide).day().month(.wide)
        return date.formatted(thisYear ? format : format.year())
    }

    /// "21:00" or "9:00 PM", as the venue announced it.
    var clock: String? {
        time?.formatted(style.hour().minute())
    }
}

/// One concert, date first: a ticket-stub date block, then the bill, where, how far and when,
/// and Tickets, which opens Ticketmaster. `compact` drops the stub for the list under the map.
/// VoiceOver reads the concert as one sentence, then Tickets on its own.
struct ConcertRow: View {
    let concert: Concert
    var compact = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let day = ConcertDay(concert)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            HStack(alignment: .top, spacing: 12) {
                if !compact, let day {
                    ConcertDateStub(day: day)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if compact, let day {
                        Text(day.short)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.accent))
                    }
                    Text(concert.name)
                        .font(.headline)
                        .foregroundStyle(Color(.ink))
                        .lineLimit(2)
                    if let whereText {
                        Text(whereText)
                            .font(.subheadline)
                            .foregroundStyle(Color(.muted))
                    }
                    if let detail = detail(day) {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Color(.muted))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(day))
            if let url = URL(string: concert.url) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("Tickets")
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Tickets for \(concert.name)")
                .accessibilityHint("Opens Ticketmaster.")
            }
        }
        .padding(.vertical, 4)
    }

    /// "MEO Arena · Lisboa".
    private var whereText: String? {
        let parts = [concert.venue, concert.city].compactMap(\.self).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "3.4 km · 21:00".
    private func detail(_ day: ConcertDay?) -> String? {
        let parts = [concert.distanceKm.map { Self.distance($0, width: .abbreviated) }, day?.clock]
            .compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Radiohead, Saturday 2 November, MEO Arena, Lisboa, 3.4 kilometres, 21:00".
    private func spoken(_ day: ConcertDay?) -> String {
        [
            concert.name,
            day?.spoken,
            concert.venue,
            concert.city,
            concert.distanceKm.map { Self.distance($0, width: .wide) },
            day?.clock,
        ]
        .compactMap(\.self)
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    static func distance(_ kilometres: Double, width: Measurement<UnitLength>.FormatStyle.UnitWidth) -> String {
        Measurement(value: kilometres, unit: UnitLength.kilometers).formatted(
            .measurement(width: width, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0 ... 1)))
        )
    }

    /// Stand-ins for loading rows, shown redacted.
    static let placeholders: [Concert] = (0 ..< 4).map { index in
        Concert(
            id: "placeholder-\(index)", name: "Artist name on tour", artists: [], localDate: "2026-11-02",
            localTime: "21:00", venue: "Venue name", city: "City", distanceKm: 3.4, url: "https://www.ticketmaster.com"
        )
    }
}

/// The ticket stub: month, the day in the display serif, weekday.
private struct ConcertDateStub: View {
    let day: ConcertDay
    @ScaledMetric(relativeTo: .largeTitle) private var width = 56

    var body: some View {
        VStack(spacing: 0) {
            Text(day.month)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.accent))
            Text(day.day)
                .font(.aaruDisplay(.largeTitle))
                .monospacedDigit()
                .foregroundStyle(Color(.ink))
            Text(day.weekday)
                .font(.caption)
                .foregroundStyle(Color(.muted))
        }
        .frame(width: width)
        .padding(.vertical, 8)
        .background(Color(.surface), in: .rect(cornerRadius: 10))
    }
}

// MARK: Previews

#Preview("Rows") {
    List {
        ConcertRow(concert: ConcertRow.placeholders[0])
        ConcertRow(concert: ConcertRow.placeholders[1], compact: true)
    }
}
