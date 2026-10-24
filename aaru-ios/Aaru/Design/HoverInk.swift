import SwiftUI

/// A quiet control's look: Muted at rest, Ink under the pointer (Mac, and iPad with a pointer).
/// The web's `text-muted hover:text-ink`. For plain text controls; a capsule like `UpvoteButton`
/// tints its fill instead.
private struct HoverInk: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(hovering ? Color(.ink) : Color(.muted))
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Muted, and Ink while the pointer is over it (`HoverInk`).
    func hoverInk() -> some View {
        modifier(HoverInk())
    }
}
