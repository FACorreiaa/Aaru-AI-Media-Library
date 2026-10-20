import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    /// CAT-020. Signed-in only, though nothing in the answer depends on who asks.
    func getDiscover(_ input: Operations.GetDiscover.Input) async throws -> Operations.GetDiscover.Output {
        _ = try currentUser()
        let ids = input.query.section.map { [DiscoverSectionID(rawValue: $0.rawValue)].compactMap(\.self) }
            ?? DiscoverSectionID.allCases
        let sections = try await services.discover.sections(ids)
        return .ok(.init(body: .json(.init(sections: sections.map(Components.Schemas.DiscoverSection.init)))))
    }
}

extension Components.Schemas.DiscoverSection {
    init(_ section: DiscoverSection) {
        self.init(
            id: .init(rawValue: section.id.rawValue) ?? .trending,
            animeSeason: section.animeSeason.map {
                .init(season: .init(rawValue: $0.name.rawValue) ?? .winter, year: $0.year)
            },
            items: section.items.map(Components.Schemas.CatalogHit.init),
            fetchedAt: section.fetchedAt
        )
    }
}
