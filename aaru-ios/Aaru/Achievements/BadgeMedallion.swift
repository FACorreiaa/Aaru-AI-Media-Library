import AaruAPI
import SwiftUI

/// A badge's round mark (DESIGN.md §17): the glyph on Surface, ringed by tier. Tier 1 a Stone
/// ring, 2 an Ink ring, 3 a gold hairline, 4 a double gold hairline; gold is edge light and never
/// fills. Unearned is Stone at reduced contrast; a hidden badge not yet earned reads "???".
struct BadgeMedallion: View {
    let badge: String
    let family: Components.Schemas.BadgeFamily
    /// 0 for not earned.
    let tier: Int
    var secret = false
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(Color(.surface))
            ring
            if secret {
                Text("???")
                    .font(.system(size: size * 0.24, weight: .semibold))
                    .foregroundStyle(Color(.muted))
            } else {
                Image(systemName: BadgeGlyph.symbol(badge: badge, family: family))
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(tier > 0 ? Color(.ink) : Color(.muted))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .frame(width: size, height: size)
        .opacity(tier > 0 || secret ? 1 : 0.7)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var ring: some View {
        switch tier {
        case 4:
            Circle().strokeBorder(Color(.gold), lineWidth: 1)
            Circle().strokeBorder(Color(.gold), lineWidth: 1).padding(3)
        case 3:
            Circle().strokeBorder(Color(.gold), lineWidth: 1)
        case 2:
            Circle().strokeBorder(Color(.ink), lineWidth: 2)
        case 1:
            Circle().strokeBorder(Color(.stone), lineWidth: 2)
        default:
            Circle().strokeBorder(Color(.stone).opacity(AaruAlpha.half), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}

/// How badges read: glyphs, tier words, family names. The same words as the web's.
enum BadgeGlyph {
    /// A badge's SF Symbol: its own where one says it better, else its family's.
    static func symbol(badge: String, family: Components.Schemas.BadgeFamily) -> String {
        overrides[badge] ?? familySymbol(family)
    }

    static func familySymbol(_ family: Components.Schemas.BadgeFamily) -> String {
        familySymbols[family] ?? "rosette"
    }

    private static let familySymbols: [Components.Schemas.BadgeFamily: String] = [
        .films: "film", .shows: "tv", .anime: "sparkles.tv", .books: "book.closed", .music: "music.note",
        .ratings: "star", .lists: "list.bullet.rectangle", .imports: "shippingbox", .discovery: "safari",
        .streaks: "flame", .social: "person.2",
    ]

    private static let overrides: [String: String] = [
        "silver_screen": "theatermasks",
        "double_feature": "film.stack",
        "seasons": "square.stack.3d.up",
        "completionist": "checkmark.seal",
        "long_haul": "infinity",
        "binge": "forward.end",
        "marathon": "figure.run",
        "day_one": "calendar.badge.clock",
        "finale_night": "moon.haze",
        "pages": "book.pages",
        "doorstopper": "books.vertical",
        "chapter_a_day": "bookmark",
        "artists": "music.mic",
        "albums": "opticaldisc",
        "perfect_ten": "star.circle",
        "tough_crowd": "hand.thumbsdown",
        "notes": "note.text",
        "first_shelf": "rectangle.stack",
        "collector": "archivebox",
        "sources": "globe",
        "genres": "theatermask.and.paintbrush",
        "decades": "clock.arrow.circlepath",
        "networks": "antenna.radiowaves.left.and.right",
        "all_rounder": "circle.hexagongrid",
        "comeback": "arrow.uturn.up",
        "night_owl": "moon.stars",
        "ambassador": "envelope.open",
        "tastemaker": "hand.thumbsup",
        "good_call": "checkmark.bubble",
        "applause": "hands.clap",
        "watch_party": "popcorn",
    ]

    /// "Bronze", "Silver", "Gold", "Platinum"; nil for a badge with one tier.
    static func tierWord(_ tier: Int, of maxTier: Int) -> String? {
        guard maxTier > 1, (1 ... 4).contains(tier) else { return nil }
        return ["Bronze", "Silver", "Gold", "Platinum"][tier - 1]
    }

    static func familyName(_ family: Components.Schemas.BadgeFamily) -> String {
        // The raw values are the lowercase names; "anime" and the rest read capitalised.
        family.rawValue.capitalized
    }
}

#Preview {
    HStack(spacing: 16) {
        BadgeMedallion(badge: "films", family: .films, tier: 0)
        BadgeMedallion(badge: "films", family: .films, tier: 1)
        BadgeMedallion(badge: "films", family: .films, tier: 2)
        BadgeMedallion(badge: "films", family: .films, tier: 3)
        BadgeMedallion(badge: "films", family: .films, tier: 4)
        BadgeMedallion(badge: "long_haul", family: .shows, tier: 0, secret: true)
    }
    .padding()
    .background(Color(.paper))
}
