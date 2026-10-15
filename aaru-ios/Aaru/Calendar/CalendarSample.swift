import AaruAPI
import Foundation

extension CalendarFeed {
    /// For previews: a month that looks like a real one. Premieres, a finale, watched episodes,
    /// date-only air dates, synopses, and no artwork (the placeholders are what previews check).
    static var sample: CalendarFeed {
        let calendar = Calendar.aaru
        let start = WeekModel.weekStart(of: .now, in: calendar)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        func dateOnly(_ day: Int) -> Date {
            let local = calendar.dateComponents([.year, .month, .day], from: at(day, 12))
            return utcCalendar.date(from: local) ?? start
        }
        func show(_ name: String, _ network: String?) -> Components.Schemas.TitleSummary {
            .init(id: UUID().uuidString, _type: .show, title: name, network: network, isAnime: false, ids: .init())
        }
        func entry(
            _ title: Components.Schemas.TitleSummary, _ season: Int, _ number: Int, _ name: String, _ airsAt: Date,
            exact: Bool = true, watched: Bool = false, kind: CalendarEntry.KindPayload = .regular,
            overview: String? = nil
        ) -> CalendarEntry {
            .init(
                libraryItemId: title.id, title: title, season: season, number: number, episodeName: name,
                episodeOverview: overview, airsAt: airsAt, airTimeKnown: exact, watched: watched, kind: kind
            )
        }
        let severance = show("Severance", "Apple TV+")
        let andor = show("Andor", "Disney+")
        let frieren = show("Frieren: Beyond Journey's End", "Crunchyroll")
        let bear = show("The Bear", "FX")
        let slow = show("Slow Horses", "Apple TV+")
        let pitt = show("The Pitt", "HBO Max")
        let pluribus = show("Pluribus", nil)
        var entries = [
            entry(
                severance,
                2,
                1,
                "Hello, Ms. Cobel",
                at(0, 3),
                kind: .premiere,
                overview: "Mark returns to Lumon to find the severed floor changed and his team replaced."
            ),
            entry(pitt, 1, 14, "8:00 P.M.", at(0, 21), watched: true),
            entry(
                andor,
                2,
                4,
                "Ever Been to Ghorman?",
                at(1, 3),
                overview: "Cassian takes a job that brings him closer to the Rebellion than he wants."
            ),
            entry(frieren, 2, 1, "The Journey North", at(2, 16, 30), kind: .premiere),
            entry(
                bear,
                4,
                10,
                "Forever",
                dateOnly(3),
                exact: false,
                kind: .finale,
                overview: "Carmy has to decide what the restaurant is for."
            ),
            entry(slow, 5, 3, "Missing Persons", at(3, 9)),
            entry(pitt, 1, 15, "9:00 P.M.", at(4, 21)),
            entry(severance, 2, 2, "Goodbye, Mrs. Selvig", at(5, 3)),
            entry(pluribus, 1, 1, "We Is Us", at(6, 3), kind: .premiere),
        ]
        // The rest of the month: the weekly shows carry on, one ends its season.
        for week in 1 ... 4 {
            entries.append(entry(severance, 2, 2 + week, "Episode \(2 + week)", at(7 * week + 5, 3)))
            entries.append(entry(pitt, 1, 15 + week, "\(9 + week):00 P.M.", at(7 * week + 4, 21)))
            entries.append(entry(
                andor,
                2,
                4 + week,
                "Chapter \(4 + week)",
                at(7 * week + 1, 3),
                kind: week == 4 ? .finale : .regular
            ))
            entries.append(entry(slow, 5, 3 + week, "Part \(3 + week)", dateOnly(7 * week + 3), exact: false))
        }
        for week in -2 ... -1 {
            entries.append(entry(pitt, 1, 14 + week, "\(8 + week):00 P.M.", at(7 * week + 4, 21), watched: true))
            entries.append(entry(andor, 2, 4 + week, "Chapter \(4 + week)", at(7 * week + 1, 3), watched: true))
        }
        return CalendarFeed(preview: entries, calendar: calendar)
    }
}
