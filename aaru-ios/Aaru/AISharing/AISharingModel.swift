import AaruAPI
import Foundation
import Observation

typealias AISharingState = Components.Schemas.AISharing.StatePayload

/// AI sharing (PRV-002): the signed-in user's yes or no to Aaru sending their data to its AI
/// provider, as `Me.aiSharing` has it. One for the whole app: the first run, the full-screen ask,
/// the owl's card, capture, the group composer and Settings all read and change it here. The
/// server holds the rule and refuses every AI call until the answer is `allowed`.
@MainActor
@Observable
final class AISharingModel {
    /// The error code of the 403 an AI call answers until the user has allowed.
    static let requiredCode = "ai_sharing_required"

    /// Nil until `Me` has been read: nothing is asked on a guess.
    private(set) var state: AISharingState?
    /// An answer is on its way to the server.
    private(set) var isSaving = false
    /// Why the last answer was not saved.
    var problem: String?

    @ObservationIgnored private let api: Client?
    /// Bumped by `reset()`, so an answer still in flight says nothing to the next account.
    @ObservationIgnored private var generation = 0

    init(api: Client?) {
        self.api = api
    }

    var isAllowed: Bool {
        state == .allowed
    }

    /// The account is known not to have allowed: an AI surface shows the ask instead of sending.
    var needsAsk: Bool {
        state == .unanswered || state == .declined
    }

    /// `Me` as it was just read. A server that leaves the field out means unanswered.
    func apply(_ account: Components.Schemas.Me) {
        state = account.aiSharing?.state ?? .unanswered
    }

    /// Reads `Me` again. A failed read keeps the last known answer.
    func refresh() async {
        guard let api else { return }
        let started = generation
        guard case let .ok(response)? = try? await api.getMe(),
              let account = try? response.body.json,
              started == generation
        else { return }
        apply(account)
    }

    /// The server answered `ai_sharing_required`: the answer changed somewhere else.
    func serverRefused() {
        if state != .declined {
            state = .unanswered
        }
    }

    /// `PUT /v1/me/ai-sharing`. True once the server has the answer; false with `problem` set.
    @discardableResult
    func set(_ allowed: Bool) async -> Bool {
        guard let api else {
            problem = String(localized: "This build has no server configured.")
            return false
        }
        guard !isSaving else { return false }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        let started = generation
        do {
            switch try await api.setAISharing(body: .json(.init(allowed: allowed))) {
            case let .ok(response):
                let answer = try response.body.json
                guard started == generation else { return false }
                state = answer.state
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? String(localized: "Your answer was not saved.")
            }
        } catch {
            problem = String(localized: "Your answer was not saved. Aaru could not reach the server.")
        }
        return false
    }

    /// Sign-out.
    func reset() {
        generation += 1
        state = nil
        isSaving = false
        problem = nil
    }
}

/// When Aaru asks about AI sharing without being asked to (PRV-002): the pure part.
enum AISharingAsk {
    /// Whether an account that already finished its first run is asked, full screen, as the app
    /// opens. Never on a guess: `onboardingPending` and `state` are nil when `Me` was not read.
    /// An account whose first run ended during this launch is asked the next time the app opens.
    static func asksOnOpen(onboardingPending: Bool?, state: AISharingState?, firstRunEndedThisLaunch: Bool) -> Bool {
        onboardingPending == false && state == .unanswered && !firstRunEndedThisLaunch
    }

    /// Set once this account has answered, so later launches open straight into the app and
    /// read `Me` behind it. Cleared on sign-out: the next account waits for `Me` again.
    private static let answeredKey = "aiSharing.answered"

    static var isKnownAnswered: Bool {
        UserDefaults.standard.bool(forKey: answeredKey)
    }

    static func rememberAnswered() {
        UserDefaults.standard.set(true, forKey: answeredKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: answeredKey)
    }

    /// Whether a group message tags `@aaru`, by the server's rule (`groups.Mentions`): the handle
    /// in any case, not inside a word or an email address.
    static func tagsAaru(_ body: String) -> Bool {
        let inHandle: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        let inWord: (Character) -> Bool = { $0 == "_" || $0 == "@" || $0.isLetter || $0.isNumber }
        var rest = body[...]
        while let mark = rest.firstIndex(of: "@") {
            let after = rest[rest.index(after: mark)...]
            let handle = after.prefix(while: inHandle)
            let follows = after.dropFirst(handle.count).first
            let startsWord = mark == body.startIndex || !inWord(body[body.index(before: mark)])
            if startsWord, handle.lowercased() == "aaru", follows.map(inWord) != true {
                return true
            }
            rest = after.dropFirst(handle.count)
        }
        return false
    }
}
