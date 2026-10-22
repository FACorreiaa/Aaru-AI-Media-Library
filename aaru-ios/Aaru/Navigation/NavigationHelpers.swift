import SwiftUI

extension View {
    /// iPhone and a compact iPad window: the account button (`person.crop.circle`, top
    /// trailing) that presents Settings as a sheet (§18). Regular width has Settings in the
    /// sidebar and the Mac has its Settings scene, so it shows nothing there.
    func accountButton() -> some View {
        #if os(iOS)
            modifier(AccountButtonModifier())
        #else
            self
        #endif
    }

    /// Reloads when ⌘R (View → Refresh) is chosen while `tab` is the selected destination.
    func refreshesOnCommand(_ tab: AppTab, perform action: @escaping () async -> Void) -> some View {
        modifier(RefreshCommandModifier(tab: tab, action: action))
    }
}

#if os(iOS)
    private struct AccountButtonModifier: ViewModifier {
        @Environment(AppRouter.self) private var router
        @Environment(\.horizontalSizeClass) private var sizeClass

        func body(content: Content) -> some View {
            content.toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "person.crop.circle") { router.openSettings() }
                    }
                }
            }
        }
    }
#endif

private struct RefreshCommandModifier: ViewModifier {
    let tab: AppTab
    let action: () async -> Void
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.onChange(of: router.refreshTick) {
            guard router.tab == tab else { return }
            Task { await action() }
        }
    }
}
