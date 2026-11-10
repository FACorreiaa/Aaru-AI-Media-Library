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
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.aaruDisplay(.title3, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing {
                    HomeRowLink(label: trailing.label, action: trailing.action)
                }
            }
            .padding(.horizontal, AaruSpace.xlarge)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
                    .padding(.horizontal, AaruSpace.xlarge)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AaruSpace.medium) {
                    content()
                }
                .scrollTargetLayout()
                .padding(.horizontal, AaruSpace.xlarge)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// The link at the end of a row's heading ("All 14", "See calendar"). The words stay one line
/// tall; the tap target is 44 pt, reaching into the space above and below the heading.
struct HomeRowLink: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.borderless)
        // Gives back what the target added, so the heading's row keeps its height.
        .padding(.vertical, -AaruSpace.medium)
    }
}

/// Card widths per row: on compact width a card is ~80% of the screen; wider screens show more.
enum HomeCardSize {
    case wide, poster, banner

    /// The card's width; at the accessibility text sizes cards widen so titles have room.
    func width(compact: Bool, dynamicType: DynamicTypeSize = .large) -> CGFloat {
        base(compact: compact) * (dynamicType.isAccessibilitySize ? 1.4 : 1)
    }

    private func base(compact: Bool) -> CGFloat {
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

/// Wide catalog art with the blue-to-amber wash over Surface when there is none.
struct HomeArt: View {
    let url: URL?
    let aspect: CGFloat

    var body: some View {
        Color(.surface)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: AaruMotion.ease(AaruMotion.fast))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color(.accent).opacity(AaruAlpha.ghost), Color(.gold).opacity(AaruAlpha.ghost)],
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
    var tint: Color = .init(.scrim)
    var foreground: Color = .init(.onScrim)

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, AaruSpace.small)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
    }
}

/// Under a pointer (Mac, iPad) a card lifts, so it reads as clickable.
struct HoverLift: ViewModifier {
    #if os(macOS)
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
            // iPad's pointer: the system lift, which follows Reduce Motion itself.
            content.hoverEffect(.lift)
        #else
            content
                .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
                .animation(AaruMotion.ease(AaruMotion.fast), value: hovering)
                .onHover { hovering = $0 }
        #endif
    }
}
