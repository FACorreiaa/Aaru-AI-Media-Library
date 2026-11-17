import AaruAPI
import SwiftUI

/// GRAPH-007: `WorldMap`, a World drawn. A row per lane (books, films, shows…), each lane's titles
/// in the server's order along a rail; a link between lanes is a rung. Finished titles are lit,
/// the one to go to next is ringed, titles the user does not have are quieter, and a side story
/// is smaller. The server places everything; this only draws it, scrolling both ways.
///
/// VoiceOver reads it lane by lane, in order: the lines are decoration.
struct WorldMap: View {
    let world: StoryWorld
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            WorldMapContent(world: world)
                // The map arrives once, on entrance; nothing moves after that.
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(AaruMotion.ease(AaruMotion.slow)) { shown = true }
            }
        }
    }
}

/// The map at its full size, without scrolling: lane labels, tiles, and the lines under them.
struct WorldMapContent: View {
    let world: StoryWorld

    var body: some View {
        let layout = WorldLayout(world)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(layout, in: &context) }
                .frame(width: layout.size.width, height: layout.size.height)
                .accessibilityHidden(true)
            ForEach(Array(world.lanes.enumerated()), id: \.element.kind) { laneIndex, lane in
                laneLabel(lane)
                    .offset(x: layout.labelOrigin(lane: laneIndex).x, y: layout.labelOrigin(lane: laneIndex).y)
                ForEach(Array(lane.titles.enumerated()), id: \.element.key) { column, title in
                    WorldTile(title: title, lane: lane.kind, startHere: world.startHere == title.key)
                        .offset(
                            x: layout.origin(lane: laneIndex, column: column).x,
                            y: layout.origin(lane: laneIndex, column: column).y
                        )
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private func laneLabel(_ lane: WorldLane) -> some View {
        let done = lane.titles.count(where: { $0.status == .finished })
        return HStack(spacing: AaruSpace.small) {
            Image(systemName: lane.kind.kind.symbol)
                .foregroundStyle(.tint)
            Text(lane.kind.kind.label).eyebrow()
            Text(WorldWords.count(finished: done, total: lane.titles.count))
                .font(.caption)
                .foregroundStyle(Color(.muted))
                .monospacedDigit()
        }
        .frame(height: WorldLayout.labelHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The rails and the rungs, under the tiles.
    private func draw(_ layout: WorldLayout, in context: inout GraphicsContext) {
        let middle = WorldLayout.posterHeight / 2
        for (laneIndex, lane) in world.lanes.enumerated() {
            for column in lane.titles.indices.dropFirst() {
                let earlier = layout.origin(lane: laneIndex, column: column - 1)
                let later = layout.origin(lane: laneIndex, column: column)
                var rail = Path()
                rail.move(to: CGPoint(x: earlier.x + WorldLayout.tileWidth, y: earlier.y + middle))
                rail.addLine(to: CGPoint(x: later.x, y: later.y + middle))
                // Lit between two finished titles: the path the user has walked.
                let walked = lane.titles[column - 1].status == .finished && lane.titles[column].status == .finished
                context.stroke(
                    rail, with: .color(walked ? Color(.accent) : Color(.lineStrong)),
                    style: StrokeStyle(lineWidth: walked ? 2.5 : 1.5, lineCap: .round)
                )
            }
        }
        // A rung drops from under the upper title to just above the lower lane's label, over the
        // column of the title it joins: it never runs through the label.
        for rung in layout.rungs {
            let top = layout.origin(lane: rung.upper.lane, column: rung.upper.column)
            let bottom = layout.origin(lane: rung.lower.lane, column: rung.lower.column)
            let start = CGPoint(
                x: top.x + WorldLayout.tileWidth / 2, y: top.y + WorldLayout.posterHeight + WorldLayout.captionHeight
            )
            let end = CGPoint(x: bottom.x + WorldLayout.tileWidth / 2, y: bottom.y - WorldLayout.labelHeight - 4)
            let bend = (end.y - start.y) / 2
            var path = Path()
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x, y: start.y + bend),
                control2: CGPoint(x: end.x, y: end.y - bend)
            )
            context.stroke(path, with: .color(Color(.lineStrong)), style: StrokeStyle(lineWidth: 1.25, dash: [4, 4]))
            context.fill(
                Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                with: .color(Color(.lineStrong))
            )
        }
    }
}

/// One title on the map, opening its page: the Title room when it is in the library, else its
/// catalog page.
struct WorldTile: View {
    let title: WorldTitle
    let lane: WorldLaneKind
    let startHere: Bool

    private var finished: Bool {
        title.status == .finished
    }

    /// A side story is drawn smaller; it keeps its column.
    private var posterWidth: CGFloat {
        title.side ? WorldLayout.tileWidth * 0.8 : WorldLayout.tileWidth
    }

    var body: some View {
        Group {
            if let item = title.libraryItemId {
                NavigationLink(value: item) { tile }
            } else {
                NavigationLink(value: CatalogRoute(hit: title.hit(in: lane))) { tile }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.spoken(in: lane, startHere: startHere))
        .accessibilityAddTraits(.isButton)
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: lane.kind)
                .clipShape(.rect(cornerRadius: AaruRadius.thumb, style: .continuous))
                .frame(width: posterWidth)
                .frame(width: WorldLayout.tileWidth, height: WorldLayout.posterHeight, alignment: .bottom)
                // A title the user does not have is quieter; the next step never is.
                .opacity(title.libraryItemId == nil && !startHere && !title.next ? 0.5 : 1)
                .overlay {
                    if startHere {
                        RoundedRectangle(cornerRadius: AaruRadius.thumb + 3, style: .continuous)
                            .stroke(Color(.accent), lineWidth: 2)
                            .frame(width: posterWidth + 6)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if startHere || title.next {
                        Text(startHere ? "Start here" : "Next")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.ink), in: Capsule())
                            .foregroundStyle(Color(.paper))
                            .padding(3)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if finished {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color(.paper), Color(.accent))
                            .padding(3)
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(title.ref.title ?? "")
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(Color(.ink))
                if let year = title.year {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(Color(.muted))
                }
            }
            .frame(
                width: WorldLayout.tileWidth,
                height: WorldLayout.captionHeight - AaruSpace.xsmall,
                alignment: .topLeading
            )
        }
    }
}

/// What the map's marks mean.
struct WorldLegend: View {
    var body: some View {
        HStack(spacing: AaruSpace.large) {
            Label("Finished", systemImage: "checkmark.circle.fill")
            Label("Start here", systemImage: "circle.circle")
            Label("Ahead", systemImage: "circle")
        }
        .font(.caption)
        .foregroundStyle(Color(.muted))
        .accessibilityElement(children: .combine)
    }
}
