import Foundation

extension WidgetSnapshot {
    /// The gallery and previews: a week of plausible shows, no artwork.
    static var sample: WidgetSnapshot {
        let now = Date.now
        let calendar = WidgetSnapshot.weekCalendar
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        func at(_ day: Int, _ hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: day * 24 + hour, to: monday) ?? now
        }
        func airing(
            _ title: String, _ season: Int, _ number: Int, _ date: Date, network: String?,
            kind: AiringKind = .regular, watched: Bool = false
        ) -> Airing {
            Airing(
                libraryItemId: UUID().uuidString, title: title, season: season, number: number,
                episodeName: nil, airsAt: date, airTimeKnown: true, network: network, kind: kind, watched: watched
            )
        }
        return WidgetSnapshot(
            upNext: [
                NextEpisode(
                    libraryItemId: "s1", title: "Severance", season: 2, number: 8, episodeName: "Sweet Vitriol",
                    runtimeMinutes: 57, remainingCount: 3, remainingMinutes: 160, isFinale: false
                ),
                NextEpisode(
                    libraryItemId: "s2", title: "The Bear", season: 4, number: 10, episodeName: "Forever",
                    runtimeMinutes: 41, remainingCount: 1, remainingMinutes: 41, isFinale: true
                ),
                NextEpisode(
                    libraryItemId: "s3", title: "Frieren", season: 1, number: 18, episodeName: nil,
                    runtimeMinutes: 24, remainingCount: 10, remainingMinutes: 240, isFinale: false
                ),
                NextEpisode(
                    libraryItemId: "s4", title: "Andor", season: 2, number: 4, episodeName: "Ever Been to Ghorman?",
                    runtimeMinutes: 50, remainingCount: 2, remainingMinutes: 100, isFinale: false
                ),
                NextEpisode(
                    libraryItemId: "s5", title: "Slow Horses", season: 5, number: 3, episodeName: "Missing Persons",
                    runtimeMinutes: 48, remainingCount: 4, remainingMinutes: 192, isFinale: false
                ),
            ],
            airings: [
                airing("Severance", 2, 7, at(0, 3), network: "Apple TV", watched: true),
                airing("Andor", 2, 5, at(1, 3), network: "Disney+"),
                airing("The Bear", 4, 10, at(2, 2), network: "FX", kind: .finale),
                airing("Slow Horses", 5, 4, at(2, 9), network: "Apple TV"),
                airing("The Pitt", 1, 15, now.addingTimeInterval(3 * 3600), network: "HBO Max"),
                airing("Frieren", 2, 1, at(4, 16), network: "Crunchyroll", kind: .premiere),
                airing("Pluribus", 1, 1, at(5, 3), network: "Apple TV", kind: .premiere),
                airing("Severance", 2, 8, at(6, 3), network: "Apple TV"),
            ].sorted { $0.airsAt < $1.airsAt },
            writtenAt: now
        )
    }
}
