import AaruAPI
import Foundation

// How people and reactions read: pure helpers, out of `SocialModel.swift` to keep it under the
// file limit.

extension SocialUser {
    /// "Ana · @ana", or "@ana" when there is no name.
    var label: String {
        displayName.map { "\($0) · @\(handle)" } ?? "@\(handle)"
    }

    /// One or two letters for a monogram.
    var monogram: String {
        let words = (displayName ?? "").split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return String(words.first?.first ?? handle.first ?? "?").uppercased()
    }
}

extension SocialModel {
    /// The row with the viewer's reaction set to `emoji` (or cleared), counts kept in step.
    static func reacted(_ item: ActivityItem, _ emoji: String?) -> ActivityItem {
        var counts = Dictionary((item.reactions ?? []).map { ($0.emoji, $0.count) }) { first, _ in first }
        if let mine = item.myReaction {
            counts[mine, default: 1] -= 1
        }
        if let emoji {
            counts[emoji, default: 0] += 1
        }
        var copy = item
        let kept = counts.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        copy.reactions = kept.isEmpty ? nil : kept.map { .init(emoji: $0.key, count: $0.value) }
        copy.myReaction = emoji
        return copy
    }
}
