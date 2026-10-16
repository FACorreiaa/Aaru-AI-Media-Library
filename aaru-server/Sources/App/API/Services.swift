/// Business services the handlers call. Built once at boot; tests build them over fakes.
struct Services: Sendable {
    var auth: AuthService
    var catalog: CatalogService
    var library: LibraryService
    var lists: ListService
    var shelves: ShelfService
    var schedule: ScheduleService
    var imports: ImportService
    var traktConnect: TraktConnectService

    /// `trakt` is nil when Trakt is not configured; connect then answers 503.
    static func make(
        stores: Stores,
        catalogs: CatalogProviders,
        auth: AuthService,
        trakt: TraktAPI? = nil
    ) -> Services {
        let catalog = CatalogService(stores: stores, catalogs: catalogs)
        let resolver = TitleResolver(stores: stores, catalogs: catalogs)
        let library = LibraryService(stores: stores, resolver: resolver, catalog: catalog)
        return Services(
            auth: auth,
            catalog: catalog,
            library: library,
            lists: ListService(stores: stores, resolver: resolver),
            shelves: ShelfService(stores: stores, library: library),
            schedule: ScheduleService(stores: stores, catalog: catalog),
            imports: ImportService(
                stores: stores, resolver: resolver,
                trakt: trakt.map { TraktImport(connect: traktConnect(stores, $0), importer: TraktImporter(api: $0)) },
                anilistLists: catalogs.anilist as? any AniListListReading
            ),
            traktConnect: traktConnect(stores, trakt)
        )
    }

    private static func traktConnect(_ stores: Stores, _ api: TraktAPI?) -> TraktConnectService {
        TraktConnectService(stores: stores, settings: api?.settings, api: api)
    }
}
