import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// GAM-001…005: progress, badges, the ledger and the weekly friends board.
extension APIImplementation {
    var gamification: GamificationService {
        GamificationService(stores: stores)
    }

    func getProgress(_: Operations.GetProgress.Input) async throws -> Operations.GetProgress.Output {
        let progress = try await gamification.progress(currentUser())
        let unseen = progress.unseen
        // One summary for anything an import, a plan or the first run awarded.
        let origin = unseen.first { $0.origin != .live }?.origin ?? .live
        return .ok(.init(body: .json(.init(
            total: progress.total, level: progress.level, levelStart: progress.levelStart,
            nextLevelAt: progress.nextLevelAt, weekPoints: progress.weekPoints,
            streak: .init(
                current: progress.streak.current, longest: progress.streak.longest, today: progress.streak.today,
                days: progress.days.map { .init(date: $0.date, active: $0.active) }
            ),
            unseen: .init(
                count: unseen.count, origin: .init(origin),
                items: unseen.prefix(5).compactMap { Components.Schemas.BadgeAward($0) }
            )
        ))))
    }

    func listBadges(_: Operations.ListBadges.Input) async throws -> Operations.ListBadges.Output {
        let badges = try await gamification.badges(currentUser())
        return .ok(.init(body: .json(.init(items: badges.map(Components.Schemas.Badge.init)))))
    }

    func markBadgesSeen(_ input: Operations.MarkBadgesSeen.Input) async throws -> Operations.MarkBadgesSeen.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        guard body.ids.count <= 200 else {
            throw AppError(status: .unprocessableContent, code: "validation_failed", message: "Send at most 200 ids.")
        }
        try await gamification.markSeen(body.ids.compactMap { UUID(uuidString: $0) }, user: currentUser())
        return .noContent(.init())
    }

    func listPoints(_ input: Operations.ListPoints.Input) async throws -> Operations.ListPoints.Output {
        let user = try currentUser()
        let limit = min(max(input.query.limit ?? 50, 1), 100)
        let events = try await stores.gamification.events(userID: user, before: input.query.before, limit: limit)
        var titles: [TitleID: Title] = [:]
        for id in Set(events.compactMap(\.titleID)) {
            titles[id] = try await stores.titles.title(id: id)
        }
        let items = events.map { event in
            Components.Schemas.PointsEventItem(
                id: event.id.uuidString, kind: event.kind, points: event.points,
                title: event.titleID.flatMap { titles[$0] }.map(Components.Schemas.TitleSummary.init),
                day: event.localDate, at: event.createdAt, revocation: event.isRevocation
            )
        }
        return .ok(.init(body: .json(.init(
            items: items, nextBefore: events.count == limit ? events.last?.createdAt : nil
        ))))
    }

    func getLeaderboard(_ input: Operations.GetLeaderboard.Input) async throws -> Operations.GetLeaderboard.Output {
        let viewer = try currentUser()
        let board = try await gamification.leaderboard(viewer: viewer, week: input.query.week)
        return .ok(.init(body: .json(.init(
            week: board.week, from: board.from, until: board.until, optedIn: board.optedIn,
            entries: board.entries.map {
                .init(user: .init($0.user), points: $0.points, rank: $0.rank, you: $0.user.id == viewer)
            }
        ))))
    }
}

extension Components.Schemas.BadgeOrigin {
    init(_ origin: BadgeOrigin) {
        switch origin {
        case .live: self = .live
        case .batch: self = .batch
        case .backfill: self = .backfill
        }
    }
}

extension Components.Schemas.BadgeFamily {
    init(_ family: BadgeFamily) {
        self = .init(rawValue: family.rawValue) ?? .films
    }
}

extension Components.Schemas.BadgeAward {
    /// Nil for a badge no longer in the catalog. `reveal` defaults to the rule: a live award of a
    /// tiered badge's top tier, or of a hidden badge.
    init?(_ award: EarnedBadge, reveal: Bool? = nil) {
        guard let definition = BadgeCatalog.byID[award.badge] else { return nil }
        let top = award.tier == definition.maxTier && (definition.maxTier > 1 || definition.hidden)
        self.init(
            id: award.id.uuidString, badge: award.badge, name: definition.name, family: .init(definition.family),
            tier: award.tier, maxTier: definition.maxTier, awardedAt: award.awardedAt, origin: .init(award.origin),
            reveal: reveal ?? (award.origin == .live && top)
        )
    }
}

extension Components.Schemas.Badge {
    init(_ status: BadgeStatus) {
        let definition = status.definition
        let earned = !status.earned.isEmpty
        let secret = definition.hidden && !earned
        let byTier = Dictionary(status.earned.map { ($0.tier, $0.awardedAt) }) { first, _ in first }
        let shown = status.target ?? definition.thresholds.last ?? 1
        self.init(
            id: definition.id, family: .init(definition.family), hidden: definition.hidden, earned: earned,
            tier: status.tier, maxTier: definition.maxTier, _private: definition.isPrivate ? true : nil,
            name: secret ? nil : definition.name,
            description: secret ? nil : definition.describe(shown),
            progress: secret ? nil : status.target.map { .init(current: min(status.value, $0), target: $0) },
            tiers: secret ? [] : definition.thresholds.enumerated().map { index, threshold in
                .init(
                    tier: index + 1, threshold: threshold, description: definition.describe(threshold),
                    awardedAt: byTier[index + 1]
                )
            }
        )
    }
}
