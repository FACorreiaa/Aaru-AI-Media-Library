import SwiftUI

/// GAM-006a: the Recap's share image, the same card the web draws: the user's own numbers in
/// brand colours, no posters (the web's canvas can't use them, and the two should match).
struct RecapShareCard: View {
    let stats: Stats

    static let size = CGSize(width: 1080, height: 1350)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MY RECAP")
                .font(.system(size: 40, weight: .medium))
                .tracking(4)
            Text(RecapPeriod(year: stats.year, month: stats.month).label)
                .font(.aaruDisplay(size: 132))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 24)
            // A year review can carry seven lines; they step down a size, as on the web.
            let lines = RecapDeck.shareLines(stats)
            let compact = lines.count > 5
            VStack(alignment: .leading, spacing: compact ? 28 : 40) {
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.aaruDisplay(size: compact ? 52 : 64))
                }
            }
            .padding(.top, 96)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                Text("Aaru").font(.aaruDisplay(size: 44, weight: .semibold))
                Spacer()
                Text("aaruapp.com").font(.system(size: 32)).opacity(0.75)
            }
        }
        .padding(96)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .foregroundStyle(Color(.paper))
        .background(LinearGradient(
            colors: [Color(.accent), Color(.ink)], startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }
}

/// Renders the share card once and offers it to the share sheet.
struct RecapShareButton: View {
    let stats: Stats
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    preview: SharePreview("My Aaru recap", image: image)
                ) {
                    Label("Share as an image", systemImage: "square.and.arrow.up")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(lineWidth: 2))
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
            }
        }
        .task { render() }
    }

    private func render() {
        let renderer = ImageRenderer(content: RecapShareCard(stats: stats).environment(\.colorScheme, colorScheme))
        renderer.proposedSize = ProposedViewSize(RecapShareCard.size)
        renderer.scale = 1
        if let cgImage = renderer.cgImage {
            image = Image(decorative: cgImage, scale: 1)
        }
    }
}
