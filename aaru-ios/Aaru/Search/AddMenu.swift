import SwiftUI

/// The "Add" button on a catalog hit (Search, Discover). A tap adds the title as planned; holding
/// it offers the other starting statuses and "Add to list…". Status words follow the kind.
struct AddMenu: View {
    let kind: MediaKind
    let onAdd: (LibraryStatus) -> Void
    let onAddToList: () -> Void

    var body: some View {
        Menu {
            ForEach([LibraryStatus.wishlist, .inProgress, .finished]) { status in
                Button(status.label(for: kind)) { onAdd(status) }
            }
            Divider()
            Button("Add to list…", systemImage: "text.badge.plus", action: onAddToList)
        } label: {
            Text("Add")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.25)))
        } primaryAction: {
            onAdd(.wishlist)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityHint("Adds as \(LibraryStatus.wishlist.label(for: kind)). Hold for other statuses.")
    }
}
