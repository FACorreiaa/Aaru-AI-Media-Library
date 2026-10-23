import AaruAPI
import Foundation

// MARK: Discover

extension HomeModel {
    /// The library item a Discover hit opens: the server's mark, else a match on the shelf
    /// (it may have been added since the rows loaded).
    func libraryItemID(_ hit: CatalogHit) -> String? {
        hit.libraryItemId ?? library?.entry(matching: hit)?.id
    }

    /// Adds a Discover hit with a status, as search does. The card turns into a link to it (the
    /// shelf now has it), and the revision bump reloads Home once.
    func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard let api, let library, !adding.contains(hit.id) else { return }
        problem = nil
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        problem = await library.add(hit, status: status, api: api)
    }
}
