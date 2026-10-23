import AaruAPI
import AaruCore
import Foundation
import Observation
import WidgetKit

typealias AchievementProgress = Components.Schemas.Progress
typealias AchievementBadge = Components.Schemas.Badge
typealias BadgeAward = Components.Schemas.BadgeAward
typealias PointsEventItem = Components.Schemas.PointsEventItem
typealias FriendsBoard = Components.Schemas.Leaderboard

/// GAM-001…005: the user's level, streak, badges and points, and the unlock moment. One model for
/// the app, shared through the environment: Home's strip, Friends' "You" card, Achievements and
/// the toast all read it. Writes elsewhere call `refreshSoon()`, and a new badge shows once.
@MainActor
@Observable
final class ProgressModel {
    /// What the toast says, once per unlock.
    enum Unlock: Equatable, Identifiable {
        /// One badge earned live: its medallion and name.
        case one(BadgeAward)
        /// Several live at once: "3 badges earned".
        case several(count: Int, first: BadgeAward)
        /// An import, an approved plan, or the first-run backfill: one summary.
        case summary(count: Int, origin: Components.Schemas.BadgeOrigin)

        var id: String {
            switch self {
            case let .one(award): award.id
            case let .several(count, first): "\(first.id)-\(count)"
            case let .summary(count, origin): "\(origin.rawValue)-\(count)"
            }
        }
    }

    private(set) var progress: AchievementProgress?
    private(set) var badges: [AchievementBadge] = []
    private(set) var hasLoadedBadges = false
    /// "How you earned it", newest first, and where the next page starts.
    private(set) var points: [PointsEventItem] = []
    private(set) var pointsNext: Date?
    private(set) var board: FriendsBoard?
    /// The toast to show; cleared when it goes.
    var unlock: Unlock?
    /// A top tier reached live: one full card, once.
    var reveal: BadgeAward?
    var problem: String?

    @ObservationIgnored let api: Client?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Awards already toasted on this device, so a seen-mark that failed never toasts twice.
    @ObservationIgnored private var shown: Set<String> = []

    init(api: Client?) {
        self.api = api
    }

    /// Reads progress; any badge not yet seen becomes the toast (and maybe the reveal), then is
    /// marked seen. A failure keeps what is shown.
    func refresh() async {
        guard let api, case let .ok(response) = try? await api.getProgress(),
              let next = try? response.body.json
        else { return }
        progress = next
        WidgetSnapshotStore.setStreak(.init(next.streak))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.streakWidgetKind)
        await announce(next.unseen)
    }

    /// After a write: refresh once things settle, so a run of ticks reads progress once.
    func refreshSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func loadBadges() async {
        guard let api else { return }
        do {
            if case let .ok(response) = try await api.listBadges() {
                badges = try response.body.json.items
                hasLoadedBadges = true
            }
        } catch {
            problem = "Your badges could not be loaded. Aaru could not reach the server."
        }
    }

    /// The first page of the ledger, or the next one with `more`.
    func loadPoints(more: Bool = false) async {
        guard let api else { return }
        if more, pointsNext == nil {
            return
        }
        do {
            let query = Operations.ListPoints.Input.Query(before: more ? pointsNext : nil, limit: 50)
            if case let .ok(response) = try await api.listPoints(query: query) {
                let page = try response.body.json
                points = more ? points + page.items : page.items
                pointsNext = page.nextBefore
            }
        } catch {
            problem = "Your points could not be loaded. Aaru could not reach the server."
        }
    }

    /// This week's board (GAM-005). Empty with `optedIn` false until the user joins.
    func loadBoard() async {
        guard let api, case let .ok(response) = try? await api.getLeaderboard(),
              let next = try? response.body.json
        else { return }
        board = next
    }

    func reset() {
        pending?.cancel()
        progress = nil
        badges = []
        hasLoadedBadges = false
        points = []
        pointsNext = nil
        board = nil
        unlock = nil
        reveal = nil
        problem = nil
        shown = []
    }

    /// Turns unseen awards into one toast and marks them seen. A batch or backfill is always one
    /// summary, whatever its size; the server lists five at a time, so the rest are marked too.
    private func announce(_ unseen: AchievementProgress.UnseenPayload) async {
        let fresh = unseen.items.filter { !shown.contains($0.id) }
        guard unseen.count >= 1, !fresh.isEmpty || unseen.count > unseen.items.count else { return }
        shown.formUnion(unseen.items.map(\.id))
        if unseen.origin != .live {
            unlock = .summary(count: unseen.count, origin: unseen.origin)
        } else if let first = fresh.first {
            unlock = unseen.count == 1 ? .one(first) : .several(count: unseen.count, first: first)
            reveal = fresh.first(where: \.reveal)
        }
        await markSeen(unseen)
    }

    private func markSeen(_ first: AchievementProgress.UnseenPayload) async {
        guard let api else { return }
        var unseen = first
        // Bounded: a backfill can hold every badge, five per page.
        for _ in 0 ..< 20 where !unseen.items.isEmpty {
            let ids = unseen.items.map(\.id)
            guard case .noContent = try? await api.markBadgesSeen(body: .json(.init(ids: ids))),
                  unseen.count > ids.count,
                  case let .ok(response) = try? await api.getProgress(),
                  let next = try? response.body.json
            else { return }
            progress = next
            shown.formUnion(next.unseen.items.map(\.id))
            unseen = next.unseen
        }
    }
}

extension ProgressModel.Unlock {
    /// The toast's line.
    var message: String {
        switch self {
        case let .one(award):
            "\(award.name) · earned"
        case let .several(count, _):
            "\(count) badges earned"
        case let .summary(count, origin):
            switch origin {
            case .backfill:
                "Aaru gives badges now. You've already earned \(count)."
            default:
                count == 1 ? "Your history earned you a badge" : "Your history earned you \(count) badges"
            }
        }
    }

    /// The medallion the toast leads with, when there is one award to show.
    var award: BadgeAward? {
        switch self {
        case let .one(award), let .several(_, award): award
        case .summary: nil
        }
    }
}
