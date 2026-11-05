import AaruAPI
import SwiftUI

extension EnvironmentValues {
    /// The host an owl here opens the Assistant card over; nil is the root host.
    @Entry var assistantHostID: UUID?
}

extension View {
    /// Mounts the card here. The root passes `isSheet: false`. A sheet's content passes true, because a
    /// card on the tab view would sit behind a sheet; the owl inside it carries this host's id.
    func assistantHost(api: Client?, library: LibraryModel, lists: ListsModel, isSheet: Bool) -> some View {
        modifier(AssistantHost(api: api, library: library, lists: lists, isSheet: isSheet))
    }
}

private struct AssistantHost: ViewModifier {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let isSheet: Bool

    /// Both nil in previews.
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(AssistantModel.self) private var model: AssistantModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// This sheet's, when the host is in one.
    @Environment(\.dismiss) private var dismiss
    @State private var hostID: UUID?
    /// A title tapped in the card. A sheet works whether this host is the root or itself in a sheet.
    @State private var openedTitle: CatalogHit?

    init(api: Client?, library: LibraryModel, lists: ListsModel, isSheet: Bool) {
        self.api = api
        self.library = library
        self.lists = lists
        self.isSheet = isSheet
        _hostID = State(initialValue: isSheet ? UUID() : nil)
    }

    /// Not `router?.assistant?.hostID == hostID`: that flattens, and closed reads as the root.
    private var isOpen: Bool {
        router?.assistant.map { $0.hostID == hostID } ?? false
    }

    private var rise: Animation {
        reduceMotion ? AaruMotion.ease(AaruMotion.fast) : .spring(duration: AaruMotion.slow, bounce: 0.12)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.assistantHostID, hostID)
            // The card's own swipe must not take the sheet under it along.
            .interactiveDismissDisabled(isSheet && isOpen)
            .overlay { overlay }
            .sheet(item: $openedTitle) { hit in
                AssistantOpenedTitle(hit: hit, api: api, library: library, lists: lists) { openedTitle = nil }
            }
            // At the root only, so a change is handled once.
            .onChange(of: router?.assistant) {
                guard !isSheet, let model else { return }
                if let presentation = router?.assistant {
                    model.opened(presentation)
                } else {
                    model.closed()
                }
            }
            // A sheet can go with the card still up (a share link closes sheets): nothing would
            // close it then, and the mic would stay on.
            .onDisappear {
                guard isSheet, isOpen else { return }
                router?.closeAssistant()
            }
    }

    private var overlay: some View {
        ZStack(alignment: .bottom) {
            if isOpen {
                AssistantScrim { router?.closeAssistant() }
                    .transition(.opacity)
            }
            if isOpen, let model {
                AssistantCard(
                    model: model,
                    api: api,
                    library: library,
                    opensListening: router?.assistant?.listening ?? false,
                    onClose: { router?.closeAssistant() },
                    onOpenTitle: open,
                    onShowHistory: showHistory
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(rise, value: isOpen)
    }

    private func open(_ title: TitleSummary) {
        router?.closeAssistant()
        openedTitle = CatalogHit(title)
    }

    private func showHistory() {
        guard let router else { return }
        router.closeAssistant()
        #if os(iOS)
            // History is in a sheet on iPhone and a tab on iPad, and one sheet can't show over
            // another from the root: this one closes first, as `PlanSheet` does.
            if isSheet {
                router.closeSheets()
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    router.openHistory()
                }
                return
            }
        #endif
        router.openHistory()
    }
}

/// A title opened from the card, in its own sheet. `TitlePreviewView` swaps to the Title room when
/// the title is in the library. Nominal on purpose: its owl needs a host too, and a named struct is
/// what breaks the opaque-type cycle between this view and `AssistantHost`.
private struct AssistantOpenedTitle: View {
    let hit: CatalogHit
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            TitlePreviewView(hit: hit, api: api, library: library, lists: lists)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onDone)
                    }
                }
                .catalogDestination(api: api, library: library, lists: lists)
        }
        .assistantHost(api: api, library: library, lists: lists, isSheet: true)
        #if os(macOS)
            .frame(minWidth: 520, idealWidth: 640, minHeight: 640, idealHeight: 760)
        #endif
    }
}
