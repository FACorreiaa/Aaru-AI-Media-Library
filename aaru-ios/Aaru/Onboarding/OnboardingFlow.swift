import AaruAPI
import SwiftUI

/// ONB-001: a new account's first screens, once, before Home (DESIGN.md §0a). RootView shows it
/// in place of `MainTabs` (a branch, not a cover, so the Mac shows it too). Skip on every screen
/// ends the whole flow and keeps what was already saved.
struct OnboardingFlow: View {
    let notifications: NotificationsModel
    /// The flow has ended; true when the user asked for Import instead.
    let onFinished: (_ openImport: Bool) -> Void

    @State private var model: OnboardingModel
    @State private var step: OnboardingStep = .kinds
    /// Which way the last move went, so the next screen comes in from that side.
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        api: Client?, library: LibraryModel, notifications: NotificationsModel,
        onFinished: @escaping (_ openImport: Bool) -> Void
    ) {
        self.notifications = notifications
        self.onFinished = onFinished
        _model = State(initialValue: OnboardingModel(api: api, library: library))
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
        case .kinds:
            KindsStep(
                model: model,
                onSkip: skip,
                onContinue: { advance(from: .kinds) },
                onImport: {
                    model.finish(skipped: false)
                    onFinished(true)
                }
            )
        case let .pick(kind):
            PickerStep(model: model, kind: kind, onBack: back, onSkip: skip) {
                Task {
                    if await model.save(kind) {
                        await move(from: .pick(kind))
                    }
                }
            }
        case .favorites:
            FavoritesStep(model: model, onBack: back, onSkip: skip) {
                Task { await move(from: .favorites) }
            }
        case .related:
            RelatedStep(model: model, onBack: back, onSkip: skip) {
                Task {
                    if await model.saveRelated() {
                        await move(from: .related)
                    }
                }
            }
        case .notifications:
            NotificationsStep(
                sample: model.sampleAiring, notifications: notifications,
                onBack: back, onSkip: skip, onDone: { advance(from: .notifications) }
            )
        }
    }

    private func advance(from current: OnboardingStep) {
        Task { await move(from: current) }
    }

    /// To the next screen, or out at the end. The related screen and the alerts after it depend
    /// on the related answer, so the move waits for it when the next screen is not a picker or
    /// favorites.
    private func move(from current: OnboardingStep) async {
        var next = model.step(after: current)
        if next == nil || next == .related || next == .notifications {
            await model.awaitRelated()
            next = model.step(after: current)
        }
        guard let next else {
            model.finish(skipped: false)
            onFinished(false)
            return
        }
        go(to: next, forward: true)
    }

    private func back() {
        guard let previous = model.step(before: step) else { return }
        go(to: previous, forward: false)
    }

    private func go(to next: OnboardingStep, forward: Bool) {
        model.clearProblem()
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
