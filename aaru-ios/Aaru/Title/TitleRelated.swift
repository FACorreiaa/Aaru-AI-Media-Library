import AaruAPI
import SwiftUI

/// GRAPH-002: `RelatedRow`, the title room's Related section: the titles directly before and after
/// this one, what it is based on and adapted into, and its side stories, each with the person's
/// status and "Start here". Graph opens the whole `RelationGraph`. Absent when nothing is related;
/// a read that fails says so and offers to try again.
struct TitleRelated: View {
    let api: Client?
    let titleID: String
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: TitleRelationsModel
    @State private var showsGraph = false
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(AssistantModel.self) private var assistant: AssistantModel?
    @Environment(\.assistantHostID) private var hostID

    /// Providers know sequels and adaptations, not every show set in one world: that is a question
    /// for the owl, whose answer is its own suggestion to review, never catalog data.
    private func askSameWorld() {
        let title = model.centre?.ref.title ?? "this title"
        router?.openAssistant(
            listening: false, titleID: titleID, onTitlePage: true, hostID: hostID,
            question: "What else is set in the same world as \"\(title)\"? Spin-offs, prequels and sequels "
                + "in any medium that are not already related here."
        )
    }

    init(api: Client?, titleID: String, library: LibraryModel, lists: ListsModel) {
        self.api = api
        self.titleID = titleID
        self.library = library
        self.lists = lists
        _model = State(initialValue: TitleRelationsModel(api: api, titleID: titleID))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let graph = model.graph, !graph.relatedGroups.isEmpty {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Related").eyebrow()
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if assistant?.isAvailable == true, router != nil {
                            Button("Ask Aaru for more", action: askSameWorld)
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
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
            } else if model.failed {
                VStack(alignment: .leading, spacing: AaruSpace.small) {
                    Text("Related").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    Text("Related titles could not be loaded.")
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                    Button("Try again") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.loading)
                }
            } else {
                Color.clear.frame(height: 0)
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
    @Environment(\.dismiss) private var dismiss

    init(api: Client?, titleID: String, library: LibraryModel, lists: ListsModel) {
        self.api = api
        self.library = library
        self.lists = lists
        _model = State(initialValue: TitleRelationsModel(api: api, titleID: titleID))
    }

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
                    RelationGraphCanvas(graph: graph) { node in Task { await model.centre(on: node) } }
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
            ContentUnavailableView {
                Label("Related titles could not be loaded", systemImage: "wifi.slash")
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        }
    }
}
