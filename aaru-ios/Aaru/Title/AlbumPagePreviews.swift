import SwiftUI

// MUS-001: the album page, as `TitleDetailView` draws it for an album.

#Preview("Album") {
    let entry = AlbumSample.entry("OK Computer", artist: "Radiohead", year: 1997)
    NavigationStack {
        TitleDetailView(
            entry: entry, api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
            title: AlbumSample.detail(
                for: entry, genres: ["alternative rock", "art rock"], tracks: AlbumSample.okComputerTracks
            )
        )
    }
}

#Preview("Album, two discs · dark") {
    let entry = AlbumSample.entry("The Fragile", artist: "Nine Inch Nails", year: 1999, status: .finished)
    NavigationStack {
        TitleDetailView(
            entry: entry, api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
            title: AlbumSample.detail(
                for: entry, genres: ["industrial rock", "industrial", "alternative rock"],
                tracks: AlbumSample.fragileTracks
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Album, no tracklist yet") {
    let entry = AlbumSample.entry("Vespertine", artist: "Björk", year: 2001, status: .wishlist)
    NavigationStack {
        TitleDetailView(
            entry: entry, api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
            title: AlbumSample.detail(for: entry, genres: [], tracks: nil)
        )
    }
}
