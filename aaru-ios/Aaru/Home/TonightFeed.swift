import AaruAPI
import Foundation
import Observation

/// Tonight as the server ranks it (AG-005), and what the user set aside since it loaded. Home
/// owns one, as it owns `airingFeed`; `HomeModel.tonight` reads it. The last answer is kept on
/// disk, so Tonight opens offline.
@MainActor
@Observable
final class TonightFeed {
    /// The last answer. `HomeModel.tonight` uses it only on the day it names.
    private(set) var answer: Components.Schemas.Tonight?
    /// Picks set aside here ("Not tonight", "Not for me") since the answer loaded.
    private(set) var hidden: Set<String> = []

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let cache: HomeCache?
    @ObservationIgnored private let timeZone: TimeZone

    init(api: Client?, cache: HomeCache?, timeZone: TimeZone) {
        self.api = api
        self.cache = cache
        self.timeZone = timeZone
        answer = cache?.loadTonight()
    }

    /// Asks again. A failure keeps the last answer; `HomeModel.tonight` falls back to the device
    /// once its day has passed.
    func load() async {
        guard let api,
              case let .ok(response) = try? await api.getTonight(query: .init(tz: timeZone.identifier)),
              let reply = try? response.body.json
        else { return }
        answer = reply
        hidden = []
        cache?.saveTonight(reply)
    }

    /// "Not tonight" hides the pick for the rest of the day; "Not for me" also ranks it lower for
    /// two weeks. The card moves on at once, then Tonight loads again. Returns what went wrong.
    func setAside(_ pick: TonightPick, verdict: TonightVerdict) async -> String? {
        let id = pick.libraryItemId
        guard let api, !hidden.contains(id) else { return nil }
        hidden.insert(id)
        do {
            let output = try await api.sendTonightFeedback(
                path: .init(id: id),
                query: .init(tz: timeZone.identifier),
                body: .json(.init(verdict: verdict))
            )
            switch output {
            case .noContent:
                await load()
                return nil
            case let .default(_, error):
                hidden.remove(id)
                return (try? error.body.json.message) ?? "\(pick.title.title) could not be set aside."
            }
        } catch {
            hidden.remove(id)
            return "\(pick.title.title) could not be set aside. Aaru could not reach the server."
        }
    }
}

extension HomeModel {
    /// Sets a Tonight pick aside; what went wrong shows as Home's problem.
    func setAside(_ pick: TonightPick, verdict: TonightVerdict) async {
        problem = nil
        problem = await tonightFeed.setAside(pick, verdict: verdict)
    }
}
