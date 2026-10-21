import SwiftUI

// The mindspace layer (DESIGN.md "Mindspace"): the Field and the Title room stand in a lit,
// constructed room; every other screen is plain Paper. Everything here is static: drawn once
// per size, never animated, and gone when the viewer asks for less transparency or more
// contrast.

/// The local hour, in four parts, the same split as the web (`lib/appearance.ts`).
enum Daypart {
    case dawn, day, dusk, night

    init(hour: Int) {
        switch hour {
        case 5 ..< 8: self = .dawn
        case 8 ..< 17: self = .day
        case 17 ..< 21: self = .dusk
        default: self = .night
        }
    }

    static var now: Daypart {
        Daypart(hour: Calendar.current.component(.hour, from: .now))
    }

    /// "Tuesday evening".
    func heading(on date: Date = .now) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide))
        switch self {
        case .dawn: return "\(weekday) morning"
        case .day: return weekday
        case .dusk: return "\(weekday) evening"
        case .night: return "\(weekday) night"
        }
    }
}

/// Paper with the room's light: a warmer or cooler wash from the top by time of day, and a
/// band of reed-like hairlines along the top edge that reads, up close, as encoded rhythm.
/// `seed` varies the rhythm (the Title room passes its title's id).
struct FieldBackground: View {
    var seed: String = "field"
    var daypart: Daypart = .now
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .top) {
            Color(.paper)
            if !reduceTransparency, contrast != .increased {
                LinearGradient(colors: [wash, .clear], startPoint: .top, endPoint: .center)
                ReedCode(seed: seed)
                    .frame(height: 160)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var wash: Color {
        switch daypart {
        case .dawn: Color(.gold).opacity(0.10)
        case .day: Color(.accent).opacity(0.05)
        case .dusk: Color(.gold).opacity(0.14)
        case .night: Color(.accent).opacity(0.10)
        }
    }
}

/// Hairlines of varying height, like reeds or a barcode, from a stable per-seed sequence.
struct ReedCode: View {
    let seed: String

    var body: some View {
        Canvas { context, size in
            var state = seed.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
            let pitch: CGFloat = 6
            var x: CGFloat = pitch / 2
            while x < size.width {
                // xorshift: deterministic, cheap, no Foundation randomness
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                let share = 0.25 + CGFloat(state % 1000) / 1000 * 0.75
                let rect = CGRect(x: x, y: 0, width: 0.75, height: size.height * share)
                context.fill(Path(rect), with: .color(Color(.ink).opacity(0.07)))
                x += pitch
            }
        }
    }
}

private struct EdgeLit: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    contrast == .increased
                        ? AnyShapeStyle(Color(.ink).opacity(0.4))
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [Color(.gold).opacity(0.6), Color(.line)],
                                startPoint: .top, endPoint: .center
                            )
                        ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// A hairline border lit gold along the top edge, for the one or two focal pieces on a page.
    func edgeLit(cornerRadius: CGFloat = 14) -> some View {
        modifier(EdgeLit(cornerRadius: cornerRadius))
    }

    /// A raised panel: Surface, a hairline, the panel radius.
    func panel(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.surface), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.line), lineWidth: 1)
            }
    }
}
