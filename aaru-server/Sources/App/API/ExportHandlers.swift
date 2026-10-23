import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func exportAccount(_ input: Operations.ExportAccount.Input) async throws -> Operations.ExportAccount.Output {
        let userID = try currentUser()
        guard let profile = try await stores.users.profile(userID) else { throw AppError.unauthorized() }
        let export = try await AccountExport.gather(userID: userID, stores: stores, services: services)
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withFullDate])
        if input.query.format == .csv {
            return .ok(.init(
                headers: .init(contentDisposition: "attachment; filename=\"aaru-library-\(stamp).csv\""),
                body: .csv(HTTPBody(export.csv))
            ))
        }
        let library = export.entries.map { entry -> Components.Schemas.LibraryEntry in
            var dto = Components.Schemas.LibraryEntry(entry)
            dto.watchedEpisodes = export.watched[entry.item.id]?.map { .init(season: $0.season, number: $0.episode) }
            return dto
        }
        async let friends = services.social.friends(userID)
        async let blocked = services.social.blocked(userID)
        async let groups = services.groups.groups(userID)
        async let groupMessages = stores.groups.exportMessages(userID)
        async let listens = services.listens.all(userID: userID)
        async let favorites = FavoriteService.favorites(of: userID, stores: stores)
        return try await .ok(.init(
            headers: .init(contentDisposition: "attachment; filename=\"aaru-export-\(stamp).json\""),
            body: .json(.init(
                exportedAt: Date(),
                account: .init(
                    userId: profile.id.description,
                    displayName: profile.displayName,
                    handle: profile.handle,
                    providers: profile.providers.compactMap { .init(rawValue: $0.rawValue) }
                ),
                library: library,
                lists: export.lists.map { .init(
                    name: $0.list.name,
                    createdAt: $0.list.createdAt,
                    items: $0.titles.map(Components.Schemas.TitleSummary.init)
                ) },
                shelves: export.shelves.map(Components.Schemas.Shelf.init),
                friends: friends.map(Components.Schemas.SocialUser.init),
                blocked: blocked.map(Components.Schemas.SocialUser.init),
                groups: groups.map { .init(name: $0.name, role: .init($0.role)) },
                groupMessages: groupMessages.map {
                    .init(group: $0.group, channel: $0.channel, body: $0.body, createdAt: $0.createdAt)
                },
                listens: listens.map(Components.Schemas.Listen.init),
                favorites: .init(favorites)
            ))
        ))
    }
}
