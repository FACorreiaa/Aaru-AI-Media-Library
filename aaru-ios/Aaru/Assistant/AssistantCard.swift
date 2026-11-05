import AaruAPI
import SwiftUI

/// The dimmed screen under the Assistant card. A tap closes it.
struct AssistantScrim: View {
    let onClose: () -> Void

    var body: some View {
        Color(.night)
            .opacity(AaruAlpha.half)
            .ignoresSafeArea()
            .onTapGesture(perform: onClose)
            .accessibilityHidden(true)
    }
}

/// The floating card the owl opens over the current screen (ASK-009): one Chat with Aaru. It rises
/// from the bottom, grows with the reply, and stays above the keyboard.
struct AssistantCard: View {
    let model: AssistantModel
    let api: Client?
    let library: LibraryModel
    /// Opened by a long press: the mic is about to start, so no keyboard.
    let opensListening: Bool
    let onClose: () -> Void
    let onOpenTitle: (TitleSummary) -> Void
    let onShowHistory: () -> Void

    /// Its own, so a Plan's Undo toast shows in the card and not dimmed behind it.
    @State private var toasts = ToastCenter()
    /// Back to zero when the swipe ends, however it ends: a cancelled gesture never calls `onEnded`.
    @GestureState private var dragOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private static let maxWidth: CGFloat = 560
    private static let closeDistance: CGFloat = 80
    private static let closeSpeed: CGFloat = 700
    private static let minimumHeight: CGFloat = 260

    private var isCompact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        GeometryReader { container in
            panel
                .frame(maxWidth: isCompact ? .infinity : Self.maxWidth)
                .padding(.horizontal, AaruSpace.medium)
                .padding(.bottom, AaruSpace.small)
                .offset(y: dragOffset)
                // Follows the finger as it is; only the way back to rest is animated.
                .animation(dragOffset == 0 ? settle : nil, value: dragOffset)
                .frame(maxHeight: Self.maxHeight(in: container.size.height), alignment: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        // This order: the toast reads the center from outside it, and the Plan's from inside.
        .undoToast()
        .toastCenter(toasts)
    }

    private var settle: Animation? {
        reduceMotion ? nil : .spring(duration: AaruMotion.base)
    }

    /// 70% of the container, which the keyboard has already taken its share of. A phone on its side
    /// with the keyboard up leaves so little that 70% would hide the reply; there it may take more.
    private static func maxHeight(in container: CGFloat) -> CGFloat {
        max(container * 0.7, min(container, minimumHeight))
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            turns
            Rectangle()
                .fill(Color(.line))
                .frame(height: 1)
            AssistantComposer(model: model, opensListening: opensListening)
        }
        .background(Color(.surface))
        .clipShape(.rect(cornerRadius: AaruRadius.card, style: .continuous))
        .lift(cornerRadius: AaruRadius.card)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        #if os(macOS)
            .onExitCommand(perform: onClose)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            // A sheet's grabber is an iOS idiom; on the Mac, Close and Escape say it.
            #if os(iOS)
                Capsule()
                    .fill(Color(.lineStrong))
                    .frame(width: 36, height: 5)
                    .padding(.top, AaruSpace.small)
                    .accessibilityHidden(true)
            #endif
            HStack(spacing: AaruSpace.small) {
                AaruAvatar(size: 28, breathing: model.phase == .answering)
                Text("Aaru")
                    .font(.aaruDisplay(.headline, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if model.voiceAvailable {
                    muteButton
                }
                closeButton
            }
            .padding(.leading, AaruSpace.large)
            .padding(.trailing, AaruSpace.xsmall)
        }
        .contentShape(.rect)
        .gesture(swipeToClose)
    }

    private var muteButton: some View {
        Button {
            model.isMuted.toggle()
        } label: {
            headerIcon(
                model.isMuted ? "Read replies aloud" : "Stop reading replies aloud",
                symbol: model.isMuted ? "speaker.slash" : "speaker.wave.2"
            )
        }
        .buttonStyle(.plain)
        .help(model.isMuted ? "Read replies aloud" : "Stop reading replies aloud")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            headerIcon("Close", symbol: "xmark")
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
    }

    /// The glyph stays small; the tap target is 44 pt.
    private func headerIcon(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(.muted))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }

    /// On the grabber and header only: the turns' scroll view keeps its own drag. Global, because
    /// the offset moves the card and a local space would move with it.
    private var swipeToClose: some Gesture {
        DragGesture(coordinateSpace: .global)
            .updating($dragOffset) { drag, offset, _ in
                offset = max(0, drag.translation.height)
            }
            .onEnded { drag in
                if drag.translation.height > Self.closeDistance || drag.velocity.height > Self.closeSpeed {
                    onClose()
                }
            }
    }

    // MARK: - Turns

    private var turns: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AaruSpace.xlarge) {
                if model.turns.isEmpty {
                    Text("Ask about your library, what's airing, or anything you're tracking.")
                        .font(.callout)
                        .foregroundStyle(Color(.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.turns) { turn in
                    AssistantTurnView(
                        turn: turn,
                        model: model,
                        api: api,
                        library: library,
                        onOpenTitle: onOpenTitle,
                        onShowHistory: onShowHistory
                    )
                }
            }
            .padding(.horizontal, AaruSpace.large)
            .padding(.top, AaruSpace.xsmall)
            .padding(.bottom, AaruSpace.medium)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        // Follows the content; the card's height cap takes the rest, and then this scrolls.
        .frame(maxHeight: contentHeight)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .modifier(PinnedToBottom(turnCount: model.turns.count))
    }
}

/// Keeps a scroll view on its last line while the reply streams, until the person scrolls up. A
/// new Chat turn pins it again.
private struct PinnedToBottom: ViewModifier {
    let turnCount: Int

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isPinned = true

    private static let tolerance: CGFloat = 24

    private struct Extent: Equatable {
        let content: CGFloat
        let viewport: CGFloat
        let gapBelow: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Extent.self) { geometry in
                Extent(
                    content: geometry.contentSize.height,
                    viewport: geometry.containerSize.height,
                    gapBelow: geometry.contentSize.height - geometry.visibleRect.maxY
                )
            } action: { old, new in
                // Only a scroll with nothing resized is the person's: growing text and a rising
                // keyboard open a gap too, and that gap is what pinning closes.
                if old.content == new.content, old.viewport == new.viewport {
                    isPinned = new.gapBelow <= Self.tolerance
                } else if isPinned {
                    position.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: turnCount) {
                isPinned = true
                position.scrollTo(edge: .bottom)
            }
    }
}
