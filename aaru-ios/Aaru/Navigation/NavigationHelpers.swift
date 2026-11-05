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

    /// The owl in the top bar (ASK-009): opens the Assistant card over this screen. Beside Search,
    /// on every main screen; shown only while the server has the Assistant on.
    func assistantButton() -> some View {
        modifier(AssistantButtonModifier(titleID: nil, onTitlePage: false))
    }

    /// The owl on a title page: the card is told which title the user is looking at.
    func assistantButton(titleID: String?) -> some View {
        modifier(AssistantButtonModifier(titleID: titleID, onTitlePage: true))
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

private struct AssistantButtonModifier: ViewModifier {
    let titleID: String?
    let onTitlePage: Bool
    /// Nil in previews.
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(AssistantModel.self) private var model: AssistantModel?
    /// The host this screen is under: a sheet's, or nil for the root.
    @Environment(\.assistantHostID) private var hostID
    #if os(iOS)
        @State private var didLongPress = false
        @State private var longPresses = 0
    #endif

    func body(content: Content) -> some View {
        content.toolbar {
            if model?.isAvailable == true {
                ToolbarItem(placement: .primaryAction) { owl }
            }
        }
    }

    private var owl: some View {
        let button = Button(action: tapped) {
            OwlHead(size: 28)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ask Aaru")
        .accessibilityAction(named: "Talk to Aaru") { open(listening: true) }
        .help("Ask Aaru (⌘K)")
        #if os(iOS)
            // Holding the owl opens the card listening; the flag keeps the lift from also being a tap.
            return button
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    didLongPress = true
                    longPresses += 1
                    open(listening: true)
                    // A lift the button never reports must not swallow the next tap.
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        didLongPress = false
                    }
                })
                .sensoryFeedback(.impact, trigger: longPresses)
        #else
            return button
        #endif
    }

    private func tapped() {
        #if os(iOS)
            if didLongPress {
                didLongPress = false
                return
            }
        #endif
        open(listening: false)
    }

    private func open(listening: Bool) {
        router?.openAssistant(listening: listening, titleID: titleID, onTitlePage: onTitlePage, hostID: hostID)
    }
}

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
