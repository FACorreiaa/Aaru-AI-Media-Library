import AaruCore
import Foundation

/// Open Library adapter (CAT-003): book search and detail, ISBN normalized to ISBN-13,
/// cover URLs referenced, never downloaded.
struct OpenLibraryCatalog: CatalogSearching {
    static let baseURL = URL(string: "https://openlibrary.org")!
    static let fields = "key,title,first_publish_year,isbn,cover_i,author_name"

    let client: ProviderClient
    /// Open Library asks API users to identify themselves.
    let userAgent: String

    func search(query: String, type _: MediaType) async throws -> [CatalogHit] {
        let page = try await get(SearchPage.self, "search.json", ["q": query, "fields": Self.fields, "limit": "20"])
        return page.docs.compactMap(\.hit)
    }

    func hydrate(ids: ExternalIDs, type _: MediaType) async throws -> CatalogTitle? {
        let query: [String: String]
        if let work = ids.openLibrary {
            query = ["q": "key:/works/\(work)", "fields": Self.fields, "limit": "1"]
        } else if let isbn = ids.isbn.flatMap(ISBN.normalize) {
            query = ["isbn": isbn, "fields": Self.fields, "limit": "1"]
        } else {
            return nil
        }
        guard var hit = try await get(SearchPage.self, "search.json", query).docs.first?.hit else { return nil }
        // Keep the ISBN that resolved it: it is the key a later import will look up.
        if let isbn = ids.isbn.flatMap(ISBN.normalize) {
            hit.ids.isbn = isbn
        }
        hit.ids = hit.ids.filling(from: ids)
        return CatalogTitle(hit: hit, status: nil, runtimeMinutes: nil)
    }

    private func get<T: Decodable>(_: T.Type, _ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw ProviderError(provider: "openlibrary", kind: .malformed) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try await client.decode(
            T.self,
            OutboundRequest(url: url, headers: [("User-Agent", userAgent), ("Accept", "application/json")]),
            decoder: decoder
        )
    }
}

private struct SearchPage: Decodable {
    struct Doc: Decodable {
        let key: String
        let title: String?
        let firstPublishYear: Int?
        let isbn: [String]?
        let coverI: Int?
        let authorName: [String]?

        var hit: CatalogHit? {
            guard let title = title?.nilIfBlank, key.hasPrefix("/works/") else { return nil }
            return CatalogHit(
                type: .book,
                title: title,
                originalTitle: nil,
                year: firstPublishYear,
                posterURL: coverI.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") },
                overview: nil,
                byline: authorName.map { $0.prefix(3).joined(separator: ", ") },
                ids: ExternalIDs(
                    isbn: isbn?.lazy.compactMap(ISBN.normalize).first,
                    openLibrary: String(key.dropFirst("/works/".count))
                ),
                isAnime: false
            )
        }
    }

    let docs: [Doc]
}
