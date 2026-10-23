import SwiftUI

/// A Form or List on Paper instead of the system grouped grey, the way every Settings page reads:
/// grouped, its scroll background hidden, Paper behind it. Cells keep the system's grouped cell;
/// SwiftUI sets a row's background from the row, not from the list, so a page that wants Surface
/// cells says `.listRowBackground(Color(.surface))` on its sections.
private struct PaperPage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
    }
}

// The resting layers (DESIGN.md "Elevation"): Paper, Surface and Stone sit flat and separate by
// tint and a hairline, never by a shadow. Corners are always continuous, from `AaruRadius`.

/// A card: Surface, the card radius, a hairline.
private struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.surface), in: .rect(cornerRadius: AaruRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AaruRadius.card, style: .continuous)
                    .strokeBorder(Color(.line), lineWidth: 1)
            }
    }
}

/// A well: Stone, the field radius, a hairline inset — a sunk area such as a code or a quote.
private struct Well: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.stone), in: .rect(cornerRadius: AaruRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous)
                    .strokeBorder(Color(.line), lineWidth: 1)
            }
    }
}

/// A field: Paper, the field radius, the strong line, so an input reads as one on any surface.
private struct InputField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.paper), in: .rect(cornerRadius: AaruRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous)
                    .strokeBorder(Color(.lineStrong), lineWidth: 1)
            }
    }
}

/// The one shadow. Floating layers only: a sheet's own card, a toast, a dragged card. A card or
/// panel at rest never casts it.
private struct Lift: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(.lineStrong), lineWidth: 1)
            }
            .shadow(color: Color(.shadow), radius: 16, y: 8)
    }
}

extension View {
    /// Draws this Form or List on Paper (`PaperPage`). Settings pages add their title and problem
    /// banner on top through `settingsPage(_:problem:)`.
    func paperPage() -> some View {
        modifier(PaperPage())
    }

    /// Surface with the card radius and a hairline (`Card`). Padding stays with the caller.
    func card() -> some View {
        modifier(Card())
    }

    /// Stone with the field radius and an inset hairline (`Well`).
    func well() -> some View {
        modifier(Well())
    }

    /// Paper with the field radius and the strong line (`InputField`), for text inputs.
    func field() -> some View {
        modifier(InputField())
    }

    /// The one shadow, with a strong line on the clip shape (`Lift`). Floating layers only: a
    /// sheet's custom card, a toast, a dragged card. `cornerRadius` is the shape the view is
    /// clipped to.
    func lift(cornerRadius: CGFloat = AaruRadius.panel) -> some View {
        modifier(Lift(cornerRadius: cornerRadius))
    }
}
