import SwiftUI

/// LIB-005: Library, Lists and Discover show 20 at a time and show 20 more as the end scrolls
/// into view. Their filter searches every item, not only those shown, by the web's rule
/// (`aaru-client/src/lib/paging.ts`).
enum Paging {
    static let pageSize = 20

    /// True when every word of `query` starts a word of one of `fields` ("fri" finds
    /// "Frieren", "pokemon" finds "Pokémon"). An empty query matches everything.
    static func matches(_ query: String, _ fields: String?...) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return true }
        let haystack = fields.compactMap(\.self).flatMap(words)
        return wanted.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
    }

    /// Lowercased, accents and punctuation folded away.
    private static func words(_ text: String) -> [Substring] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
    }
}

/// Sits after the last shown item: once it scrolls into view, 20 more are shown. A new
/// identity per step, so a screen tall enough to still show it asks again.
struct LoadMore: View {
    @Binding var shown: Int
    let total: Int

    var body: some View {
        if shown < total {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .id(shown)
                .onAppear { shown += Paging.pageSize }
        }
    }
}
