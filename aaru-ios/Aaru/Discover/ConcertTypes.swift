import AaruAPI
import Foundation

typealias Concert = Components.Schemas.Concert
typealias ConcertPlace = Components.Schemas.ConcertPlace
typealias ConcertPage = Components.Schemas.ConcertPage
typealias ArtistConcerts = Components.Schemas.ArtistConcerts
typealias ConcertRadius = Components.Schemas.ConcertsNearRequest.RadiusKmPayload
typealias ConcertSearchScope = Components.Schemas.ConcertSearchScope
typealias ConcertPerformer = Components.Schemas.ConcertPerformer

/// The artist the Near list is narrowed to (MUS-010): one performer picked from the provider's
/// list, or every event matching the name.
struct ArtistSearch: Hashable {
    var name: String
    var performerID: String?
}

/// The performers offered for a submitted name, before one is picked.
enum PerformerChoices: Equatable {
    case loading(String)
    case ready(String, [ConcertPerformer])
}

/// A point to look for concerts around, rounded to two decimals (about a kilometre). "Use my
/// location" keeps one in memory for this visit only: it is never saved, here or on the server.
struct ConcertPoint: Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }
}

extension ConcertPlace {
    /// "Lisboa, Lisbon, Portugal": the parts there are, each once.
    var label: String {
        [name, detail].compactMap(\.self).joined(separator: ", ")
    }

    /// A row's identity in the city picker: name and point, compact.
    var key: String {
        "\(name)|\(latitude)|\(longitude)"
    }

    /// "Lisbon, Portugal", or nil when the place has nothing past its name.
    var detail: String? {
        let parts = [region, country].compactMap(\.self).filter { !$0.isEmpty && $0 != name }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension ConcertRadius {
    /// "50 km": the API's unit, the same in every locale.
    var label: String {
        "\(rawValue) km"
    }

    var spoken: String {
        "\(rawValue) kilometres"
    }
}
