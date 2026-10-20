import AaruAPI
import Foundation
import Observation

typealias WatchParty = Components.Schemas.WatchParty

/// GRP-009: a watch channel's party. Every response carries the server's clock, and the
/// countdown runs against it, so every member sees the same second whatever their device says.
@MainActor
@Observable
final class WatchPartyModel {
    private(set) var party: WatchParty?
    private(set) var hasLoaded = false
    /// Server time minus device time, measured at the middle of the last request.
    private(set) var serverOffset: TimeInterval = 0
    private(set) var reactions: [FloatingReaction] = []
    /// The party this user already marked watched, so the button can say so.
    private(set) var markedWatchedID: String?
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored let groupID: String
    @ObservationIgnored let channelID: String

    static let reactionSet = ["😂", "😱", "😭", "❤️", "👏", "🔥"]
    static let reactionLifetime: TimeInterval = 2.5

    struct FloatingReaction: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let name: String
    }

    init(api: Client?, groupID: String, channelID: String) {
        self.api = api
        self.groupID = groupID
        self.channelID = channelID
    }

    private var path: Operations.GetWatchParty.Input.Path {
        .init(groupId: groupID, channelId: channelID)
    }

    /// The server's "now", for the countdown.
    func serverNow(_ date: Date = Date()) -> Date {
        date.addingTimeInterval(serverOffset)
    }

    /// The state as of `date`: a countdown that has run out is live even before the next fetch.
    func state(at date: Date) -> WatchParty.StatePayload? {
        guard let party else { return nil }
        if party.state == .countdown, let startsAt = party.startsAt, startsAt <= serverNow(date) {
            return .live
        }
        return party.state
    }

    // MARK: Reads and writes

    func load() async {
        guard let api else { return }
        await apply("The watch party could not be loaded.") {
            switch try await api.getWatchParty(path: path) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    func open(_ title: Components.Schemas.MediaRef, season: Int?, episode: Int?) async -> Bool {
        guard let api else { return false }
        return await apply("The party was not started.") {
            switch try await api.openWatchParty(
                path: .init(groupId: groupID, channelId: channelID),
                body: .json(.init(title: title, season: season, episode: episode))
            ) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    func setReady(_ ready: Bool) async {
        guard let api else { return }
        await apply("That was not saved.") {
            switch try await api.setWatchPartyReady(
                path: .init(groupId: groupID, channelId: channelID), body: .json(.init(ready: ready))
            ) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    func startCountdown(seconds: Int) async {
        guard let api else { return }
        await apply("The countdown did not start.") {
            switch try await api.startWatchParty(
                path: .init(groupId: groupID, channelId: channelID),
                body: .json(.init(countdownSeconds: seconds))
            ) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    func end() async {
        guard let api else { return }
        await apply("The party did not end.") {
            switch try await api.endWatchParty(path: .init(groupId: groupID, channelId: channelID)) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    /// Ticks the episode, film or book in this user's library only.
    func markWatched() async {
        guard let api, let party else { return }
        problem = nil
        do {
            switch try await api.markWatchPartyWatched(path: .init(groupId: groupID, channelId: channelID)) {
            case .noContent: markedWatchedID = party.id
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That was not marked watched."
            }
        } catch {
            problem = "That was not marked watched. Aaru could not reach the server."
        }
    }

    // MARK: Realtime

    func apply(_ event: RealtimeEvent) async {
        if event._type == .ready {
            await load()
            return
        }
        guard event.channelId == channelID else { return }
        switch event._type {
        case .watch_updated:
            await load()
        case .watch_reaction:
            if let emoji = event.emoji, Self.reactionSet.contains(emoji) {
                show(emoji, from: event.user?.label ?? "Someone")
            }
        default:
            break
        }
    }

    /// A reaction floats for a moment, then goes.
    func show(_ emoji: String, from name: String) {
        let reaction = FloatingReaction(emoji: emoji, name: name)
        reactions.append(reaction)
        if reactions.count > 12 {
            reactions.removeFirst(reactions.count - 12)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.reactionLifetime))
            self?.reactions.removeAll { $0.id == reaction.id }
        }
    }

    // MARK: Plumbing

    /// A party call's answer: the view, or the server's message.
    typealias Answer = (view: Components.Schemas.WatchPartyView?, message: String?)

    /// Runs a call, keeps the party and the server clock. True when it succeeded.
    @discardableResult
    private func apply(_ fallback: String, _ call: () async throws -> Answer) async -> Bool {
        problem = nil
        let sent = Date()
        do {
            let answer = try await call()
            let received = Date()
            guard let view = answer.view else {
                problem = answer.message ?? fallback
                return false
            }
            party = view.party
            let midpoint = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
            serverOffset = view.serverTime.timeIntervalSince(midpoint)
            hasLoaded = true
            return true
        } catch {
            problem = "\(fallback) Aaru could not reach the server."
        }
        return false
    }
}
