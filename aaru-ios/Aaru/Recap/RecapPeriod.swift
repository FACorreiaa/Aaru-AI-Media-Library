import AaruAPI
import Foundation

typealias Stats = Components.Schemas.Stats
typealias StatsTitle = Components.Schemas.StatsTitle
typealias StatsMoment = Components.Schemas.StatsMoment
typealias StatsGenre = Components.Schemas.StatsGenre
typealias Persona = Components.Schemas.Stats.PersonaPayload
typealias TitleSummary = Components.Schemas.TitleSummary

/// One recap: a whole year, or one month of it.
struct RecapPeriod: Hashable, Identifiable {
    var year: Int
    var month: Int?

    var id: String {
        month.map { "\(year)-\($0)" } ?? "\(year)"
    }

    /// "October 2026", or "2026".
    var label: String {
        guard let month else { return "\(year)" }
        return "\(RecapDeck.months[month - 1]) \(year)"
    }

    /// The recap Home offers today, if any: the year review from Dec 1 to Jan 15, and last
    /// month's recap in the first week of a month. The same windows as the web.
    static func offered(now: Date, calendar: Calendar) -> RecapPeriod? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12 {
            return RecapPeriod(year: year)
        }
        if month == 1, day <= 15 {
            return RecapPeriod(year: year - 1)
        }
        if day <= 7 {
            return previousMonth(now: now, calendar: calendar)
        }
        return nil
    }

    static func previousMonth(now: Date, calendar: Calendar) -> RecapPeriod {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let (year, month) = (parts.year ?? 2000, parts.month ?? 1)
        return month == 1 ? RecapPeriod(year: year - 1, month: 12) : RecapPeriod(year: year, month: month - 1)
    }

    /// Settings' shortcuts: this year so far, last month, last year.
    static func shortcuts(now: Date, calendar: Calendar) -> [RecapPeriod] {
        let year = calendar.component(.year, from: now)
        return [RecapPeriod(year: year), previousMonth(now: now, calendar: calendar), RecapPeriod(year: year - 1)]
    }
}

extension TitleSummary {
    var mediaKind: MediaKind {
        MediaKind(type: _type, isAnime: isAnime)
    }

    var posterURL: URL? {
        posterUrl.flatMap(URL.init(string:))
    }
}
