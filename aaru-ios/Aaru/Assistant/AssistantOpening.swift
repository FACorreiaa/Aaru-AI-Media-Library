import Foundation

extension AssistantModel {
    /// What a card that just opened starts with: a question a screen asked for the person ("Ask
    /// Aaru for more"), sent as if typed here, or the microphone after a long press.
    func begin(_ presentation: AssistantPresentation) {
        // From idle only: while listening, toggling would stop the recording.
        guard phase == .idle, !hold(presentation.question) else { return }
        if let question = presentation.question {
            send(question)
        } else if presentation.listening, voiceAvailable {
            toggleListening()
        }
    }

    /// The card's ask was answered with Allow: a question held for it goes now.
    func aiSharingAllowed() {
        guard let question = heldQuestion else { return }
        heldQuestion = nil
        send(question)
    }

    /// The card asks about AI sharing instead of sending; `question` waits for the answer.
    func hold(_ question: String?) -> Bool {
        guard aiSharing?.needsAsk == true else { return false }
        heldQuestion = question
        return true
    }

    /// Unstructured: the next flow waits for this one, and should not wait for a status read.
    /// `ChatThread` gives a refusal's words but not its code, so AI sharing is read again too: if
    /// the answer changed on another device (`ai_sharing_required`), the card asks.
    func refreshStatusSoon() {
        Task { [weak self] in
            await self?.refreshStatus()
            await self?.aiSharing?.refresh()
        }
    }
}
