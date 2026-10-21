import AaruAPI
import SwiftUI

/// GAM-006a: the Recap story, the twin of the web's `RecapStory`. Tap the right of a card to go on,
/// the left to go back, hold to pause; arrows and Esc with a keyboard. Cards advance on their own
/// unless Reduce Motion is on, in which case they cross-fade and wait for a tap.
struct RecapView: View {
    @State var model: RecapModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var elapsed: Double = 0
    @State private var held = false
    @State private var pressedAt: Date?

    static let cardSeconds = 6.0
    private static let tick = 0.1
    /// Shorter than this, a press is a tap; longer, it was a hold.
    private static let tapSeconds = 0.25

    private var deck: [RecapCard] {
        model.deck
    }

    private var backdrop: (background: Color, foreground: Color) {
        guard !deck.isEmpty else { return (Color(.paper), Color(.ink)) }
        switch index % 3 {
        case 0: return (Color(.ink), Color(.paper))
        case 1: return (Color(.accent), Color(.paper))
        default: return (Color(.surface), Color(.ink))
        }
    }

    var body: some View {
        ZStack {
            backdrop.background.ignoresSafeArea()
            if let stats = model.stats, !deck.isEmpty {
                story(stats)
            } else {
                placeholder
            }
        }
        .foregroundStyle(backdrop.foreground)
        .animation(.smooth(duration: 0.5), value: index)
        .task { await model.load() }
        .task(id: index) { await autoAdvance() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { go(index + 1); return .handled }
        .onKeyPress(.space) { go(index + 1); return .handled }
        .onKeyPress(.leftArrow) { go(index - 1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func story(_ stats: Stats) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                progressBars
                closeButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            GeometryReader { proxy in
                RecapCardView(card: deck[index], stats: stats)
                    .frame(maxWidth: 560, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(index)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .contentShape(Rectangle())
                    .gesture(press(width: proxy.size.width))
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Next card") { go(index + 1) }
            .accessibilityAction(named: "Previous card") { go(index - 1) }
        }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(deck.indices, id: \.self) { position in
                Capsule()
                    .fill(.primary.opacity(0.25))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().frame(width: proxy.size.width * progress(position))
                        }
                    }
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .padding(8)
            .contentShape(Circle())
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            if let problem = model.problem {
                Text(problem).multilineTextAlignment(.center)
                Button("Try again") { Task { await model.load() } }.buttonStyle(.bordered)
            } else if model.isEmpty {
                Text("Nothing tracked in \(model.period.label) yet")
                    .font(.aaruDisplay(.title2))
                Text("Tick an episode or finish a title, and it will show up here.")
                    .foregroundStyle(Color(.muted))
                    .multilineTextAlignment(.center)
            } else {
                ProgressView("Gathering your \(model.period.label)…")
            }
            Button("Close") { dismiss() }.buttonStyle(.borderless)
        }
        .padding(32)
    }

    private func progress(_ position: Int) -> Double {
        if position < index {
            return 1
        }
        if position > index {
            return 0
        }
        return reduceMotion ? 1 : min(1, elapsed / Self.cardSeconds)
    }

    private func go(_ target: Int) {
        guard !deck.isEmpty else { return }
        index = max(0, min(deck.count - 1, target))
        elapsed = 0
    }

    private func press(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressedAt == nil {
                    pressedAt = .now
                    held = true
                }
            }
            .onEnded { value in
                defer {
                    pressedAt = nil
                    held = false
                }
                guard let pressedAt, Date.now.timeIntervalSince(pressedAt) < Self.tapSeconds else { return }
                go(value.location.x < width / 3 ? index - 1 : index + 1)
            }
    }

    private func autoAdvance() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.tick))
            guard !Task.isCancelled, !reduceMotion, !held, !deck.isEmpty else { continue }
            if elapsed + Self.tick < Self.cardSeconds {
                elapsed += Self.tick
            } else if index < deck.count - 1 {
                go(index + 1)
            } else {
                // The last card fills its bar, then stays.
                elapsed = Self.cardSeconds
            }
        }
    }
}

extension View {
    /// Presents the Recap story for `period`: full screen on iPhone and iPad, a window-sized sheet on Mac.
    func recapStory(_ period: Binding<RecapPeriod?>, api: Client?) -> some View {
        #if os(iOS)
            fullScreenCover(item: period) { RecapView(model: RecapModel(period: $0, api: api)) }
        #else
            sheet(item: period) {
                RecapView(model: RecapModel(period: $0, api: api)).frame(minWidth: 480, minHeight: 720)
            }
        #endif
    }
}
