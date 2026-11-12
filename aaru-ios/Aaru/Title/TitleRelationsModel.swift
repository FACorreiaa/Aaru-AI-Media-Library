import AaruAPI
import Foundation

typealias RelationGraph = Components.Schemas.RelationGraph
typealias RelationNode = Components.Schemas.RelationNode
typealias RelationEdge = Components.Schemas.RelationEdge

/// GRAPH-002: a title's relation graph (GRAPH-001), as the server placed it. The server orders and
/// lays out every title; this model only loads it, and asks once more when the server cut a cold
/// graph short, by which time the rest is cached.
@MainActor
@Observable
final class TitleRelationsModel {
    private(set) var graph: RelationGraph?
    private(set) var loading = false
    /// True when the last read failed and there is no graph to show: the section says so and
    /// offers to try again, where "nothing related" stays absent.
    private(set) var failed = false
    var problem: String?
    @ObservationIgnored let api: Client?
    @ObservationIgnored private var titleID: String
    @ObservationIgnored private var order: Components.Schemas.RelationOrder = .release

    /// A partial graph is read again after this long, once.
    static let partialRetry: Duration = .seconds(5)

    init(api: Client?, titleID: String) {
        self.api = api
        self.titleID = titleID
    }

    /// Loads the graph; a partial one is asked for again once. A failure leaves the last graph.
    func load(retryPartial: Bool = true) async {
        guard let api else { return }
        let asked = (titleID, order)
        loading = true
        defer { loading = false }
        do {
            let output = try await api.getTitleRelations(
                path: .init(id: titleID),
                query: .init(order: order == .release ? nil : order)
            )
            guard asked == (titleID, order) else { return }
            guard case let .ok(response) = output else {
                failed = graph == nil
                return
            }
            graph = try response.body.json
            problem = nil
            failed = false
        } catch {
            // A page that moved on cancels its read: that is not a failure to show.
            if !Task.isCancelled, !(error is CancellationError), asked == (titleID, order) {
                failed = graph == nil
            }
            return
        }
        if retryPartial, graph?.partial == true {
            try? await Task.sleep(for: Self.partialRetry)
            guard !Task.isCancelled, asked == (titleID, order) else { return }
            await load(retryPartial: false)
        }
    }

    func setOrder(_ order: Components.Schemas.RelationOrder) async {
        guard order != self.order else { return }
        self.order = order
        await load()
    }

    /// Walks the graph out from another title: its Aaru title is found (or made) first, as opening
    /// its page would, and nothing is added to the library.
    func centre(on node: RelationNode) async {
        guard let api else { return }
        do {
            guard case let .ok(response) = try await api.resolveTitle(body: .json(node.ref)) else {
                problem = String(localized: "Aaru could not open that title.")
                return
            }
            titleID = try response.body.json.title.id
            await load()
        } catch {
            problem = String(localized: "Aaru could not reach the server.")
        }
    }

    /// "Add the chain" (GRAPH-003): the main chain as a capture to review. Its id, or nil after
    /// saying why not.
    func planChain() async -> String? {
        guard let api else { return nil }
        do {
            let output = try await api.planRelationChain(
                path: .init(id: titleID),
                query: .init(order: graph?.order == .story ? .story : nil)
            )
            guard case let .accepted(response) = output else {
                problem = String(localized: "Aaru could not plan the chain.")
                return nil
            }
            return try response.body.json.id
        } catch {
            problem = String(localized: "Aaru could not reach the server.")
            return nil
        }
    }

    /// True when the main chain has more than one title.
    var hasChain: Bool {
        (graph?.nodes.filter(\.mainChain).count ?? 0) > 1
    }

    var centre: RelationNode? {
        graph?.nodes.first(where: \.centre)
    }
}

// MARK: - Groups for the Related section

/// How a related title stands to the one on screen, as a group heading.
enum RelatedGroup: CaseIterable {
    case before, after, basedOn, adaptations, mainStory, sideStories, spinOffs, alternatives, summaries, other

    var label: String {
        switch self {
        case .before: String(localized: "Before")
        case .after: String(localized: "After")
        case .basedOn: String(localized: "Based on")
        case .adaptations: String(localized: "Adaptations")
        case .mainStory: String(localized: "Main story")
        case .sideStories: String(localized: "Side stories")
        case .spinOffs: String(localized: "Spin-offs")
        case .alternatives: String(localized: "Other versions")
        case .summaries: String(localized: "Recaps")
        case .other: String(localized: "Related")
        }
    }

    /// The group for the other end of an edge: `to` is `from`'s relation, and `outward` is true when
    /// the title on screen is `from`.
    init(_ relation: Components.Schemas.Relation, outward: Bool) {
        self = switch relation {
        case .sequel: outward ? .after : .before
        case .prequel: outward ? .before : .after
        case .adaptation: outward ? .adaptations : .basedOn
        case .source: outward ? .basedOn : .adaptations
        case .sideStory: outward ? .sideStories : .mainStory
        case .parent: outward ? .mainStory : .sideStories
        case .spinOff: .spinOffs
        case .alternative: .alternatives
        case .summary: .summaries
        case .other: .other
        }
    }
}

extension RelationGraph {
    /// The titles directly related to the centre, grouped, in the server's order.
    var relatedGroups: [(group: RelatedGroup, nodes: [RelationNode])] {
        guard let centre = nodes.first(where: \.centre) else { return [] }
        let byKey = Dictionary(nodes.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let position = Dictionary(nodes.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [RelatedGroup: [RelationNode]] = [:]
        var seen: Set<String> = []
        for edge in edges {
            let outward = edge.from == centre.key
            guard outward || edge.to == centre.key,
                  let other = byKey[outward ? edge.to : edge.from],
                  seen.insert(other.key).inserted
            else { continue }
            found[RelatedGroup(edge.relation, outward: outward), default: []].append(other)
        }
        return RelatedGroup.allCases.compactMap { group in
            guard let nodes = found[group] else { return nil }
            return (group, nodes.sorted { (position[$0.key] ?? 0) < (position[$1.key] ?? 0) })
        }
    }
}

extension RelationNode {
    var kind: MediaKind {
        MediaKind(type: ref._type, isAnime: isAnime ?? false)
    }

    /// "2013 · OVA": what tells two titles of one name apart.
    var caption: String {
        let year = releaseDate.map { String($0.prefix(4)) } ?? ref.year.map(String.init)
        let formats = [
            "tv": String(localized: "TV"), "tv_short": String(localized: "TV short"),
            "movie": String(localized: "Film"), "ova": String(localized: "OVA"), "ona": String(localized: "ONA"),
            "special": String(localized: "Special"), "manga": String(localized: "Manga"),
            "novel": String(localized: "Light novel"), "one_shot": String(localized: "One-shot"),
        ]
        return [year, format.flatMap { formats[$0] }].compactMap(\.self).joined(separator: " · ")
    }

    /// The catalog page for a title that is not in the library.
    var hit: CatalogHit {
        CatalogHit(
            _type: ref._type, title: ref.title ?? "", year: ref.year, posterUrl: posterUrl,
            isAnime: isAnime ?? false, ids: ref.ids ?? .init(), libraryItemId: libraryItemId,
            releaseDate: releaseDate
        )
    }
}
