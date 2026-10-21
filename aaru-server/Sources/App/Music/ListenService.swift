import AaruCore
import Foundation

/// MUS-005: the listening log. Scrobblers add listens (`ListenBrainzRoutes`); the signed-in user
/// reads them back as recent listens and top lists. A listen never touches the library.
struct ListenService: Sendable {
    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    /// Keeps each listen unless it repeats one already stored. Returns how many were kept.
    func submit(_ listens: [NewListen], from caller: AgentCaller) async throws -> Int {
        try await stores.listens.insert(listens, userID: caller.userID, agentTokenID: caller.token.id)
    }

    /// A page's size: 20 unless asked, never more than 100.
    static func pageSize(_ limit: Int?) -> Int {
        min(max(limit ?? 20, 1), 100)
    }

    /// Newest first, a page at a time.
    func listens(userID: UserID, before: Date?, limit: Int?) async throws -> [Listen] {
        try await stores.listens.listens(userID: userID, before: before, limit: Self.pageSize(limit))
    }

    /// Every listen, newest first, for the account export.
    func all(userID: UserID) async throws -> [Listen] {
        try await stores.listens.listens(userID: userID, before: nil, limit: .max)
    }

    /// A period read the way `/v1/me/stats` reads it: a year, a month of it, or a span.
    func period(span: StatsPeriod.Span?, year: Int?, month: Int?, timeZone: String?) throws -> StatsPeriod {
        try StatsService.period(span: span, year: year, month: month, timeZone: timeZone, now: now())
    }

    /// The period's top artists, tracks or albums: 10 unless asked, never more than 50. `artist`
    /// narrows it to one artist.
    func top(userID: UserID, by grouping: ListenGrouping, period: StatsPeriod, limit: Int?, artist: String? = nil)
        async throws -> ListenTop
    {
        try await stores.listens.top(
            userID: userID, by: grouping, period: period, limit: min(max(limit ?? 10, 1), 50), artist: artist
        )
    }
}
