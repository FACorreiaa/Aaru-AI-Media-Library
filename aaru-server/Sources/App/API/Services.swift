/// Business services the handlers call. Built once at boot; tests build them over fakes.
struct Services: Sendable {
    var auth: AuthService
    var catalog: CatalogService
    var library: LibraryService

    static func make(stores: Stores, catalogs: CatalogProviders, auth: AuthService) -> Services {
        let catalog = CatalogService(stores: stores, catalogs: catalogs)
        return Services(
            auth: auth,
            catalog: catalog,
            library: LibraryService(
                stores: stores,
                resolver: TitleResolver(stores: stores, catalogs: catalogs),
                catalog: catalog
            )
        )
    }
}
