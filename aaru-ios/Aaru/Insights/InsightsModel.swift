import AaruAPI
import Foundation
import Observation

/// The span Insights shows: the last 7 or 30 days, one month, one year, or everything.
enum InsightsSpan: String, CaseIterable, Identifiable {
    case last7, last30, month, year, all

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .last7: "7 days"
        case .last30: "30 days"
        case .month: "Month"
        case .year: "Year"
        case .all: "All time"
        }
    }

    /// GAM-006d: a window ending today, compared with the one before. Nothing to step through.
    var isRolling: Bool {
        self == .last7 || self == .last30
    }

    /// The `span` query a span sends; calendar months and years send a year instead.
    var query: Operations.GetStats.Input.Query.SpanPayload? {
        switch self {
        case .last7: .last7
        case .last30: .last30
        case .all: .all
        case .month, .year: nil
        }
    }
}

/// One period Insights can show. `month` is read only for the month span.
struct InsightsPeriod: Hashable {
    var span: InsightsSpan
    var year: Int
    var month: Int

    /// "Last 7 days", "October 2026", "2026", "All time".
    var label: String {
        switch span {
        case .last7: "Last 7 days"
        case .last30: "Last 30 days"
        case .month: RecapPeriod(year: year, month: month).label
        case .year: "\(year)"
        case .all: "All time"
        }
    }

    /// The Recap story for this period; none for all time or a rolling window.
    var recap: RecapPeriod? {
        switch span {
        case .month: RecapPeriod(year: year, month: month)
        case .year: RecapPeriod(year: year)
        case .all, .last7, .last30: nil
        }
    }

    /// One month or year earlier (`delta` -1) or later (+1).
    func stepped(_ delta: Int) -> InsightsPeriod {
        var next = self
        switch span {
        case .month:
            let index = year * 12 + (month - 1) + delta
            next.year = index / 12
            next.month = index % 12 + 1
        case .year: next.year += delta
        case .all, .last7, .last30: break
        }
        return next
    }

    /// Whether this period starts after `now`'s: Insights never steps into the future.
    func isAfter(_ other: InsightsPeriod) -> Bool {
        switch span {
        case .month: (year, month) > (other.year, other.month)
        case .year: year > other.year
        case .all, .last7, .last30: false
        }
    }
}

/// GAM-006c: the user's own numbers from `/v1/me/stats` for a month, a year or all time, in the
/// device's time zone. Loaded periods are kept, so stepping back and forth does not refetch.
@MainActor
@Observable
final class InsightsModel {
    var period: InsightsPeriod
    private(set) var loaded: [InsightsPeriod: Stats] = [:]
    private(set) var isLoading = false
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let current: InsightsPeriod

    init(
        api: Client?, span: InsightsSpan = .month, now: Date = .now, calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.api = api
        self.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: now)
        current = InsightsPeriod(span: .month, year: parts.year ?? 2000, month: parts.month ?? 1)
        period = current.with(span: span)
    }

    /// For previews: one period's stats already in place.
    convenience init(preview stats: Stats, span: InsightsSpan = .month) {
        self.init(api: nil)
        period = InsightsPeriod(span: span, year: stats.year, month: stats.month ?? 1)
        loaded[period] = stats
    }

    var stats: Stats? {
        loaded[period]
    }

    var span: InsightsSpan {
        get { period.span }
        set {
            // Switching span lands on the current month or year, not one picked under another span.
            period = current.with(span: newValue)
        }
    }

    var canStep: Bool {
        span != .all && !span.isRolling
    }

    var canStepForward: Bool {
        canStep && !period.stepped(1).isAfter(current.with(span: span))
    }

    func step(_ delta: Int) {
        let next = period.stepped(delta)
        guard !next.isAfter(current.with(span: span)) else { return }
        period = next
    }

    func load() async {
        let wanted = period
        guard let api, loaded[wanted] == nil else { return }
        isLoading = true
        defer { isLoading = false }
        let query = Operations.GetStats.Input.Query(
            year: wanted.span.query == nil ? wanted.year : nil,
            span: wanted.span.query,
            month: wanted.span == .month ? wanted.month : nil,
            tz: timeZone.identifier
        )
        do {
            guard case let .ok(response) = try await api.getStats(query: query) else {
                problem = "Insights could not be loaded."
                return
            }
            loaded[wanted] = try response.body.json
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            problem = "Aaru could not reach the server."
        }
    }
}

private extension InsightsPeriod {
    func with(span: InsightsSpan) -> InsightsPeriod {
        InsightsPeriod(span: span, year: year, month: month)
    }
}
