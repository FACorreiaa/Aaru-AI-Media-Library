import AaruAPI
import Foundation
import Observation

/// GAM-006a: one period's stats from `/v1/me/stats`, in the device's time zone, and the deck
/// the story plays.
@MainActor
@Observable
final class RecapModel {
    let period: RecapPeriod
    private(set) var stats: Stats?
    private(set) var deck: [RecapCard] = []
    private(set) var isLoading = false
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let timeZone: TimeZone

    init(period: RecapPeriod, api: Client?, timeZone: TimeZone = .current) {
        self.period = period
        self.api = api
        self.timeZone = timeZone
    }

    /// For previews: stats already in place.
    convenience init(preview stats: Stats) {
        self.init(period: RecapPeriod(year: stats.year, month: stats.month), api: nil)
        apply(stats)
    }

    var isEmpty: Bool {
        stats.map(RecapDeck.isEmpty) ?? false
    }

    func load() async {
        guard let api, stats == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let output = try await api.getStats(
                query: .init(year: period.year, month: period.month, tz: timeZone.identifier)
            )
            guard case let .ok(response) = output else {
                problem = "Your recap could not be loaded."
                return
            }
            try apply(response.body.json)
            problem = nil
        } catch {
            problem = "Aaru could not reach the server."
        }
    }

    private func apply(_ stats: Stats) {
        self.stats = stats
        deck = RecapDeck.cards(from: stats)
    }
}
