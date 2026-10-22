import SwiftUI

// Search's rows, out of `SearchView.swift` to keep it under the file limit.

/// A hit one tap acts on: adds it to the list (list mode) or chooses it (pick mode).
struct TapHitRow: View {
    let hit: CatalogHit
    let kind: MediaKind
    /// The button's word: "Add", "Choose".
    let action: String
    /// Already on the list: a check instead of the button.
    let isDone: Bool
    let isAdding: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title).font(.body.weight(.medium)).lineLimit(2)
                Text(hit.detailLine(kind: kind))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isDone {
                Label("On this list", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color(.accent))
                    .accessibilityLabel("On this list")
            } else if isAdding {
                ProgressView()
            } else {
                Button(action: onTap) {
                    Text(action)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.25)))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(action) \(hit.title)")
            }
        }
        .padding(.vertical, 4)
    }
}

struct SearchHitRow: View {
    let hit: CatalogHit
    let kind: MediaKind
    let isInLibrary: Bool
    let isAdding: Bool
    let onAdd: (LibraryStatus) -> Void
    let onAddToList: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title).font(.body.weight(.medium)).lineLimit(2)
                Text(hit.detailLine(kind: kind))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isInLibrary {
                Label("In your library", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color(.accent))
                    .accessibilityLabel("In your library")
            } else if isAdding {
                ProgressView()
            } else {
                AddMenu(kind: kind, onAdd: onAdd, onAddToList: onAddToList)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The last row of an All search: books and music are searched on their own.
struct SearchElsewhereRow: View {
    let query: String
    /// Nothing else matched, so the row says so first.
    let isFirst: Bool
    let onSearch: (SearchScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFirst {
                Text("No films, shows or anime match.")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            ForEach([SearchScope.book, .music]) { scope in
                if let kind = scope.kind {
                    Button {
                        onSearch(scope)
                    } label: {
                        Label("Search \(kind.label) for \u{201C}\(query)\u{201D}", systemImage: kind.symbol)
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
