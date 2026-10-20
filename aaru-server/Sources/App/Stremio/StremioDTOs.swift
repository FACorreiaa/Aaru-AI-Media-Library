import Foundation

// The Stremio addon protocol's response shapes (github.com/Stremio/stremio-addon-sdk/docs).
// Encoded as Stremio expects; nothing here leaves the Stremio adapter.

struct StremioManifest: Encodable, Sendable {
    struct Resource: Encodable, Sendable {
        var name: String
        var types: [String]
        var idPrefixes: [String]?
    }

    struct Catalog: Encodable, Sendable {
        struct Extra: Encodable, Sendable {
            var name: String
        }

        var type: String
        var id: String
        var name: String
        var extra: [Extra]?
    }

    struct BehaviorHints: Encodable, Sendable {
        var configurable: Bool
        var configurationRequired: Bool
    }

    var id: String
    var version: String
    var name: String
    var description: String
    var logo: String?
    var resources: [Resource]
    var types: [String]
    var idPrefixes: [String]
    var catalogs: [Catalog]
    var behaviorHints: BehaviorHints
}

struct StremioMetaPreview: Encodable, Sendable, Equatable {
    var id: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var description: String?
    var releaseInfo: String?
}

struct StremioCatalogResponse: Encodable, Sendable {
    var metas: [StremioMetaPreview]
}

struct StremioMeta: Encodable, Sendable {
    struct Video: Encodable, Sendable {
        var id: String
        var title: String
        var season: Int
        var episode: Int
        var released: String
        var thumbnail: String?
        var overview: String?
    }

    var id: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var description: String?
    var releaseInfo: String?
    var videos: [Video]?
}

struct StremioMetaResponse: Encodable, Sendable {
    var meta: StremioMeta
}

/// The body of an error or an event acknowledgement; Stremio ignores event bodies.
struct StremioMessage: Encodable, Sendable {
    var err: String?
}
