import AaruAPI
import Foundation

/// GRP-011: "Aaru is thinking…" from `agent.thinking` until the answer arrives, or 90 seconds.
extension ChannelModel {
    static let thinkingLifetime: TimeInterval = 90

    func noteThinking(_ mention: String) {
        thinking[mention] = Date().addingTimeInterval(Self.thinkingLifetime)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.thinkingLifetime + 0.1))
            guard let self else { return }
            let now = Date()
            thinking = thinking.filter { $0.value > now }
        }
    }

    /// An answer ends the wait for the mention it replies to.
    func answered(_ message: GroupMessage) {
        if message.fromAgent, let mention = message.replyTo {
            thinking[mention] = nil
        }
    }
}
