import AaruCore
import Foundation
import Logging

/// Keeps the "Now playing" Live Activity in step with everything that plays (SCR-008, SCR-009):
/// one activity per device lists the user's live set. Each report, and each sweep, recomputes the
/// set and pushes only when what the activity shows changes: the first thing playing starts it on
/// every device by push, a row added, gone, paused, resumed or ticked updates it, and nothing left
/// ends it. Position alone never pushes, so a player's heartbeat costs nothing. Best effort: a push
/// outage never fails a report.
struct LiveSetNotifier: Sendable {
    /// How long a ticked row stays, reading "Watched".
    static let watchedLinger: TimeInterval = 8
    /// How long past the next expected change the activity may go unheard before it reads stale.
    static let staleGrace: TimeInterval = 30 * 60
    /// An end time moving by more than this (a seek, a duration first known) is a change.
    static let endTimeSlack: TimeInterval = 60

    let stores: Stores
    let sender: any LiveActivityPushing
    var logger = Logger(label: "aaru-now-playing")

    /// Recomputes what plays for `userID` and pushes the difference. `ticked` names watch events
    /// that just ticked: their rows stay a moment as "Watched".
    func sync(userID: UserID, now: Date, ticked: [UUID] = []) async {
        do {
            guard try await stores.watchEvents.hasLiveActivityTokens(userID: userID) else { return }
            // A second report saving first means this one recomputes once on top of it.
            if try await !attempt(userID: userID, now: now, ticked: ticked) {
                _ = try await attempt(userID: userID, now: now, ticked: ticked)
            }
        } catch {
            logger.warning("Live Activity push failed", metadata: ["error": "\(error)"])
        }
    }

    /// An activity's token arrived, maybe well after a push started it in the background: the app
    /// uploads it when iOS next runs it. The token hears what the activity should show now.
    func caughtUp(_ token: LiveActivityToken, userID: UserID, now: Date) async {
        do {
            if let pushed = try await stores.watchEvents.liveActivityState(userID: userID).pushed {
                await deliver(.update, pushed, to: [token], now: now)
            } else if try await LiveSet.load(stores, userID: userID, now: now).isEmpty {
                await deliver(.end(dismissal: now), NowPlayingActivityState(items: []), to: [token], now: now)
                try await stores.watchEvents.forgetLiveActivity(token: token.token)
            } else {
                // The app started the activity itself: it is the one running now.
                await sync(userID: userID, now: now)
            }
        } catch {
            logger.warning("Live Activity catch-up failed", metadata: ["error": "\(error)"])
        }
    }

    /// One read, compute, save and push. False when another report saved first.
    private func attempt(userID: UserID, now: Date, ticked: [UUID]) async throws -> Bool {
        var state = try await stores.watchEvents.liveActivityState(userID: userID)
        let ids = Set(ticked.map { $0.uuidString.lowercased() })
        let justTicked = (state.pushed?.items ?? []).filter { ids.contains($0.id) }.map { item in
            var item = item
            item.watched = true
            return LiveActivityState.Lingering(item: item, until: now.addingTimeInterval(Self.watchedLinger))
        }
        let lingering = (state.lingering.filter { !ids.contains($0.item.id) } + justTicked).filter { $0.until > now }
        let entries = try await LiveSet.load(stores, userID: userID, now: now)
        let shown = Set(lingering.map(\.item.id))
        let items = lingering.map(\.item) + entries.map(\.activityItem).filter { !shown.contains($0.id) }
        let next = NowPlayingActivityState(items: Array(items.prefix(NowPlayingActivityState.maxItems)))
        let nextCheck = (lingering.map(\.until) + entries.map(\.liveUntil)).min()

        let event: LiveActivityPush.Event?
        switch (state.pushed, next.items.isEmpty) {
        case (nil, true): event = nil
        case (.some, true): event = .end(dismissal: now)
        case (nil, false): event = .start(alertTitle: "Now playing", alertBody: Self.line(next.items[0]))
        case let (pushed?, false): event = Self.differs(pushed, next) ? .update : nil
        }
        guard let event else {
            if let nextCheck {
                try await stores.watchEvents.scheduleLiveActivityCheck(userID: userID, at: nextCheck)
            }
            return true
        }
        let last = state.pushed
        state.pushed = next.items.isEmpty ? nil : next
        state.lingering = lingering
        state.nextCheckAt = nextCheck
        guard try await stores.watchEvents.saveLiveActivityState(state, userID: userID) else { return false }

        try await send(event, saved: state, last: last, userID: userID, now: now)
        return true
    }

    /// Sends a change already saved: to the running activities, or to every device to start one.
    private func send(
        _ event: LiveActivityPush.Event, saved: LiveActivityState, last: NowPlayingActivityState?, userID: UserID,
        now: Date
    ) async throws {
        let next = saved.pushed ?? NowPlayingActivityState(items: [])
        let staleDate = saved.nextCheckAt.map { $0.addingTimeInterval(Self.staleGrace) }
        let running = try await stores.watchEvents.liveActivityUpdateTokens(userID: userID)
        switch event {
        case .start where !running.isEmpty:
            // The app started one itself and handed over its token: update it, start no second.
            await deliver(.update, next, to: running, staleDate: staleDate, now: now)
        case .start:
            try await deliver(
                event, next, to: stores.watchEvents.liveActivityStartTokens(userID: userID),
                staleDate: staleDate, now: now
            )
        case .update:
            await deliver(.update, next, to: running, staleDate: staleDate, now: now)
        case .end:
            await deliver(event, last ?? next, to: running, now: now)
            try await stores.watchEvents.forgetLiveActivityUpdates(userID: userID)
        }
    }

    /// Whether the activity would look different: rows, their order, pause, tick, text or art, or
    /// an end time moved by more than `endTimeSlack`. Not position: the activity runs its own clock.
    static func differs(_ old: NowPlayingActivityState, _ new: NowPlayingActivityState) -> Bool {
        guard old.items.count == new.items.count else { return true }
        return zip(old.items, new.items).contains { before, after in
            var same = before
            same.startedAt = after.startedAt
            same.endsAt = after.endsAt
            same.pausedAt = after.pausedAt
            guard same == after, (before.pausedAt == nil) == (after.pausedAt == nil),
                  (before.endsAt == nil) == (after.endsAt == nil)
            else { return true }
            guard let was = before.endsAt, let will = after.endsAt else { return false }
            return abs(was.timeIntervalSince(will)) > endTimeSlack
        }
    }

    /// "Pluribus · S1 · E2 · Pilot", "Song · Artist".
    static func line(_ item: NowPlayingActivityItem) -> String {
        [item.title, item.subtitle].compactMap(\.self).joined(separator: " · ")
    }

    private func deliver(
        _ event: LiveActivityPush.Event, _ content: NowPlayingActivityState, to tokens: [LiveActivityToken],
        staleDate: Date? = nil, now: Date
    ) async {
        // A start or an end shows at once; a row coming or going waits for a good moment.
        let priority: LiveActivityPush.Priority = switch event {
        case .start, .end: .immediate
        case .update: .considerate
        }
        let push = LiveActivityPush(
            event: event, content: content, staleDate: staleDate, timestamp: now, priority: priority
        )
        for token in tokens {
            let outcome = try? await sender.send(push, to: token)
            Metrics.shared.push("live_activity", outcome)
            switch outcome {
            case .deadToken?: try? await stores.watchEvents.forgetLiveActivity(token: token.token)
            case .sent?, nil: continue
            }
        }
    }
}
