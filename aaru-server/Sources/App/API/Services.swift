/// Business services the handlers call. Built once at boot; tests build them over fakes.
struct Services: Sendable {
    var auth: AuthService
    var catalog: CatalogService
    var library: LibraryService
    var lists: ListService
    var shelves: ShelfService
    var schedule: ScheduleService

    static func make(stores: Stores, catalogs: CatalogProviders, auth: AuthService) -> Services {
        let catalog = CatalogService(stores: stores, catalogs: catalogs)
        let resolver = TitleResolver(stores: stores, catalogs: catalogs)
        let library = LibraryService(stores: stores, resolver: resolver, catalog: catalog)
        return Services(
            auth: auth,
            catalog: catalog,
            library: library,
            lists: ListService(stores: stores, resolver: resolver),
            shelves: ShelfService(stores: stores, library: library),
            schedule: ScheduleService(stores: stores, catalog: catalog)
        )
    }
}
