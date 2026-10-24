import SwiftUI

/// `@` suggestions while typing, for every composer that tags people: Groups (members, and
/// `@aaru` where it answers) and the Board (friends, never `@aaru` until BOARD-004).
enum MentionSuggestions {
    /// The `@` word being typed at the end of `text`, without the `@`, lowercased. Nil when the
    /// last word is not a tag or a space follows it.
    static func prefix(in text: String) -> String? {
        let word = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard text.last?.isWhitespace != true, word.hasPrefix("@") else { return nil }
        return String(word.dropFirst()).lowercased()
    }

    /// Handles to suggest for what is typed: Aaru first when `agent` is on, then up to five of
    /// `handles` that start with the prefix, in the order given.
    static func suggestions(for text: String, handles: [String], agent: Bool = false) -> [String] {
        guard let prefix = prefix(in: text) else { return [] }
        let agentHandle = agent && "aaru".hasPrefix(prefix) ? ["aaru"] : []
        return agentHandle + handles.filter { $0.hasPrefix(prefix) }.prefix(5)
    }

    /// `text` with its last `@` word replaced by `@handle `.
    static func complete(_ text: String, with handle: String) -> String {
        guard let range = text.range(of: "@", options: .backwards) else { return text }
        var completed = text
        completed.replaceSubrange(range.lowerBound..., with: "@\(handle) ")
        return completed
    }
}

/// The suggestions in a row of buttons above or below a composer's field. Empty draws nothing.
struct MentionSuggestionStrip: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AaruSpace.small) {
                    ForEach(suggestions, id: \.self) { handle in
                        Button {
                            onPick(handle)
                        } label: {
                            Label("@\(handle)", systemImage: handle == "aaru" ? "bird" : "at")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
