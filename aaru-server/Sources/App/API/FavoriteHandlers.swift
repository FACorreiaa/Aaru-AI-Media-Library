import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// FAV-001: a top 10 per kind, set in Settings and shown on the profile.
extension APIImplementation {
    var favorites: FavoriteService {
        FavoriteService(stores: stores, resolver: services.lists.resolver)
    }

    func getMyFavorites(_: Operations.GetMyFavorites.Input) async throws -> Operations.GetMyFavorites.Output {
        let favorites = try await favorites.favorites(of: currentUser())
        return .ok(.init(body: .json(.init(favorites))))
    }

    func setMyFavorites(_ input: Operations.SetMyFavorites.Input) async throws -> Operations.SetMyFavorites.Output {
        guard case let .json(body) = input.body, let kind = FavoriteKind(rawValue: input.path.kind.rawValue)
        else { throw AppError.badRequest() }
        let saved = try await favorites.replace(kind, with: body.items.map(MediaRef.init), user: currentUser())
        return .ok(.init(body: .json(.init(saved))))
    }
}

extension Components.Schemas.Favorites {
    init(_ favorites: Favorites) {
        func row(_ kind: FavoriteKind) -> [Components.Schemas.TitleSummary] {
            favorites[kind].map(Components.Schemas.TitleSummary.init)
        }
        self.init(
            film: row(.film), show: row(.show), anime: row(.anime), manga: row(.manga), book: row(.book),
            album: row(.album)
        )
    }
}
