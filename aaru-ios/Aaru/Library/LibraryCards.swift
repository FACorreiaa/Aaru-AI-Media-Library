import SwiftUI

// Library's pieces (`LibraryView`): the filter bar, the poster grid and its cards, the row, the
// iPhone "Lists" entry and the ribbon after a removal.

/// Kind chips and the status menu, with the offline line under them.
struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    /// "Offline. Showing your library from the last sync." A first failure is the main error.
    let syncProblem: String?

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isOn: filter.kind == nil) { filter.kind = nil }
                    ForEach(MediaKind.allCases) { option in
                        FilterChip(title: option.label, isOn: filter.kind == option) { filter.kind = option }
                    }
                    Menu {
                        Picker("Status", selection: $filter.status) {
                            Text("Any status").tag(LibraryStatus?.none)
                            ForEach(LibraryStatus.allCases) { Text($0.label(for: filter.kind)).tag(Optional($0)) }
                        }
                    } label: {
                        Label(
                            filter.status?.label(for: filter.kind) ?? "Any status",
                            systemImage: "line.3.horizontal.decrease"
                        )
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, AaruSpace.small)
                        .overlay(Capsule().strokeBorder(Color(.lineStrong)))
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Status: \(filter.status?.label(for: filter.kind) ?? "Any status")")
                }
                .padding(.horizontal, 16)
            }
            if let syncProblem {
                Label(syncProblem, systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 4)
        .background(Color(.paper))
    }
}

/// A capsule toggle. The capsule is drawn small; the target is 44 pt tall.
private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, AaruSpace.medium)
                .padding(.vertical, AaruSpace.small)
                .foregroundStyle(isOn ? Color(.paper) : Color(.ink))
                .background(isOn ? Color(.ink) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color(.lineStrong)))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The poster grid: columns follow the width (iPad thirds to a full Mac window), and widen with
/// the text size so titles wrap rather than clip.
struct LibraryGrid<Menu: View>: View {
    let rows: [LibraryRow]
    @ViewBuilder let menu: (LibraryRow) -> Menu

    @ScaledMetric(relativeTo: .footnote) private var cardWidth: CGFloat = 108

    var body: some View {
        let minimum = min(max(108, cardWidth), 220)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum, maximum: max(160, minimum)), spacing: 16, alignment: .top)],
            spacing: 20
        ) {
            ForEach(rows) { row in
                NavigationLink(value: row.id) { LibraryPosterCard(row: row) }
                    .buttonStyle(.plain)
                    .posterHover()
                    .contextMenu { menu(row) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// One library poster with its title and status: the grid's card, and a kind page's shelf (NAV-002).
struct LibraryPosterCard: View {
    let row: LibraryRow
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: row.posterURL, kind: row.kind)
            Text(row.title)
                .font(.footnote.weight(.medium))
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            if row.kind == .music, let artist = row.byline {
                Text(artist)
                    .font(.caption2)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            }
            Text(row.detail ?? row.status.label(for: row.kind))
                .font(.caption2)
                .foregroundStyle(Color(.muted))
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryListRow: View {
    let row: LibraryRow

    var body: some View {
        HStack(spacing: AaruSpace.medium) {
            PosterView(url: row.posterURL, kind: row.kind)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                Text(row.title).font(.body.weight(.medium)).lineLimit(2)
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                Text([row.status.label(for: row.kind), row.detail].compactMap(\.self).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    /// "1997 · Film", or "Radiohead · 1997" for an album (UX-046: one item, the singular noun).
    private var metaLine: String {
        let parts = row.kind == .music
            ? [row.byline, row.year.map(String.init)]
            : [row.year.map(String.init), row.kind.noun]
        return parts.compactMap(\.self).joined(separator: " · ")
    }
}

/// iPhone: "Lists ›" at the top of Library, since Lists has no tab there (§18).
struct ListsEntryRow: View {
    /// Nil until the lists have loaded.
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label("Lists", systemImage: "list.bullet.rectangle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(.ink))
                Spacer(minLength: 8)
                if let count {
                    Text(count, format: .number)
                        .foregroundStyle(Color(.muted))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.muted))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AaruSpace.large)
            .frame(minHeight: 44)
            .background(Color(.surface), in: .rect(cornerRadius: AaruRadius.panel, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your lists")
    }
}

/// After "Remove from library": what went, and the way to undo it in History (UX-061).
struct RemovalRibbon: View {
    let title: String?
    let onHistory: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let title {
            HStack(spacing: 12) {
                Text("Removed “\(title)”.")
                    .font(.callout)
                    .foregroundStyle(Color(.ink))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Undo in History", action: onHistory)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 16)
            .background(Color(.surface), in: .rect(cornerRadius: AaruRadius.panel, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }
}

extension View {
    /// The pointer over a poster: a lift on iPad, an accent ring on the Mac. No motion on the
    /// Mac, so nothing to turn off under Reduce Motion.
    func posterHover() -> some View {
        #if os(iOS)
            hoverEffect(.lift)
        #else
            modifier(MacPosterHover())
        #endif
    }
}

#if os(macOS)
    private struct MacPosterHover: ViewModifier {
        @State private var hovering = false

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .top) {
                    if hovering {
                        RoundedRectangle(cornerRadius: AaruRadius.panel, style: .continuous)
                            .strokeBorder(Color(.accent).opacity(AaruAlpha.half), lineWidth: 2)
                            .padding(-4)
                            .allowsHitTesting(false)
                    }
                }
                .onHover { hovering = $0 }
        }
    }
#endif
