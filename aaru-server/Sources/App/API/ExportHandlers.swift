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
        return .ok(.init(
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
                shelves: export.shelves.map(Components.Schemas.Shelf.init)
            ))
        ))
    }
}
