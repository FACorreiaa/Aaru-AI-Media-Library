import SwiftUI

/// Music's Concerts view (MUS-003, moved from Discover by NAV-002): "Your artists on tour", then
/// concerts near the saved city or near the viewer once, within 25, 50 or 100 km, as a date-led
/// list or a map of the searched area. Tickets open Ticketmaster; Aaru sells nothing. On the Mac
/// the radius and the List/Map switch sit in the toolbar, as Music's own switch does.
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
            if model.nearState != .noPlace, !model.searchesAnywhere, model.performerChoices == nil {
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
                    QuietNote("Concert listings aren't answering right now.")
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
            return "When an artist of an album in your library tours, the dates show here."
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
                if model.nearState != .noPlace, !model.searchesAnywhere, model.performerChoices == nil {
                    HStack(spacing: 12) {
                        RadiusPicker(radius: $model.radius)
                        LayoutPicker(layout: $model.layout).fixedSize()
                    }
                }
            #endif
            if let choices = model.performerChoices {
                PerformerChoicesList(model: model, choices: choices)
            } else {
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

/// The Near list once loaded: the listings' silence, nothing in range, or the concerts (under
/// the map when Map is on), with Show more.
private struct NearResults: View {
    let model: ConcertsModel

    var body: some View {
        let items = model.nearItems
        if model.nearUnavailable {
            ContentUnavailableView {
                // The vendor is named in the credit, not as the error's subject (UX-050).
                Label("Concert listings aren't answering", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Try again in a few minutes.")
            } actions: {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        } else {
            // Anywhere is list only: its concerts are not around one centre.
            if model.layout == .map, !model.searchesAnywhere, let centre = model.centre {
                ConcertsMap(name: centre.name, point: centre.point, radiusKm: model.radius.rawValue)
            }
            if items.isEmpty {
                EmptyNear(model: model)
            } else {
                ForEach(items, id: \.id) { concert in
                    ConcertRow(concert: concert, compact: model.layout == .map && !model.searchesAnywhere)
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

/// The provider's performers for a submitted name, best first, then every event matching the
/// name, for festivals and bills without a named act (MUS-010).
private struct PerformerChoicesList: View {
    let model: ConcertsModel
    let choices: PerformerChoices

    var body: some View {
        switch choices {
        case .loading:
            PlaceholderRows(count: 3, label: "Looking for artists")
        case let .ready(name, performers):
            VStack(alignment: .leading, spacing: 0) {
                Text("Which one?")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                    .padding(.bottom, 4)
                ForEach(performers, id: \.id) { performer in
                    ChoiceRow {
                        PerformerAvatar(performer: performer)
                        Text(performer.name)
                            .foregroundStyle(Color(.ink))
                    } action: {
                        model.choose(performer)
                    }
                    Divider()
                }
                ChoiceRow {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 40, height: 40)
                        .overlay(Circle().strokeBorder(Color(.line)))
                    Text("All events matching “\(name)”")
                        .foregroundStyle(Color(.muted))
                } action: {
                    model.chooseAll(name)
                }
            }
        }
    }
}

private struct ChoiceRow<Label: View>: View {
    @ViewBuilder let label: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Ticketmaster's picture of the performer, or their initial.
private struct PerformerAvatar: View {
    let performer: ConcertPerformer

    var body: some View {
        AsyncImage(url: performer.imageUrl.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(performer.name.prefix(1))
                .font(.headline)
                .foregroundStyle(Color(.ink))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.surface))
        }
        .frame(width: 40, height: 40)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Nothing listed: in range, or for the searched artist (MUS-010), with the next thing to try.
private struct EmptyNear: View {
    @Bindable var model: ConcertsModel

    var body: some View {
        if let artist = model.searchedArtist?.name {
            if model.scope == .anywhere {
                ContentUnavailableView(
                    "No upcoming \(artist) concerts listed", systemImage: "music.mic",
                    description: Text("Check the spelling, or try the name as the tickets show it.")
                )
            } else {
                ContentUnavailableView {
                    Label("No \(artist) concerts within \(model.radius.label)", systemImage: "music.mic")
                } actions: {
                    Button("Try Anywhere") { model.scope = .anywhere }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            ContentUnavailableView(
                "No concerts within \(model.radius.label)",
                systemImage: "music.mic",
                description: Text(model.radius == ._100 ? "Nothing is listed yet." : "Try a wider radius.")
            )
        }
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
