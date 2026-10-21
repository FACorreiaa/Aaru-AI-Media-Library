import Foundation

/// The "Concerts near" city picker: a few lookups a user, only while they type (MUS-003).
func makePlaceSearch(_ transport: any HTTPTransport) -> any PlaceSearching {
    OpenMeteoPlaces(client: ProviderClient(
        name: "open-meteo", transport: transport, pacer: RequestPacer(requestsPerSecond: 2, burst: 5)
    ))
}

/// Ticketmaster allows five requests a second and 5,000 a day (MUS-003).
func makeConcertListing(apiKey: String, _ transport: any HTTPTransport) -> any ConcertListing {
    TicketmasterConcerts(
        client: ProviderClient(
            name: "ticketmaster", transport: transport, pacer: RequestPacer(requestsPerSecond: 4, burst: 4)
        ),
        apiKey: apiKey,
        budget: CallBudget(limit: 4500)
    )
}
