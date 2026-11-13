import AaruAPI
import SwiftUI

/// ONB-001: a new account's first screens, once, before Home (DESIGN.md §0a). RootView shows it
/// in place of `MainTabs` (a branch, not a cover, so the Mac shows it too). Skip on every screen
/// ends the whole flow and keeps what was already saved.
struct OnboardingFlow: View {
    let notifications: NotificationsModel
    /// AI sharing (PRV-002): asked on its own screen unless this account has already answered.
    let aiSharing: AISharingModel
    /// The flow has ended; true when the user asked for Import instead.
    let onFinished: (_ openImport: Bool) -> Void

    @State private var model: OnboardingModel
    @State private var step: OnboardingScreen = .step(.kinds)
    /// Which way the last move went, so the next screen comes in from that side.
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        api: Client?, library: LibraryModel, notifications: NotificationsModel, aiSharing: AISharingModel,
        onFinished: @escaping (_ openImport: Bool) -> Void
    ) {
        self.notifications = notifications
        self.aiSharing = aiSharing
        self.onFinished = onFinished
        _model = State(initialValue: OnboardingModel(
            api: api, library: library, asksAISharing: aiSharing.state == .unanswered
        ))
    }

    var body: some View {
        ZStack {
            screen
                .id(step)
                .transition(transition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.paper).ignoresSafeArea())
        #if os(macOS)
            .frame(minWidth: 760, minHeight: 520)
        #endif
    }

    /// The screens slide in from the side they come from; with Reduce Motion they fade.
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading)
    }

    @ViewBuilder private var screen: some View {
        switch step {
        case .step(.kinds):
            KindsStep(
                model: model,
                onSkip: skip,
                onContinue: { advance() },
                onImport: {
                    model.finish(skipped: false)
                    onFinished(true)
                }
            )
        case let .step(.pick(kind)):
            PickerStep(model: model, kind: kind, onBack: back, onSkip: skip) {
                Task {
                    if await model.save(kind) {
                        await move()
                    }
                }
            }
        case .step(.favorites):
            FavoritesStep(model: model, onBack: back, onSkip: skip) { advance() }
        case .step(.related):
            RelatedStep(model: model, onBack: back, onSkip: skip) {
                Task {
                    if await model.saveRelated() {
                        await move()
                    }
                }
            }
        case .aiSharing:
            AISharingStep(model: aiSharing, onBack: back, onSkip: skip) { advance() }
        case .step(.notifications):
            NotificationsStep(
                sample: model.sampleAiring, notifications: notifications,
                onBack: back, onSkip: skip, onDone: { advance() }
            )
        }
    }

    private func advance() {
        Task { await move() }
    }

    /// To the next screen, or out at the end. The related screen and what comes after it depend
    /// on the related answer, so the move waits for it when the next screen is not a picker or
    /// favorites.
    private func move() async {
        let current = step
        var next = model.screen(after: current)
        if next?.waitsForRelated ?? true {
            await model.awaitRelated()
            next = model.screen(after: current)
        }
        guard let next else {
            model.finish(skipped: false)
            onFinished(false)
            return
        }
        go(to: next, forward: true)
    }

    private func back() {
        guard let previous = model.screen(before: step) else { return }
        go(to: previous, forward: false)
    }

    private func go(to next: OnboardingScreen, forward: Bool) {
        model.clearProblem()
        aiSharing.problem = nil
        self.forward = forward
        withAnimation(reduceMotion ? nil : AaruMotion.ease()) {
            step = next
        }
    }

    private func skip() {
        model.finish(skipped: true)
        onFinished(false)
    }
}

private extension OnboardingScreen {
    /// Related titles, and the screens that only follow once the related answer is in.
    var waitsForRelated: Bool {
        switch self {
        case .aiSharing, .step(.related), .step(.notifications): true
        case .step: false
        }
    }
}
