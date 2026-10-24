import AaruAPI
import SwiftUI

/// A public card the user does not have yet (Discover, Seasons, On air): what the card already
/// knows, up close, with Add: a card's tap until the title is added. Search and list members open
/// the full catalog page instead (LIB-006).
struct CatalogPreviewSheet: View {
    let hit: CatalogHit
    /// The caller's item for this title once added; the sheet then says so instead of offering Add.
    let libraryItemID: String?
    let isAdding: Bool
    let onAdd: (LibraryStatus) -> Void
    /// Runs after the sheet is gone, so the list picker can present.
    let onAddToList: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var kind: MediaKind {
        MediaKind(type: hit._type, isAnime: hit.isAnime)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    header
                    if let overview = hit.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(Color(.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                }
                .padding(20)
            }
            .background(Color(.paper))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    // A way out on every platform; the Mac has no swipe down (UX-069).
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AaruSpace.medium) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 96)
                .clipShape(RoundedRectangle(cornerRadius: AaruRadius.row, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(hit.title)
                    .font(.aaruDisplay(.title2, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let original = hit.originalTitle, original != hit.title {
                    Text(original)
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
                Text(hit.detailLine(kind: kind))
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if libraryItemID != nil {
            Label("In your library", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.accent))
        } else if isAdding {
            ProgressView("Adding…")
        } else {
            HStack(spacing: 8) {
                Menu {
                    ForEach([LibraryStatus.inProgress, .finished]) { status in
                        Button(status.label(for: kind)) { onAdd(status) }
                    }
                } label: {
                    Text(LibraryStatus.wishlist.label(for: kind))
                } primaryAction: {
                    onAdd(.wishlist)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Hold for other statuses.")
                Button("Add to list…", systemImage: "text.badge.plus") {
                    onAddToList()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
