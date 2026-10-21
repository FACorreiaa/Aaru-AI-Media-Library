import CoreText
import SwiftUI

/// Aaru's display face, Newsreader (design/fonts.md), for titles and headings. Body and
/// interface text stay the system font. Every size is relative to a text style, so Dynamic
/// Type scales the serif with everything else.
enum AaruType {
    /// Registers the bundled faces for this process. Call once, at launch.
    static func registerFonts() {
        let urls = ["Newsreader-Medium", "Newsreader-SemiBold", "Newsreader-MediumItalic"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "ttf") }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// The bundled face for a weight: SemiBold from `.semibold` up, Medium below.
    fileprivate static func faceName(weight: Font.Weight, italic: Bool) -> String {
        if italic {
            return "Newsreader-MediumItalic"
        }
        return [.semibold, .bold, .heavy, .black].contains(weight) ? "Newsreader-SemiBold" : "Newsreader-Medium"
    }

    /// The text style's size at the default content size, per platform.
    fileprivate static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        baseSizes[style] ?? baseSizes[.body] ?? 17
    }

    #if os(macOS)
        private static let baseSizes: [Font.TextStyle: CGFloat] = [
            .largeTitle: 26, .title: 22, .title2: 17, .title3: 15, .headline: 13, .body: 13,
            .callout: 12, .subheadline: 11, .footnote: 11, .caption: 10, .caption2: 10,
        ]
    #else
        private static let baseSizes: [Font.TextStyle: CGFloat] = [
            .largeTitle: 34, .title: 28, .title2: 22, .title3: 20, .headline: 17, .body: 17,
            .callout: 16, .subheadline: 15, .footnote: 13, .caption: 12, .caption2: 11,
        ]
    #endif
}

extension Font {
    /// Newsreader at a text style's size. `.semibold` for page titles, `.medium` otherwise.
    static func aaruDisplay(_ style: Font.TextStyle, weight: Font.Weight = .medium, italic: Bool = false) -> Font {
        .custom(AaruType.faceName(weight: weight, italic: italic), size: AaruType.baseSize(style), relativeTo: style)
    }

    /// Newsreader at a fixed size, for story cards and shared images whose layout is drawn to
    /// size (Recap). Everything else uses a text style.
    static func aaruDisplay(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(AaruType.faceName(weight: weight, italic: false), fixedSize: size)
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
