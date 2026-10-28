import AaruAPI
import Foundation

// MARK: Discover

extension HomeModel {
    /// Discover rows Home shows; the rest wait on the Discover tab.
    nonisolated static let discoverLimit = 3

    /// Home's few Discover rows, by the kinds the user keeps (2026-10-28).
    var discoverHere: [DiscoverRow] {
        Self.pickDiscover(discover, kinds: library?.rows.map(\.kind) ?? [])
    }

    /// The first row of each kind the user keeps most, then more of those kinds, then any row,
    /// up to `discoverLimit`. The main kind leads; an empty library takes the first rows. It
    /// picks which public rows show, never what is in them. Matches the web's `homeDiscover`.
    nonisolated static func pickDiscover(_ rows: [DiscoverRow], kinds: [MediaKind]) -> [DiscoverRow] {
        // Discover names albums "album"; ties keep the order the kinds first appear in.
        var counts: [String: Int] = [:]
        var seen: [String] = []
        for kind in kinds {
            let name = kind == .music ? "album" : kind.rawValue
            if counts[name] == nil {
                seen.append(name)
            }
            counts[name, default: 0] += 1
        }
        let ranked = seen.enumerated().sorted { first, second in
            let (one, two) = (counts[first.element, default: 0], counts[second.element, default: 0])
            return one == two ? first.offset < second.offset : one > two
        }
        .map(\.element)
        let shown = rows.filter { !$0.items.isEmpty }
        var picked: [DiscoverRow] = []
        func pick(_ row: DiscoverRow?) {
            guard let row, picked.count < discoverLimit, !picked.contains(where: { $0.id == row.id }) else { return }
            picked.append(row)
        }
        for kind in ranked {
            pick(shown.first { $0.kind.rawValue == kind })
        }
        for row in shown where counts[row.kind.rawValue] != nil {
            pick(row)
        }
        for row in shown {
            pick(row)
        }
        return picked
    }

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
