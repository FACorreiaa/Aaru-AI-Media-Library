import Foundation

/// TheSportsDB's premium key allows 100 requests a minute; Aaru paces at 90 with a small burst
/// so a cold Favorites tab fills fast without tripping the 429 (SPT-001).
func makeSportsListing(apiKey: String, _ transport: any HTTPTransport) -> any SportsListing {
    TheSportsDBSports(
        client: ProviderClient(
            name: "thesportsdb", transport: transport, pacer: RequestPacer(requestsPerSecond: 1.5, burst: 10)
        ),
        apiKey: apiKey
    )
}
