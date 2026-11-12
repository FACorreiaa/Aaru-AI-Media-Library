import AaruAPI
import Foundation
import Observation

typealias WatchParty = Components.Schemas.WatchParty

/// What a new party is for, beside its title: a show's episode, a manga's chapter and volume, or
/// a book's page (ROOM-005).
struct PartyTarget: Equatable {
    var season: Int?
    var episode: Int?
    var chapter: Int?
    var volume: Int?
    var page: Int?
}

extension WatchParty {
    /// A book or manga makes the party a reading session.
    var isReading: Bool {
        title._type == .book || title._type == .manga
    }

    /// The UI's word for a Room: "Watch party", or "Reading session" for a book or manga.
    var word: String {
        isReading ? String(localized: "Reading session") : String(localized: "Watch party")
    }

    /// What the party is aimed at: "S1 · E3", "Chapter 12 · Vol. 2", "Page 120", or nothing.
    var targetText: String? {
        if let season, let episode {
            return EpisodeCode.text(season: season, episode: episode)
        }
        let parts = [
            chapter.map { String(localized: "Chapter \(String($0))") },
            volume.map { String(localized: "Vol. \(String($0))") },
            page.map { String(localized: "Page \(String($0))") },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The tap for a member the end does not mark, in the kind's own verb.
    var markLabel: String {
        if isReading {
            return String(localized: "Mark read for me")
        }
        return title
            ._type == .album ? String(localized: "Mark listened for me") : String(localized: "Mark watched for me")
    }
}

/// GRP-009, ROOM-005: a watch channel's party. Every response carries the server's clock, and the
/// countdown runs against it, so every member sees the same second whatever their device says.
/// Being ready is joining: when the host ends, the server marks the title for everyone who joined
/// and left "Mark it for me" on, and this model holds the user's own side of that.
@MainActor
@Observable
final class WatchPartyModel {
    private(set) var party: WatchParty?
    private(set) var hasLoaded = false
    /// Server time minus device time, measured at the middle of the last request.
    private(set) var serverOffset: TimeInterval = 0
    private(set) var reactions: [FloatingReaction] = []
    /// This user's "Mark it for me": the end of the party marks the title for them.
    private(set) var autoMark = true
    /// The party marked its title in this user's library, at its end or by their tap.
    private(set) var markedForMe = false
    /// The action that marked it, for Undo; nil when the library already said so.
    private(set) var actionID: String?
    /// The action this user took back here, so the panel says "Undone" instead of offering it again.
    private(set) var undoneActionID: String?
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
        await apply(String(localized: "The watch party could not be loaded.")) {
            switch try await api.getWatchParty(path: path) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    func open(_ title: Components.Schemas.MediaRef, target: PartyTarget) async -> Bool {
        guard let api else { return false }
        return await apply(String(localized: "The party was not started.")) {
            switch try await api.openWatchParty(
                path: .init(groupId: groupID, channelId: channelID),
                body: .json(.init(
                    title: title, season: target.season, episode: target.episode,
                    chapter: target.chapter, volume: target.volume, page: target.page
                ))
            ) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    /// Joins or leaves. A nil `autoMark` keeps what this user chose; a first join starts with it on.
    func setReady(_ ready: Bool, autoMark: Bool? = nil) async {
        guard let api else { return }
        await apply(String(localized: "That was not saved.")) {
            switch try await api.setWatchPartyReady(
                path: .init(groupId: groupID, channelId: channelID),
                body: .json(.init(ready: ready, autoMark: autoMark))
            ) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    func startCountdown(seconds: Int) async {
        guard let api else { return }
        await apply(String(localized: "The countdown did not start.")) {
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
        await apply(String(localized: "The party did not end.")) {
            switch try await api.endWatchParty(path: .init(groupId: groupID, channelId: channelID)) {
            case let .ok(response): try (response.body.json, nil)
            case let .default(_, error): (nil, try? error.body.json.message)
            }
        }
    }

    /// Marks the episode, chapter, page, film or book in this user's library only: the tap for
    /// someone who switched "Mark it for me" off or did not join.
    func markWatched() async {
        guard let api, party != nil else { return }
        problem = nil
        do {
            switch try await api.markWatchPartyWatched(path: .init(groupId: groupID, channelId: channelID)) {
            case .noContent:
                markedForMe = true
                await load()
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? String(localized: "That was not marked.")
            }
        } catch {
            problem = String(localized: "That was not marked. Aaru could not reach the server.")
        }
    }

    /// Takes back what the party marked for this user: their own action, nobody else's.
    func undo() async {
        guard let api, let actionID else { return }
        problem = nil
        do {
            switch try await api.undoAction(path: .init(id: actionID)) {
            case .ok:
                undoneActionID = actionID
                Task { try? await WidgetSync.refresh(api: api) }
            case let .default(status, error):
                if status == 409 {
                    // Already taken back, here or in History.
                    undoneActionID = actionID
                } else {
                    problem = (try? error.body.json.message) ?? String(localized: "That could not be undone.")
                }
            }
        } catch {
            problem = String(localized: "That could not be undone. Aaru could not reach the server.")
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
                show(emoji, from: event.user?.label ?? String(localized: "Someone"))
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
            autoMark = view.autoMark
            markedForMe = view.markedForYou
            actionID = view.actionId
            let midpoint = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
            serverOffset = view.serverTime.timeIntervalSince(midpoint)
            hasLoaded = true
            return true
        } catch {
            problem = String(localized: "\(fallback) Aaru could not reach the server.")
        }
        return false
    }
}
