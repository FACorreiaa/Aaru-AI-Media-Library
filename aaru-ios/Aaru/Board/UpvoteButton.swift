import SwiftUI

/// Upvote (BOARD-003): ▲ and the count, in a capsule. The model applies it at once and puts it
/// back if the server says no. Yours is marked in the accent. A tap taps back on iPhone; the arrow
/// pops unless Reduce Motion is on.
struct UpvoteButton: View {
    let upvotes: Int
    let upvoted: Bool
    let onToggle: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var busy = false
    @State private var taps = 0
    @State private var pops = 0
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: AaruSpace.xsmall) {
                Image(systemName: upvoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .foregroundStyle(upvoted ? Color(.accent) : Color(.muted))
                    .phaseAnimator([1.0, 1.3, 1.0], trigger: pops) { arrow, scale in
                        arrow.scaleEffect(scale)
                    } animation: { _ in
                        .spring(duration: 0.2, bounce: 0.5)
                    }
                Text(upvotes, format: .number)
                    .foregroundStyle(upvoted ? Color(.ink) : Color(.muted))
                    .contentTransition(.numericText(value: Double(upvotes)))
                    .animation(reduceMotion ? nil : AaruMotion.ease(AaruMotion.fast), value: upvotes)
            }
            .font(.footnote.weight(.semibold).monospacedDigit())
            .padding(.horizontal, AaruSpace.medium)
            .padding(.vertical, AaruSpace.small)
            .background(fill, in: .capsule)
            .overlay {
                if upvoted {
                    Capsule().strokeBorder(Color(.accent).opacity(AaruAlpha.half))
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        #if os(iOS)
            .sensoryFeedback(.impact, trigger: taps)
        #endif
            .accessibilityLabel("Upvote, \(upvotes)")
            .accessibilityAddTraits(upvoted ? .isSelected : [])
    }

    private var fill: Color {
        if upvoted {
            return Color(.accent).opacity(AaruAlpha.wash)
        }
        return Color(.muted).opacity(hovering ? AaruAlpha.wash : AaruAlpha.tint)
    }

    /// One request at a time: a second tap while the first is on its way is dropped.
    private func toggle() {
        guard !busy else { return }
        busy = true
        taps += 1
        if !upvoted, !reduceMotion {
            pops += 1
        }
        Task {
            await onToggle()
            busy = false
        }
    }
}

#Preview {
    HStack {
        UpvoteButton(upvotes: 12, upvoted: false) {}
        UpvoteButton(upvotes: 3, upvoted: true) {}
    }
    .padding()
    .background(Color(.paper))
}
