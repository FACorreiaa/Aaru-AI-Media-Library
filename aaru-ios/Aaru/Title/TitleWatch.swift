import AaruAPI
import SwiftUI

typealias TitleWatchPlaces = Components.Schemas.TitleWatch
typealias WatchService = Components.Schemas.WatchProvider

/// One group of services under its heading.
struct WatchGroup: Identifiable, Equatable {
    enum Kind: String { case stream, rent, buy }

    let kind: Kind
    let services: [WatchService]

    var id: Kind {
        kind
    }

    /// "Stream: Netflix and Max", for VoiceOver.
    var spoken: String {
        "\(String(localized: label)): \(services.map(\.name).formatted(.list(type: .and)))"
    }

    var label: LocalizedStringResource {
        switch kind {
        case .stream: "Stream"
        case .rent: "Rent"
        case .buy: "Buy"
        }
    }
}

/// CAT-014: where a film or show can be watched in the device's region, as the server lists it
/// (JustWatch data through TMDB). The region is sent per request and never stored. A failed read,
/// a region with no data and a kind that is not watched all leave nothing: the section is absent.
@MainActor
@Observable
final class TitleWatchModel {
    private(set) var places: TitleWatchPlaces?
    @ObservationIgnored let api: Client?
    @ObservationIgnored let titleID: String

    init(api: Client?, titleID: String, places: TitleWatchPlaces? = nil) {
        self.api = api
        self.titleID = titleID
        self.places = places
    }

    /// The groups that have a service, streaming first. Empty: the section is not shown.
    var groups: [WatchGroup] {
        Self.groups(places)
    }

    static func groups(_ places: TitleWatchPlaces?) -> [WatchGroup] {
        guard let places else { return [] }
        return [
            WatchGroup(kind: .stream, services: places.streaming),
            WatchGroup(kind: .rent, services: places.rent),
            WatchGroup(kind: .buy, services: places.buy),
        ].filter { !$0.services.isEmpty }
    }

    /// TMDB's page of every way to watch the title in the region. There is no link per service.
    var link: URL? {
        places?.link.flatMap(URL.init(string:))
    }

    /// Only films, shows and anime are watched; a device with no two-letter region asks nothing.
    static func asks(kind: MediaKind, region: String?) -> Bool {
        region != nil && [.film, .show, .anime].contains(kind)
    }

    func load(kind: MediaKind, region: String? = OnAirModel.region()) async {
        guard let api, let region, Self.asks(kind: kind, region: region) else { return }
        do {
            guard case let .ok(response) = try await api.getTitleWatch(
                path: .init(id: titleID), query: .init(region: region)
            ) else { return }
            places = try response.body.json
        } catch {
            return
        }
    }
}

/// The title room's "Where to watch" section. Aaru plays nothing: the button opens TMDB's page.
struct TitleWatch: View {
    let kind: MediaKind
    @State private var model: TitleWatchModel
    @Environment(\.openURL) private var openURL

    init(api: Client?, titleID: String, kind: MediaKind, places: TitleWatchPlaces? = nil) {
        self.kind = kind
        _model = State(initialValue: TitleWatchModel(api: api, titleID: titleID, places: places))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if !model.groups.isEmpty {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Where to watch").eyebrow()
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if let link = model.link {
                            Button("All options", systemImage: "arrow.up.right") { openURL(link) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityHint("Opens TMDB in your browser")
                        }
                    }
                    ForEach(model.groups) { group in
                        VStack(alignment: .leading, spacing: AaruSpace.small) {
                            Text(group.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.muted))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AaruSpace.small) {
                                    ForEach(group.services, id: \.name) { service in
                                        WatchServiceChip(service: service)
                                    }
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(group.spoken))
                    }
                    Text("Streaming data from JustWatch")
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                }
                .panel()
            }
        }
        .task { await model.load(kind: kind) }
    }
}

/// One service: its logo, when the provider has one, and its name.
private struct WatchServiceChip: View {
    let service: WatchService

    var body: some View {
        HStack(spacing: AaruSpace.small) {
            if let url = service.logoUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color(.line)
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            }
            Text(service.name)
                .font(.callout)
                .foregroundStyle(Color(.ink))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .overlay { Capsule().strokeBorder(Color(.line), lineWidth: 1) }
    }
}

#Preview("Where to watch") {
    TitleWatch(
        api: nil, titleID: "preview", kind: .film,
        places: .init(
            region: "PT",
            streaming: [.init(name: "Netflix"), .init(name: "Max")],
            rent: [.init(name: "Apple TV")],
            buy: [],
            link: "https://www.themoviedb.org/movie/603/watch?locale=PT"
        )
    )
    .padding()
    .background(Color(.paper))
}
