import AaruAPI
import SwiftUI

typealias Listen = Components.Schemas.Listen
typealias TopListenRow = Components.Schemas.ListenTop.ItemsPayloadPayload

/// What a top list ranks: artists, tracks or albums. Same labels as the web's `TOP_BY`.
enum TopListenBy: String, CaseIterable, Identifiable {
    case artist, track, album

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .artist: "Artists"
        case .track: "Tracks"
        case .album: "Albums"
        }
    }

    var query: Operations.GetTopListens.Input.Query.ByPayload {
        switch self {
        case .artist: .artist
        case .track: .track
        case .album: .album
        }
    }

    /// "Teardrop", with "Massive Attack" under it; an artist row has no second line.
    func lines(_ row: TopListenRow) -> (String, String?) {
        switch self {
        case .artist: (row.artist, nil)
        case .track: (row.track ?? row.artist, row.artist)
        case .album: (row.album ?? row.artist, row.artist)
        }
    }
}

enum Listening {
    /// "1 play", "1,204 plays".
    static func plays(_ count: Int) -> String {
        count == 1 ? "1 play" : "\(count.formatted()) plays"
    }

    /// "Massive Attack · Mezzanine", or where it played when the album is unknown.
    static func subtitle(_ listen: Listen) -> String {
        [listen.artist, listen.album ?? listen.musicService].compactMap(\.self).joined(separator: " · ")
    }

    /// Today / Yesterday / "Mon, Oct 19" / "Oct 19, 2025", in the device's time zone.
    static func dayHeading(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return sameYear
            ? day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Listens under their local day, newest first.
    static func byDay(_ listens: [Listen], now: Date, calendar: Calendar = .current) -> [ListenDay] {
        var days: [ListenDay] = []
        for listen in listens {
            let heading = dayHeading(listen.listenedAt, now: now, calendar: calendar)
            if days.last?.heading == heading {
                days[days.count - 1].listens.append(listen)
            } else {
                days.append(ListenDay(heading: heading, listens: [listen]))
            }
        }
        return days
    }

    /// The top list for one span, read in the device's time zone. A calendar year sends `year`.
    static func top(
        _ api: Client, by rank: TopListenBy, span: InsightsSpan, year: Int, month: Int? = nil, limit: Int
    ) async throws -> [TopListenRow] {
        let query = Operations.GetTopListens.Input.Query(
            by: rank.query,
            year: span.query == nil ? year : nil,
            span: span.query.flatMap { .init(rawValue: $0.rawValue) },
            month: span == .month ? month : nil,
            tz: TimeZone.current.identifier,
            limit: limit
        )
        guard case let .ok(response) = try await api.getTopListens(query: query) else {
            throw URLError(.badServerResponse)
        }
        return try response.body.json.items
    }
}

struct ListenDay {
    let heading: String
    var listens: [Listen]
}

/// A 40pt album cover, or a quiet note while the album is unknown.
struct ListenCover: View {
    let url: String?

    var body: some View {
        Color(.surface)
            .frame(width: 40, height: 40)
            .overlay {
                AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note").foregroundStyle(Color(.muted))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AaruRadius.thumb, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Opens the album when it is in the library; otherwise the row is plain. Pushes the library
/// item id, which every stack that passes `library` routes to the title page.
struct AlbumLink<Label: View>: View {
    let titleID: String?
    let library: LibraryModel?
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let titleID, let entry = library?.entry(forTitle: titleID) {
            NavigationLink(value: entry.id, label: label)
        } else {
            label()
        }
    }
}

/// A ranked list of artists, tracks or albums with their plays.
struct TopListenList: View {
    let rows: [TopListenRow]
    let rank: TopListenBy
    let library: LibraryModel?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let lines = rank.lines(row)
                AlbumLink(titleID: row.albumRef?.titleId, library: library) {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.aaruDisplay(.title3, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 24)
                            .foregroundStyle(Color(.muted))
                        ListenCover(url: row.coverUrl)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lines.0).font(.body.weight(.medium)).lineLimit(1)
                            if let second = lines.1 {
                                Text(second).font(.footnote).foregroundStyle(Color(.muted)).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(Listening.plays(row.count))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Color(.muted))
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }
}
