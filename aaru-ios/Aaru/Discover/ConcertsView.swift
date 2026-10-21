import MapKit
import SwiftUI

/// Discover's Concerts view (MUS-003): "Your artists on tour", then concerts near the saved
/// city or near the viewer once, within 25, 50 or 100 km, as a date-led list or a map of the
/// searched area. Tickets open Ticketmaster; Aaru sells nothing. On the Mac the radius and the
/// List/Map switch sit in the toolbar, as Discover's own switch does.
struct ConcertsView: View {
    @Bindable var model: ConcertsModel

    @State private var choosesCity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ArtistsOnTourSection(model: model)
                NearSection(model: model) { choosesCity = true }
                Label("Concerts from Ticketmaster", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .task { await model.appear() }
        .task(id: model.query) { await model.loadNear() }
        .refreshable { await model.reload() }
        .sheet(isPresented: $choosesCity) {
            ConcertPlacePicker(model: model)
        }
        #if os(macOS)
        .toolbar {
            if model.nearState != .noPlace {
                ToolbarItemGroup {
                    RadiusPicker(radius: $model.radius).fixedSize()
                    LayoutPicker(layout: $model.layout).fixedSize()
                }
            }
        }
        #endif
    }
}

// MARK: Your artists on tour

private struct ArtistsOnTourSection: View {
    let model: ConcertsModel

    @State private var showsAll = false

    private static let firstCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConcertsHeader(title: "Your artists on tour")
            if let artists = model.artists {
                if artists.unavailable, artists.items.isEmpty {
                    QuietNote("Ticketmaster isn't answering right now.")
                } else if artists.items.isEmpty {
                    QuietNote(emptyText(artists))
                } else {
                    let items = showsAll ? artists.items : Array(artists.items.prefix(Self.firstCount))
                    ForEach(items, id: \.id) { concert in
                        ConcertRow(concert: concert)
                    }
                    if artists.items.count > Self.firstCount {
                        Button(showsAll ? "Show fewer" : "Show all \(artists.items.count)") {
                            showsAll.toggle()
                        }
                        .buttonStyle(.borderless)
                    }
                    if artists.pending > 0 {
                        QuietNote("Checking \(Self.artistCount(artists.pending, more: true)) — back within the hour")
                    }
                }
            } else if model.artistsFailed {
                HStack(spacing: 12) {
                    QuietNote("Your artists' concerts could not be loaded.")
                    Button("Try again", action: retry)
                        .buttonStyle(.borderless)
                }
            } else {
                PlaceholderRows(count: 2, label: "Loading your artists' concerts")
            }
        }
    }

    private func retry() {
        Task { await model.loadArtists(force: true) }
    }

    private func emptyText(_ artists: ArtistConcerts) -> String {
        if artists.pending > 0 {
            return "Checking \(Self.artistCount(artists.pending, more: false)) — back within the hour"
        }
        if artists.matched == 0 {
            return "When an artist of an album on your shelf tours, the dates show here."
        }
        return "None of your artists has a date announced."
    }

    /// "1 artist", "4 more artists".
    private static func artistCount(_ count: Int, more: Bool) -> String {
        "\(count.formatted()) \(more ? "more " : "")\(count == 1 ? "artist" : "artists")"
    }
}

// MARK: Near

private struct NearSection: View {
    @Bindable var model: ConcertsModel
    let onChooseCity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NearHeader(model: model, onChooseCity: onChooseCity)
            #if os(iOS)
                if model.nearState != .noPlace {
                    HStack(spacing: 12) {
                        RadiusPicker(radius: $model.radius)
                        LayoutPicker(layout: $model.layout).fixedSize()
                    }
                }
            #endif
            switch model.nearState {
            case .idle, .loading:
                PlaceholderRows(count: 4, label: "Loading concerts")
            case .noPlace:
                ContentUnavailableView {
                    Label("Where should Aaru look?", systemImage: "mappin.and.ellipse")
                } description: {
                    Text("Choose a city to keep, or use your approximate location once.")
                } actions: {
                    Button("Choose a city", action: onChooseCity)
                        .buttonStyle(.borderedProminent)
                    Button(model.isLocating ? "Locating…" : "Use my location", action: useMyLocation)
                        .buttonStyle(.bordered)
                        .disabled(model.isLocating)
                }
            case .failed:
                ContentUnavailableView {
                    Label("Concerts could not be loaded", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Try again", action: retry)
                        .buttonStyle(.bordered)
                }
            case .loaded:
                NearResults(model: model)
            }
        }
    }

    private func useMyLocation() {
        Task { await model.useMyLocation() }
    }

    private func retry() {
        Task { await model.loadNear(force: true) }
    }
}

/// "Near Lisboa ⌄", which opens the city picker, and the switch between the city and the
/// viewer's approximate location.
private struct NearHeader: View {
    let model: ConcertsModel
    let onChooseCity: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onChooseCity) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    ConcertsHeader(title: model.nearTitle)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.muted))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.nearTitle)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Choose the city to look around.")
            Spacer(minLength: 0)
            if model.usesLocation, let place = model.savedPlace {
                Button("Use \(place.name)", systemImage: "building.2", action: model.useSavedPlace)
                    .buttonStyle(.borderless)
            } else if model.nearState != .noPlace {
                Button(model.isLocating ? "Locating…" : "Use my location", systemImage: "location", action: locate)
                    .buttonStyle(.borderless)
                    .disabled(model.isLocating)
            }
        }
    }

    private func locate() {
        Task { await model.useMyLocation() }
    }
}

/// The Near list once loaded: Ticketmaster's silence, nothing in range, or the concerts (under
/// the map when Map is on), with Show more.
private struct NearResults: View {
    let model: ConcertsModel

    var body: some View {
        let items = model.nearItems
        if model.nearUnavailable {
            ContentUnavailableView {
                Label("Ticketmaster isn't answering right now", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Try again in a few minutes.")
            } actions: {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        } else {
            if model.layout == .map, let centre = model.centre {
                ConcertsMap(name: centre.name, point: centre.point, radiusKm: model.radius.rawValue)
            }
            if items.isEmpty {
                ContentUnavailableView(
                    "No concerts within \(model.radius.label)",
                    systemImage: "music.mic",
                    description: Text(model.radius == ._100 ? "Nothing is listed yet." : "Try a wider radius.")
                )
            } else {
                ForEach(items, id: \.id) { concert in
                    ConcertRow(concert: concert, compact: model.layout == .map)
                }
                if model.hasMore {
                    Button(model.isLoadingMore ? "Loading…" : "Show more", action: loadMore)
                        .buttonStyle(.bordered)
                        .disabled(model.isLoadingMore)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func retry() {
        Task { await model.loadNear(force: true) }
    }

    private func loadMore() {
        Task { await model.loadMore() }
    }
}

// MARK: Map

/// The searched area: its centre and the radius as a circle. Ticketmaster gives no venue
/// positions, so the concerts are listed under it rather than pinned on it.
private struct ConcertsMap: View {
    let name: String
    let point: ConcertPoint
    let radiusKm: Int

    @ScaledMetric(relativeTo: .body) private var height = 240

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private var region: MKCoordinateRegion {
        let span = CLLocationDistance(radiusKm) * 1000 * 2.4
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            MapCircle(center: coordinate, radius: CLLocationDistance(radiusKm) * 1000)
                .foregroundStyle(Color.accentColor.opacity(0.15))
                .stroke(Color.accentColor, lineWidth: 2)
            Marker(name, systemImage: "music.note", coordinate: coordinate)
                .tint(Color.accentColor)
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 10))
        // A new centre or radius frames the map again.
        .id([point.latitude, point.longitude, Double(radiusKm)])
        .accessibilityElement()
        .accessibilityLabel("Map of the \(radiusKm) kilometre area around \(name)")
    }
}

// MARK: Pieces

/// A section's title, in the display serif like Home's rows.
private struct ConcertsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .foregroundStyle(Color(.ink))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct QuietNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color(.muted))
    }
}

/// Still placeholder rows while concerts load: redacted, nothing shimmers.
private struct PlaceholderRows: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ConcertRow.placeholders.prefix(count), id: \.id) { concert in
                ConcertRow(concert: concert)
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

private struct RadiusPicker: View {
    @Binding var radius: ConcertRadius

    var body: some View {
        Picker("Radius", selection: $radius) {
            ForEach(ConcertRadius.allCases, id: \.self) { radius in
                Text(radius.label)
                    .accessibilityLabel(radius.spoken)
                    .tag(radius)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct LayoutPicker: View {
    @Binding var layout: ConcertsModel.Layout

    var body: some View {
        Picker("Show as", selection: $layout) {
            ForEach(ConcertsModel.Layout.allCases) { layout in
                Label(layout.label, systemImage: layout.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: Previews

#Preview("Concerts") {
    let place = ConcertPlace(name: "Lisboa", region: "Lisbon", country: "Portugal", latitude: 38.72, longitude: -9.14)
    let concerts = ConcertRow.placeholders.enumerated().map { index, concert in
        var concert = concert
        concert.name = ["Radiohead", "Lorde", "Bon Iver", "Rosalía"][index]
        return concert
    }
    NavigationStack {
        ConcertsView(model: ConcertsModel(
            preview: .init(place: place, available: true),
            near: .init(place: place, radiusKm: 50, items: concerts, page: 1, hasMore: true, unavailable: false),
            artists: .init(items: Array(concerts.prefix(1)), matched: 12, pending: 3, unavailable: false)
        ))
        .navigationTitle("Discover")
    }
}
