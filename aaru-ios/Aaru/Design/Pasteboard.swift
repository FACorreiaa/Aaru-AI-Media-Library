#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Copies text to the system pasteboard on either platform.
enum Pasteboard {
    @MainActor
    static func copy(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
