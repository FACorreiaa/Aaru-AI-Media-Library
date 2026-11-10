import Foundation

extension AssistantModel {
    /// What a card that just opened starts with: a question a screen asked for the person ("Ask
    /// Aaru for more"), sent as if typed here, or the microphone after a long press.
    func begin(_ presentation: AssistantPresentation) {
        // From idle only: while listening, toggling would stop the recording.
        guard phase == .idle else { return }
        if let question = presentation.question {
            send(question)
        } else if presentation.listening, voiceAvailable {
            toggleListening()
        }
    }
}
