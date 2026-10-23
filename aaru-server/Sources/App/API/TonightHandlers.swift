import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getTonight(_ input: Operations.GetTonight.Input) async throws -> Operations.GetTonight.Output {
        let tonight = try await services.tonight.tonight(userID: currentUser(), timeZone: input.query.tz)
        return .ok(.init(body: .json(.init(tonight))))
    }

    func sendTonightFeedback(
        _ input: Operations.SendTonightFeedback.Input
    ) async throws -> Operations.SendTonightFeedback.Output {
        guard let id = UUID(uuidString: input.path.id) else { throw AppError.notFound("No such library item.") }
        guard case let .json(body) = input.body else { throw AppError.notFound() }
        let verdict: TonightVerdict = switch body.verdict {
        case .rejected: .rejected
        case .notTonight: .notTonight
        }
        try await services.tonight.feedback(
            itemID: LibraryItemID(id), verdict: verdict, userID: currentUser(), timeZone: input.query.tz
        )
        return .noContent(.init())
    }
}

extension Components.Schemas.Tonight {
    init(_ tonight: Tonight) {
        self.init(day: tonight.day.description, picks: tonight.picks.map(Components.Schemas.TonightPick.init))
    }
}

extension Components.Schemas.TonightPick {
    init(_ pick: TonightPick) {
        self.init(
            libraryItemId: pick.libraryItemID.description,
            title: .init(pick.title),
            kind: .init(rawValue: pick.kind.rawValue) ?? ._continue,
            episode: pick.episode.map { .init(season: $0.season, number: $0.episode) },
            episodeName: pick.episodeName,
            minutes: pick.minutes,
            airsAt: pick.airsAt,
            airTimeKnown: pick.airTimeKnown,
            reason: pick.reason
        )
    }
}
