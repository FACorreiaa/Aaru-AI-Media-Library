import AaruAPI
import SwiftUI

/// GRAPH-002: `RelatedRow`, the title room's Related section: the titles directly before and after
/// this one, what it is based on and adapted into, and its side stories, each with the person's
/// status and "Start here". Graph opens the whole `RelationGraph`. Absent when nothing is related
/// or the read fails.
struct TitleRelated: View {
    let api: Client?
    let titleID: String
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: TitleRelationsModel
    @State private var showsGraph = false

    init(api: Client?, titleID: String, library: LibraryModel, lists: ListsModel) {
        self.api = api
        self.titleID = titleID
        self.library = library
        self.lists = lists
        _model = State(initialValue: TitleRelationsModel(api: api, titleID: titleID))
    }

    var body: some View {
        Group {
            if let graph = model.graph, !graph.relatedGroups.isEmpty {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Related").eyebrow()
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Graph", systemImage: "point.3.connected.trianglepath.dotted") { showsGraph = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    ForEach(graph.relatedGroups, id: \.group) { group in
                        VStack(alignment: .leading, spacing: AaruSpace.small) {
                            Text(group.group.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(.muted))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: AaruSpace.medium) {
                                    ForEach(group.nodes, id: \.key) { node in
                                        RelatedNodeLink(node: node, startHere: graph.startHere == node.key)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: titleID) { await model.load() }
        .sheet(isPresented: $showsGraph) {
            RelationGraphSheet(api: api, titleID: titleID, library: library, lists: lists)
        }
    }
}

/// One related title, opening its page: the Title room when it is in the library, else its catalog page.
struct RelatedNodeLink: View {
    let node: RelationNode
    let startHere: Bool

    var body: some View {
        Group {
            if let item = node.libraryItemId {
                NavigationLink(value: item) { RelatedCard(node: node, startHere: startHere) }
            } else {
                NavigationLink(value: CatalogRoute(hit: node.hit)) { RelatedCard(node: node, startHere: startHere) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A related title: poster, name, year and format, the person's status, and "Start here".
struct RelatedCard: View {
    let node: RelationNode
    let startHere: Bool

    static let width: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            PosterView(url: node.posterUrl.flatMap(URL.init(string:)), kind: node.kind)
                .overlay(alignment: .topLeading) {
                    if startHere {
                        Text("Start here")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.ink), in: Capsule())
                            .foregroundStyle(Color(.paper))
                            .padding(4)
                    }
                }
            Text(node.ref.title ?? "")
                .font(.subheadline)
                .lineLimit(2)
            if !node.caption.isEmpty {
                Text(node.caption)
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
            if let status = node.status {
                Text(status.label(for: node.kind))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.ink).opacity(AaruAlpha.tint), in: Capsule())
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The graph

/// GRAPH-002: `RelationGraph`, the whole graph in a sheet. The server places every title (`rank`
/// is the column, `lane` the row, 0 the main chain); this view only draws them. A title opens its
/// page inside the sheet; Centre walks the graph out from it.
struct RelationGraphSheet: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: TitleRelationsModel
    @State private var planning = false
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @Environment(\.dismiss) private var dismiss

    init(api: Client?, titleID: String, library: LibraryModel, lists: ListsModel) {
        self.api = api
        self.library = library
        self.lists = lists
        _model = State(initialValue: TitleRelationsModel(api: api, titleID: titleID))
    }

    private static let column: CGFloat = 136
    private static let row: CGFloat = 236
    private static let pad: CGFloat = 16
    /// Where an edge meets a card: halfway down a 2:3 poster.
    private static let anchorY: CGFloat = 72

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.centre?.ref.title ?? "Related")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    if model.graph?.storyOrderAvailable == true {
                        ToolbarItem(placement: .primaryAction) { orderPicker }
                    }
                    if model.hasChain {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add the chain", systemImage: "text.badge.plus") { Task { await addChain() } }
                                .disabled(planning)
                        }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .catalogDestination(api: api, library: library, lists: lists)
        }
        .task { await model.load() }
        #if os(macOS)
            .frame(minWidth: 720, minHeight: 520)
        #endif
    }

    /// The chain becomes a capture to review; the sheet closes so the review can open (the same
    /// way a review opens from a notification or the owl).
    private func addChain() async {
        planning = true
        defer { planning = false }
        guard let id = await model.planChain() else { return }
        dismiss()
        try? await Task.sleep(for: .milliseconds(400))
        PushInbox.shared.importID = id
    }

    private var orderPicker: some View {
        Picker("Order", selection: Binding(
            get: { model.graph?.order ?? .release },
            set: { order in Task { await model.setOrder(order) } }
        )) {
            Text("Release order").tag(Components.Schemas.RelationOrder.release)
            Text("Story order").tag(Components.Schemas.RelationOrder.story)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var content: some View {
        if let graph = model.graph {
            VStack(alignment: .leading, spacing: AaruSpace.small) {
                if graph.partial {
                    Text("Some related titles are still being found.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .padding(.horizontal, AaruSpace.large)
                }
                if let problem = model.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Color(.danger))
                        .padding(.horizontal, AaruSpace.large)
                }
                if graph.nodes.count > 1 {
                    ScrollView([.horizontal, .vertical]) {
                        canvas(graph)
                            .scaleEffect(zoom, anchor: .topLeading)
                            .frame(
                                width: size(graph).width * zoom,
                                height: size(graph).height * zoom,
                                alignment: .topLeading
                            )
                    }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { zoom = min(max(settledZoom * $0.magnification, 0.5), 2) }
                            .onEnded { _ in settledZoom = zoom }
                    )
                    Text("Relations from AniList, TMDB and Wikidata.")
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .padding(.horizontal, AaruSpace.large)
                        .padding(.bottom, AaruSpace.small)
                } else {
                    ContentUnavailableView(
                        "Nothing related yet",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("No related titles are known for this one.")
                    )
                }
            }
        } else if model.loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Related titles could not be loaded", systemImage: "wifi.slash")
        }
    }

    private func size(_ graph: RelationGraph) -> CGSize {
        let ranks = graph.nodes.map(\.rank).max() ?? 0
        let lanes = graph.nodes.map(\.lane).max() ?? 0
        return CGSize(
            width: CGFloat(ranks) * Self.column + RelatedCard.width + Self.pad * 2,
            height: CGFloat(lanes) * Self.row + Self.row + Self.pad
        )
    }

    private func origin(_ node: RelationNode) -> CGPoint {
        CGPoint(x: Self.pad + CGFloat(node.rank) * Self.column, y: Self.pad + CGFloat(node.lane) * Self.row)
    }

    private func canvas(_ graph: RelationGraph) -> some View {
        let byKey = Dictionary(graph.nodes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in graph.edges {
                    guard let source = byKey[edge.from], let target = byKey[edge.to] else { continue }
                    let main = edge.relation == .sequel || edge.relation == .prequel
                    context.stroke(
                        path(from: source, to: target),
                        with: .color(main ? Color(.accent) : Color(.line)),
                        style: StrokeStyle(lineWidth: main ? 2 : 1.25, dash: main ? [] : [4, 4])
                    )
                }
            }
            .frame(width: size(graph).width, height: size(graph).height)
            .accessibilityHidden(true)
            ForEach(graph.nodes, id: \.key) { node in
                VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                    RelatedNodeLink(node: node, startHere: graph.startHere == node.key)
                        .overlay {
                            if node.centre {
                                RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous)
                                    .stroke(Color(.accent), lineWidth: 2)
                                    .padding(-3)
                                    .allowsHitTesting(false)
                            }
                        }
                    if !node.centre {
                        Button("Centre") { Task { await model.centre(on: node) } }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
                .offset(x: origin(node).x, y: origin(node).y)
            }
        }
        .frame(width: size(graph).width, height: size(graph).height, alignment: .topLeading)
    }

    /// From the right of the earlier card to the left of the later one, or straight down between
    /// two cards in one column.
    private func path(from source: RelationNode, to target: RelationNode) -> Path {
        let ordered = source.rank < target.rank || (source.rank == target.rank && source.lane <= target.lane)
        let (first, second) = ordered ? (source, target) : (target, source)
        var path = Path()
        if first.rank == second.rank {
            let x = origin(first).x + RelatedCard.width / 2
            path.move(to: CGPoint(x: x, y: origin(first).y + RelatedCard.width * 1.5))
            path.addLine(to: CGPoint(x: x, y: origin(second).y))
            return path
        }
        let start = CGPoint(x: origin(first).x + RelatedCard.width, y: origin(first).y + Self.anchorY)
        let end = CGPoint(x: origin(second).x, y: origin(second).y + Self.anchorY)
        let bend = (end.x - start.x) / 2
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + bend, y: start.y),
            control2: CGPoint(x: end.x - bend, y: end.y)
        )
        return path
    }
}
