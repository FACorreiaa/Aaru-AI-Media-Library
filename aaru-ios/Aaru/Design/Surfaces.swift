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

extension View {
    /// Draws this Form or List on Paper (`PaperPage`). Settings pages add their title and problem
    /// banner on top through `settingsPage(_:problem:)`.
    func paperPage() -> some View {
        modifier(PaperPage())
    }
}
