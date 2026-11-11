import AaruAPI
import SwiftUI

/// GRAPH-005: "From here" on the title page, under Related: where this title leads, in the
/// manner of a game's skill tree. Absent when the tree has no branch. Catalog data, the same for
/// everyone: it never adds anything, and a tile opens that title's page.
struct TitleFromHere: View {
    let model: TitleTreeModel

    var body: some View {
        ZStack(alignment: .leading) {
            if let tree = model.tree, model.hasBranches {
                VStack(alignment: .leading, spacing: AaruSpace.medium) {
                    Text("From here").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    TitleTreeFiltered(tree: tree)
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: model.titleID) { await model.load() }
    }
}

/// The same tree in a sheet, opened once when a tap on the title page finishes the title. A tile
/// opens its page inside the sheet.
struct TitleTreeSheet: View {
    let model: TitleTreeModel
    let name: String
    let library: LibraryModel
    let lists: ListsModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    Text("Where \(name) leads: who made it, and what comes after.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                    if let tree = model.tree {
                        TitleTreeFiltered(tree: tree, entrance: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AaruSpace.xlarge)
            }
            .navigationTitle("From here")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: model.api, library: library, lists: lists)
                }
                .catalogDestination(api: model.api, library: library, lists: lists)
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 420)
        #endif
    }
}

/// The tree under its chips (GRAPH-006). A film or show has a row each for its director, its lead
/// and its second actor, and the chips narrow those rows to one person. An iPhone has no "All":
/// one person's row at a time, so the section is no taller than it was. A tree with one person
/// has no chips. A choice redraws from the tree already loaded and reads nothing.
struct TitleTreeFiltered: View {
    let tree: TitleTree
    var entrance = false

    @State private var chosen: TitleTreeFilter?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let compact = sizeClass == .compact
        let filters = tree.filters(compact: compact)
        let filter = tree.filter(chosen: chosen, compact: compact)
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            if !filters.isEmpty {
                Picker("Whose titles to show", selection: Binding(
                    get: { filter },
                    set: { chosen = $0 }
                )) {
                    ForEach(filters, id: \.self) { Text(tree.label(of: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: Self.pickerMaxWidth)
            }
            TitleTreeCanvas(tree: tree.showing(filter), entrance: entrance)
        }
    }

    /// Wide enough for four chips; on a Mac or iPad the picker does not stretch across the page.
    private static let pickerMaxWidth: CGFloat = 400
}

/// The tree drawn: tiles over one layer of straight and right-angle lines, scrolled sideways when
/// it is wider than the screen. `entrance` brings the lines and then the tiles in, once, for the
/// sheet a tap opened; on the page nothing moves, and Reduce Motion shows it still.
struct TitleTreeCanvas: View {
    let tree: TitleTree
    var entrance = false

    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = TitleTreeLayout(tree)
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for connector in layout.connectors {
                        var path = Path()
                        path.addLines(connector.points)
                        context.stroke(
                            path,
                            with: .color(connector.lit ? Color(.accent) : Color(.muted).opacity(AaruAlpha.half)),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .miter)
                        )
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .accessibilityHidden(true)
                .modifier(Arriving(shown: shown, index: 0, reduceMotion: reduceMotion))

                tile(layout.root)
                ForEach(layout.rows) { row in
                    Text(row.branch.title).eyebrow()
                        .lineLimit(1)
                        .frame(width: layout.size.width - row.origin.x, alignment: .leading)
                        .offset(x: row.origin.x, y: row.origin.y)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(row.tiles) { tile($0) }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        }
        .onAppear { arrived = true }
    }

    /// On the page everything is there from the start; in the sheet it arrives after it appears.
    private var shown: Bool {
        !entrance || arrived
    }

    private func tile(_ tile: TitleTreeLayout.Tile) -> some View {
        TitleTreeTileLink(node: tile.node)
            .modifier(Arriving(shown: shown, index: tile.index, reduceMotion: reduceMotion))
            .offset(x: tile.origin.x, y: tile.origin.y)
    }
}

/// One part of the tree arriving: it fades up a few points, a beat behind the part before it.
private struct Arriving: ViewModifier {
    let shown: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion ? nil : .easeOut(duration: AaruMotion.base).delay(Double(index) * 0.04),
                value: shown
            )
    }
}

/// A tile opening its title: the Title room when it is in the library, else its catalog page. The
/// root is the title on screen, so it opens nothing.
private struct TitleTreeTileLink: View {
    let node: TreeNode

    var body: some View {
        Group {
            if node.isRoot {
                TitleTreeTile(node: node)
            } else if let item = node.libraryItemId {
                NavigationLink(value: item) { TitleTreeTile(node: node) }
            } else {
                NavigationLink(value: CatalogRoute(hit: node.hit)) { TitleTreeTile(node: node) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// One title: its art in a 2:3 slot (a square cover sits at the foot), its name and year. The root
/// and a finished title are ringed in the accent (lit); one in the library is in full colour; one
/// the person does not have is dimmed. A best-known title carries a star.
struct TitleTreeTile: View {
    let node: TreeNode

    private var locked: Bool {
        !node.isRoot && node.status == nil
    }

    private var lit: Bool {
        node.isRoot || node.isLit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            PosterView(url: node.posterUrl.flatMap(URL.init(string:)), kind: node.kind)
                .clipShape(RoundedRectangle(cornerRadius: AaruRadius.thumb, style: .continuous))
                .opacity(locked ? AaruAlpha.half : 1)
                .overlay {
                    RoundedRectangle(cornerRadius: AaruRadius.thumb, style: .continuous)
                        .stroke(lit ? Color(.accent) : Color(.line), lineWidth: lit ? 2 : 1)
                }
                .overlay(alignment: .topLeading) {
                    if node.pick == .bestKnown {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .padding(4)
                            .background(Color(.ink), in: Circle())
                            .foregroundStyle(Color(.paper))
                            .padding(4)
                    }
                }
                .frame(
                    width: TitleTreeLayout.tileWidth, height: TitleTreeLayout.tileHeight, alignment: .bottom
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(node.ref.title ?? "")
                    .font(.caption)
                    .lineLimit(2)
                if let line = node.isRoot ? node.status.map({ $0.label(for: node.kind) }) : node.year {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
            .frame(
                width: TitleTreeLayout.tileWidth, height: TitleTreeLayout.captionHeight - AaruSpace.xsmall,
                alignment: .topLeading
            )
        }
        .frame(width: TitleTreeLayout.tileWidth, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.spoken)
    }
}

#Preview("Every tile state") {
    let node: (String, Components.Schemas.TreePick, Components.Schemas.LibraryStatus?, Int) -> TreeNode = {
        TreeNode(
            key: $0, ref: .init(_type: .movie, title: $0, year: $3), pick: $1, status: $2
        )
    }
    return ScrollView {
        TitleTreeFiltered(tree: TitleTree(
            root: node("Arrival", .root, .finished, 2016),
            branches: [
                .init(kind: .director, label: "Denis Villeneuve", nodes: [
                    node("Blade Runner 2049", .next, .finished, 2017),
                    node("Dune", .next, .wishlist, 2021),
                    node("Dune: Part Two", .next, nil, 2024),
                    node("Sicario", .bestKnown, .inProgress, 2015),
                    node("Prisoners", .bestKnown, nil, 2013),
                ]),
                .init(kind: .leadActor, label: "Amy Adams", nodes: [
                    node("Nocturnal Animals", .next, nil, 2016),
                    node("Her", .bestKnown, .finished, 2013),
                ]),
                .init(kind: .secondActor, label: "Jeremy Renner", nodes: [
                    node("Wind River", .next, nil, 2017),
                    node("The Hurt Locker", .bestKnown, nil, 2008),
                ]),
                .init(kind: .series, nodes: [node("A sequel", .series, nil, 2027)]),
                .init(kind: .adaptation, nodes: [
                    TreeNode(
                        key: "book",
                        ref: .init(_type: .book, title: "Story of Your Life", year: 1998),
                        pick: .adaptation
                    ),
                ]),
            ],
            partial: false
        ), entrance: true)
            .padding()
    }
}
