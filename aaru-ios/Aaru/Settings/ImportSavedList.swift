import AaruAPI
import SwiftUI

/// The list an approved import saved its titles to, in order. As on the web (ASK-012), the list is a
/// tap away when the server named it; an older answer without its id says where to find it.
struct ImportSavedList: View {
    let name: String
    let listID: String?
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    var body: some View {
        if let listID {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved in order as the list \u{201C}\(name)\u{201D}.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                NavigationLink("Open the list") {
                    ListDetailView(listID: listID, lists: lists, library: library, api: api)
                }
                .font(.subheadline.weight(.medium))
            }
        } else {
            Text("Saved in order as the list \u{201C}\(name)\u{201D}. Find it under Lists.")
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
        }
    }
}
