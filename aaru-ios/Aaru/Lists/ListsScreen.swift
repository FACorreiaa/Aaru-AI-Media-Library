import AaruAPI
import SwiftUI

/// The Lists destination (iPad and Mac sidebar). Regular width: the lists beside the chosen
/// list, a split view; compact width (an iPad third, a narrow Mac window never gets here): a
/// stack. iPhone reaches `ListsView` from Library instead.
struct ListsScreen: View {
    let lists: ListsModel
    let library: LibraryModel
    let api: Client?

    /// Kept above the size-class branch, so resizing the window keeps the chosen list.
    @State private var selection: String?

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    var body: some View {
        if isWide {
            NavigationSplitView {
                ListsView(lists: lists, library: library, api: api, selection: $selection)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            } detail: {
                NavigationStack {
                    if let selection {
                        ListDetailView(listID: selection, lists: lists, library: library, api: api)
                            .id(selection)
                    } else {
                        ContentUnavailableView(
                            "Choose a list",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Pick one from the lists, or make a new one.")
                        )
                    }
                }
            }
            .onChange(of: lists.lists.map(\.id)) { _, ids in
                // A deleted list leaves the detail column.
                if let selection, !ids.contains(selection) {
                    self.selection = nil
                }
            }
        } else {
            NavigationStack {
                ListsView(lists: lists, library: library, api: api)
            }
        }
    }
}
