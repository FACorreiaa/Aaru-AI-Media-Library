import AaruAPI
import SwiftUI

/// GRAPH-002 / GRAPH-004: `RelationGraph` drawn. The server places every title (`rank` is the column,
/// `lane` the row, 0 the main chain); this only draws them, with no layout library, scrolling both
/// ways with pinch to zoom. A title's graph and a roadmap list's graph share it. With `onCentre`,
/// every title but the centre offers Centre.
struct RelationGraphCanvas: View {
    let graph: RelationGraph
    var onCentre: ((RelationNode) -> Void)?

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1

    private static let column: CGFloat = 136
    private static let row: CGFloat = 236
    private static let pad: CGFloat = 16
    /// Where an edge meets a card: halfway down a 2:3 poster.
    private static let anchorY: CGFloat = 72

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            canvas(graph)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: size(graph).width * zoom, height: size(graph).height * zoom, alignment: .topLeading)
        }
        .gesture(
            MagnifyGesture()
                .onChanged { zoom = min(max(settledZoom * $0.magnification, 0.5), 2) }
                .onEnded { _ in settledZoom = zoom }
        )
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
                    // Off the main chain an edge says what it is, as the web's graph does.
                    if let label = edge.relation.edgeLabel {
                        context.draw(
                            Text(label).font(.caption2).foregroundStyle(Color(.muted)),
                            at: labelPoint(from: source, to: target)
                        )
                    }
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
                    if let onCentre, !node.centre {
                        Button("Centre") { onCentre(node) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
                .offset(x: origin(node).x, y: origin(node).y)
            }
        }
        .frame(width: size(graph).width, height: size(graph).height, alignment: .topLeading)
    }

    /// Where an edge's label sits: the middle of the gap between its two cards.
    private func labelPoint(from source: RelationNode, to target: RelationNode) -> CGPoint {
        let ordered = source.rank < target.rank || (source.rank == target.rank && source.lane <= target.lane)
        let (first, second) = ordered ? (source, target) : (target, source)
        if first.rank == second.rank {
            return CGPoint(
                x: origin(first).x + RelatedCard.width / 2,
                y: (origin(first).y + RelatedCard.width * 1.5 + origin(second).y) / 2
            )
        }
        return CGPoint(
            x: (origin(first).x + RelatedCard.width + origin(second).x) / 2,
            y: (origin(first).y + origin(second).y) / 2 + Self.anchorY
        )
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

extension Components.Schemas.Relation {
    /// A short label for an edge in the graph; the main chain needs none. The web's `edgeLabel`.
    var edgeLabel: String? {
        switch self {
        case .sequel, .prequel: nil
        case .adaptation: String(localized: "adapted")
        case .source: String(localized: "source")
        case .sideStory: String(localized: "side story")
        case .parent: String(localized: "main story")
        case .spinOff: String(localized: "spin-off")
        case .alternative: String(localized: "other version")
        case .summary: String(localized: "recap")
        case .other: String(localized: "related")
        }
    }
}
