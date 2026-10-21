import SwiftUI

// Home's previews, out of `HomeScreen.swift` to keep it under the file limit.

#Preview("Home") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
}

#Preview("Home, now playing") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .samplePlaying)
}

#Preview("Home, new account") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .newAccount)
}

#Preview("Home · dark") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
        .preferredColorScheme(.dark)
}

#Preview("Mac", traits: .fixedLayout(width: 1280, height: 800)) {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
}

#Preview("Wide, side column filled", traits: .fixedLayout(width: 1180, height: 820)) {
    HomeScreen(
        api: nil, library: LibraryModel(), lists: .sample,
        imports: ImportsModel(preview: [.sampleWorking, .sampleDone]), model: .sample
    )
    .environment(\.horizontalSizeClass, .regular)
}

#Preview("Empty") {
    HomeScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: HomeModel(preview: .init(upNext: .init(continueWatching: [], startWatching: []), airing: []))
    )
}
