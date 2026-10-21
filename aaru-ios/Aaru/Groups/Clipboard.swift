#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// The system pasteboard on either platform.
enum Clipboard {
    @MainActor
    static func copy(_ string: String) {
        #if os(iOS)
            UIPasteboard.general.string = string
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
