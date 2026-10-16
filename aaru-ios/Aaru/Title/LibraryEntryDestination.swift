import AaruAPI
import SwiftUI

/// Title detail for a library item id from Home or Calendar. Those screens load before the
/// library has synced, so an id can be new to this device: sync once (incremental), then show.
struct LibraryEntryDestination: View {
    let id: String
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var synced = false

    /// Reads `rows`, which the model publishes on sync, so this view re-renders after one.
    private var entry: LibraryEntry? {
        _ = library.rows.count
        return library.entry(id)
    }

    var body: some View {
        if let entry {
            TitleDetailView(entry: entry, api: api, library: library, lists: lists)
        } else if synced, !library.isSyncing {
            ContentUnavailableView(
                "Not in your library",
                systemImage: "questionmark.square.dashed",
                description: Text("It may have been removed on another device.")
            )
        } else {
            ProgressView()
                .task {
                    await library.sync(api: api)
                    synced = true
                }
        }
    }
}
