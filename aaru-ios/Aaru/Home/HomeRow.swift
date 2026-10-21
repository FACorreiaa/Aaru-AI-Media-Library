import SwiftUI

/// One Home row (DESIGN.md §13): a heading, an optional trailing link, and cards scrolling
/// sideways. On iPhone a card and a fifth show, so the row reads as scrollable.
struct HomeRow<Content: View>: View {
    let title: String
    /// A line under the title, e.g. why a row is a stand-in (AniList down, TMDB filling in).
    var note: String?
    var trailing: (label: String, action: () -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.aaruDisplay(.title3, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing {
                    Button(trailing.label, action: trailing.action)
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 20)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
                    .padding(.horizontal, 20)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    content()
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// Card widths per row: on compact width a card is ~80% of the screen; wider screens show more.
enum HomeCardSize {
    case wide, poster, banner

    func width(compact: Bool) -> CGFloat {
        switch (self, compact) {
        case (.wide, true): 300
        case (.wide, false): 340
        case (.poster, true): 128
        case (.poster, false): 150
        case (.banner, true): 240
        case (.banner, false): 260
        }
    }
}

/// Wide catalog art with the teal-to-gold wash over Surface when there is none.
struct HomeArt: View {
    let url: URL?
    let aspect: CGFloat

    var body: some View {
        Color(.surface)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color(.accent).opacity(0.25), Color(.gold).opacity(0.25)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// A small chip over art: runtime, time left, "Finale".
struct HomeChip: View {
    let text: String
    var tint: Color = .black.opacity(0.55)
    var foreground: Color = .white

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
    }
}

/// On a Mac a card lifts under the pointer, so it reads as clickable.
struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 8, y: 4)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}
