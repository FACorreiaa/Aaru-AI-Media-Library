import SwiftUI

/// GRAPH-007: `WorldShareCard`, the user's path through a World as an image the device renders:
/// the World's name, their count, and a row of dots per lane, filled where they have finished.
/// Their own data in brand colours, no posters, as the Recap card is; nothing is uploaded and no
/// link carries it.
struct WorldShareCard: View {
    let world: StoryWorld

    static let size = CGSize(width: 1080, height: 1350)
    /// Dots a lane shows before it says how many more.
    static let maxDots = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MY PATH THROUGH")
                .font(.system(size: 40, weight: .medium))
            Text(world.name ?? "")
                .font(.aaruDisplay(size: 120))
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .padding(.top, 24)
            Text(WorldWords.count(finished: world.finished, total: world.total))
                .font(.aaruDisplay(size: 72))
                .monospacedDigit()
                .padding(.top, 32)
                .opacity(0.9)
            // Six lanes still fit: they step down a size past four.
            let compact = world.lanes.count > 4
            VStack(alignment: .leading, spacing: compact ? 36 : 52) {
                ForEach(world.lanes, id: \.kind) { lane in
                    VStack(alignment: .leading, spacing: 18) {
                        Text(lane.kind.kind.label)
                            .font(.system(size: compact ? 34 : 40, weight: .medium))
                            .opacity(0.8)
                        dots(lane, size: compact ? 40 : 48)
                    }
                }
            }
            .padding(.top, 72)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                Text("Aaru").font(.aaruDisplay(size: 44, weight: .semibold))
                Spacer()
                Text("aaruapp.com").font(.system(size: 32)).opacity(0.75)
            }
        }
        .padding(AaruSpace.page * 2)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .foregroundStyle(Color(.paper))
        .background(LinearGradient(
            colors: [Color(.accent), Color(.ink)], startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }

    private func dots(_ lane: WorldLane, size: CGFloat) -> some View {
        let shown = lane.titles.prefix(Self.maxDots)
        let more = lane.titles.count - shown.count
        return HStack(spacing: size * 0.4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, title in
                Circle()
                    .strokeBorder(Color(.paper), lineWidth: 4)
                    .background(Circle().fill(Color(.paper).opacity(title.status == .finished ? 1 : 0)))
                    .frame(width: size, height: size)
            }
            if more > 0 {
                Text("+\(more)").font(.system(size: size * 0.8, weight: .medium))
            }
        }
    }
}

/// Renders the share card once and offers it to the share sheet.
struct WorldShareButton: View {
    let world: StoryWorld
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview("My path through \(world.name ?? "")", image: image)) {
                    Label("Share my path", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
            }
        }
        .task(id: world.finished) { render() }
    }

    private func render() {
        let renderer = ImageRenderer(content: WorldShareCard(world: world).environment(\.colorScheme, colorScheme))
        renderer.proposedSize = ProposedViewSize(WorldShareCard.size)
        renderer.scale = 1
        if let cgImage = renderer.cgImage {
            image = Image(decorative: cgImage, scale: 1)
        }
    }
}
