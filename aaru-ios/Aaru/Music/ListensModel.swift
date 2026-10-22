import AaruAPI
import Foundation
import Observation

/// Listens' Recent pane (MUS-008): newest first, fifty at a time.
@MainActor
@Observable
final class RecentListensModel {
    private(set) var listens: [Listen] = []
    private(set) var next: Date?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var problem: String?

    @ObservationIgnored private let api: Client?
    private static let page = 50

    init(api: Client?) {
        self.api = api
    }

    /// The first page, or the page before `before`.
    func load(before: Date?) async {
        guard let api, !loading, before != nil || !loaded else { return }
        loading = true
        defer {
            loading = false
            loaded = true
        }
        do {
            switch try await api.listListens(query: .init(before: before, limit: Self.page)) {
            case let .ok(response):
                let page = try response.body.json
                listens += page.items
                next = page.next
                problem = nil
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your listens could not be loaded."
            }
        } catch is CancellationError {
            return
        } catch {
            problem = "Your listens could not be loaded. Aaru could not reach the server."
        }
    }
}

/// A top list: Listens' Top pane (twenty, for a span) and Insights' Music (five, for its
/// period), by artist, album or track.
@MainActor
@Observable
final class TopListensModel {
    var span = InsightsSpan.last30
    var rank = TopListenBy.artist
    private(set) var rows: [TopListenRow]?
    private(set) var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let limit: Int

    static let spans: [InsightsSpan] = [.last7, .last30, .year, .all]

    init(api: Client?, limit: Int = 20) {
        self.api = api
        self.limit = limit
    }

    /// What Listens' load task restarts on.
    var key: String {
        "\(span.rawValue)-\(rank.rawValue)"
    }

    /// The span on screen, this year for Year.
    func load() async {
        await load(span: span, year: Calendar.current.component(.year, from: .now), month: nil)
    }

    /// One period: Insights' month or year.
    func load(span: InsightsSpan, year: Int, month: Int?) async {
        guard let api else { return }
        rows = nil
        problem = nil
        do {
            rows = try await Listening.top(api, by: rank, span: span, year: year, month: month, limit: limit)
        } catch is CancellationError {
            return
        } catch {
            problem = "The top list could not be loaded."
        }
    }
}
