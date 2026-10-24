import AaruAPI
import Foundation
import Observation

typealias OnAirGuide = Components.Schemas.DiscoverOnAir
typealias OnAirChannel = Components.Schemas.OnAirChannel
typealias OnAirShow = Components.Schemas.OnAirShow
typealias OnAirEpisode = Components.Schemas.OnAirEpisode

/// The On air view's state (DISC-003): this week's shows by channel, as the server groups and
/// orders them, and adds in flight. Catalog data, the same for every user; the region asked
/// for is the device's, sent per request and never stored.
@MainActor
@Observable
final class OnAirModel {
    private(set) var guide: OnAirGuide?
    private(set) var isLoading = false
    /// The last load failed; shown in place of the guide.
    private(set) var failed = false
    private(set) var adding: Set<String> = []
    /// An add that failed.
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel?

    init(api: Client?, library: LibraryModel?) {
        self.api = api
        self.library = library
    }

    /// For previews: a guide in place, nothing to fetch.
    convenience init(preview guide: OnAirGuide) {
        self.init(api: nil, library: nil)
        self.guide = guide
    }

    func loadIfNeeded() async {
        guard guide == nil else { return }
        await load()
    }

    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            switch try await api.getDiscoverOnAir(query: .init(region: Self.region())) {
            case let .ok(response):
                guide = try response.body.json
            case .default:
                failed = true
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            failed = true
        }
    }

    func libraryItemID(_ hit: CatalogHit) -> String? {
        hit.libraryItemId ?? library?.entry(matching: hit)?.id
    }

    /// Adds a show with a status, as Discover's rows do.
    func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard let api, let library, !adding.contains(hit.id) else { return }
        problem = nil
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        problem = await library.add(hit, status: status, api: api)
    }

    /// The device's region as two letters, or nil (a numeric region such as "150" has none).
    static func region(_ locale: Locale = .current) -> String? {
        guard let code = locale.region?.identifier.uppercased(),
              code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return code
    }

    /// "S2 E5 · Thu 9:00 PM", or "S2 E5 · Thu, Oct 22" while only the day is known. The day is the
    /// viewer's for an exact time and the listed (UTC) day otherwise, as on the calendar.
    static func episodeLine(
        _ episode: OnAirEpisode, timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let style = Date.FormatStyle(
            locale: locale, timeZone: episode.airTimeKnown ? timeZone : TimeZone(identifier: "UTC") ?? .gmt
        )
        let when = episode.airTimeKnown
            ? episode.airsAt.formatted(style.weekday(.abbreviated).hour().minute())
            : episode.airsAt.formatted(style.weekday(.abbreviated).day().month(.abbreviated))
        return "S\(episode.season) E\(episode.number) · \(when)"
    }

    /// "Also on Hulu and Max", or nil with nothing to list.
    static func streamsLine(_ show: OnAirShow) -> String? {
        let names = (show.streamsOn ?? []).map(\.name)
        return names.isEmpty ? nil : "Also on \(names.formatted(.list(type: .and)))"
    }

    /// "1 show", "4 shows".
    static func count(_ channel: OnAirChannel) -> String {
        channel.shows.count == 1 ? "1 show" : "\(channel.shows.count) shows"
    }
}
