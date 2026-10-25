import StoreKit
import SwiftUI

/// Asks the system for the rating sheet once a success or a milestone makes a prompt due: after
/// about 1.5 s for animations to settle, and only while this view is on screen, the app is active
/// and the prompt is still due. Anything else lets the moment pass.
///
/// `hold` keeps the ask back while something else is celebrating (the unlock toast, a badge
/// reveal, a progress read that may bring one), so the system sheet never covers a badge. Each
/// time it lets go the settle starts again. Attached once, over the signed-in app.
struct ReviewPromptPresenter: ViewModifier {
    let prompter: ReviewPrompter
    let hold: Bool
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // A new id cancels the wait: a hold that starts, or a prompt that is no longer due.
            .task(id: prompter.isPromptDue && !hold) {
                guard prompter.isPromptDue, !hold else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                guard scenePhase == .active, prompter.shouldPrompt else {
                    prompter.skipPrompt()
                    return
                }
                prompter.didPrompt()
                requestReview()
            }
            // The window closed: a prompt waiting on it has passed.
            .onDisappear {
                if prompter.isPromptDue {
                    prompter.skipPrompt()
                }
            }
    }
}

extension View {
    /// Asks for an App Store rating when `prompter` says one is due, unless `hold` is on.
    func reviewPrompt(_ prompter: ReviewPrompter = .shared, holdWhile hold: Bool = false) -> some View {
        modifier(ReviewPromptPresenter(prompter: prompter, hold: hold))
    }
}
