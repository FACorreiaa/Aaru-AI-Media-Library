import SwiftUI

/// Aaru's display style for titles and headings: the system sans (SF Pro), as in the brand
/// poster (DESIGN.md "Brand"). Headings differ from body text by weight and size, not by family,
/// and every size is a text style, so Dynamic Type scales them with everything else.
extension Font {
    /// The display style at a text style's size. `.semibold` for page titles, `.medium` otherwise.
    static func aaruDisplay(_ style: Font.TextStyle, weight: Font.Weight = .medium, italic: Bool = false) -> Font {
        let font = Font.system(style, design: .default, weight: weight)
        return italic ? font.italic() : font
    }

    /// The display style at a fixed size, for story cards and shared images whose layout is
    /// drawn to size (Recap). Everything else uses a text style.
    static func aaruDisplay(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension View {
    /// A small uppercase label above a heading ("THE FIELD", "TONIGHT").
    func eyebrow() -> some View {
        font(.caption.weight(.semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Color(.muted))
    }
}
