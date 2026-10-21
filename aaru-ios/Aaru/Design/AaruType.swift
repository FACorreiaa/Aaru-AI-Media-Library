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

    /// The text style's size at the default content size, per platform.
    fileprivate static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
            switch style {
            case .largeTitle: 26
            case .title: 22
            case .title2: 17
            case .title3: 15
            case .headline, .body: 13
            case .callout: 12
            case .subheadline, .footnote: 11
            case .caption, .caption2: 10
            @unknown default: 13
            }
        #else
            switch style {
            case .largeTitle: 34
            case .title: 28
            case .title2: 22
            case .title3: 20
            case .headline, .body: 17
            case .callout: 16
            case .subheadline: 15
            case .footnote: 13
            case .caption: 12
            case .caption2: 11
            @unknown default: 17
            }
        #endif
    }
}

extension Font {
    /// Newsreader at a text style's size. `.semibold` for page titles, `.medium` otherwise.
    static func aaruDisplay(_ style: Font.TextStyle, weight: Font.Weight = .medium, italic: Bool = false) -> Font {
        let name = italic ? "Newsreader-MediumItalic" : weight == .semibold ? "Newsreader-SemiBold" : "Newsreader-Medium"
        return .custom(name, size: AaruType.baseSize(style), relativeTo: style)
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
