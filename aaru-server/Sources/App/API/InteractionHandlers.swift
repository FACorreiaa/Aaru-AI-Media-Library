import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// SOC-007 reactions and SOC-006 recommendations.
extension APIImplementation {
    var interactions: InteractionService {
        InteractionService(stores: stores, library: library)
    }

    func setActivityReaction(_ input: Operations.SetActivityReaction.Input) async throws
        -> Operations.SetActivityReaction.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        try await interactions.react(body.emoji.rawValue, on: input.path.id, viewer: currentUser())
        return .noContent(.init())
    }

    func clearActivityReaction(_ input: Operations.ClearActivityReaction.Input) async throws
        -> Operations.ClearActivityReaction.Output
    {
        try await interactions.react(nil, on: input.path.id, viewer: currentUser())
        return .noContent(.init())
    }

    func recommendTitle(_ input: Operations.RecommendTitle.Input) async throws -> Operations.RecommendTitle.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let recipients = try body.to.map { raw in
            guard let id = UUID(uuidString: raw) else { throw SocialService.noSuchUser }
            return UserID(id)
        }
        try await interactions.recommend(
            MediaRef(body.title), note: body.note, to: recipients, viewer: currentUser()
        )
        return .noContent(.init())
    }

    func listRecommendations(_: Operations.ListRecommendations.Input) async throws
        -> Operations.ListRecommendations.Output
    {
        let items = try await interactions.inbox(currentUser()).map { item in
            Components.Schemas.RecommendationItem(
                id: item.recommendation.id.uuidString, from: .init(item.from), title: .init(item.title),
                note: item.recommendation.note, createdAt: item.recommendation.createdAt
            )
        }
        return .ok(.init(body: .json(.init(items: items))))
    }

    func addRecommendation(_ input: Operations.AddRecommendation.Input) async throws
        -> Operations.AddRecommendation.Output
    {
        try await interactions.add(recommendationID(input.path.id), viewer: currentUser())
        return .noContent(.init())
    }

    func dismissRecommendation(_ input: Operations.DismissRecommendation.Input) async throws
        -> Operations.DismissRecommendation.Output
    {
        try await interactions.dismiss(recommendationID(input.path.id), viewer: currentUser())
        return .noContent(.init())
    }

    private func recommendationID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw InteractionService.noSuchRecommendation }
        return id
    }
}
