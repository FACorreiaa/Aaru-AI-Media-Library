import SwiftUI

// The Recap cards' pieces and motion, out of `RecapCards.swift` to keep it under the file limit.

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.subheadline.weight(.medium))
            .tracking(1.8)
            .opacity(0.8)
            .rise(0)
    }
}

struct RecapBig<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.aaruDisplay(size: 88))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.top, 12)
            .rise(0.12)
    }
}

struct RecapLine: View {
    let text: String
    var delay = 0.36

    var body: some View {
        Text(text)
            .font(.title3)
            .opacity(0.9)
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.top, 20)
            .rise(delay)
    }
}

struct RecapTopRow: View {
    let entry: StatsTitle
    let rank: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(rank)")
                .font(.aaruDisplay(.title2))
                .monospacedDigit()
                .opacity(0.7)
                .frame(width: 24, alignment: .leading)
            RecapPoster(url: entry.title.posterURL, kind: entry.title.mediaKind).frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.title).font(.aaruDisplay(.title3)).lineLimit(1)
                Text(entry.episodes > 0 ? "\(entry.episodes) episodes" : "\(entry.minutes) minutes")
                    .font(.subheadline)
                    .opacity(0.75)
            }
        }
    }
}

struct RecapMoment: View {
    let label: String
    let moment: StatsMoment

    var body: some View {
        HStack(spacing: 16) {
            RecapPoster(url: moment.title.posterURL, kind: moment.title.mediaKind).frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label) · \(moment.at.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .opacity(0.75)
                Text(moment.title.title).font(.aaruDisplay(size: 28))
            }
        }
    }
}

/// One bar per month or day; the busiest is solid, the rest translucent. Bars grow from the
/// baseline in sequence.
struct RecapBarChart: View {
    let bars: [RecapCard.Bar]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { offset, bar in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .opacity(bar.busiest ? 1 : 0.35)
                                .frame(height: max(bar.height > 0 ? 4 : 1, proxy.size.height * bar.height))
                                .scaleEffect(y: grown ? 1 : 0, anchor: .bottom)
                                .animation(
                                    reduceMotion ? nil : .spring(duration: 0.7).delay(0.2 + Double(offset) * 0.035),
                                    value: grown
                                )
                        }
                    }
                    if bars.count <= 12 {
                        Text(bar.label).font(.caption2).opacity(0.7)
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityHidden(true)
        .onAppear { grown = true }
    }
}

/// Counts from zero to `value` once, digits rolling; the final number at once with Reduce Motion.
struct RecapCountUp: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text(shown.formatted())
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                guard !reduceMotion else {
                    shown = value
                    return
                }
                withAnimation(.smooth(duration: 1.2).delay(0.15)) { shown = value }
            }
            .accessibilityLabel(value.formatted())
    }
}

struct RecapEntrance: ViewModifier {
    let delay: Double
    let pop: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion || pop ? 0 : 12)
            .scaleEffect(shown || reduceMotion || !pop ? 1 : 0.85)
            .rotationEffect(.degrees(shown || reduceMotion || !pop ? 0 : -2))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(pop ? .spring(duration: 0.7, bounce: 0.35).delay(delay) : .smooth(duration: 0.6)
                    .delay(delay))
                {
                    shown = true
                }
            }
    }
}

extension View {
    /// Fades and lifts in after `delay` seconds.
    func rise(_ delay: Double) -> some View {
        modifier(RecapEntrance(delay: delay, pop: false))
    }

    /// Springs in from slightly small and tilted.
    func pop(_ delay: Double) -> some View {
        modifier(RecapEntrance(delay: delay, pop: true))
    }
}

/// A poster with a hairline in the card's ink: the placeholder is Surface, which is also one of
/// the story's backdrops.
struct RecapPoster: View {
    let url: URL?
    let kind: MediaKind

    var body: some View {
        PosterView(url: url, kind: kind)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.2), lineWidth: 1))
    }
}
