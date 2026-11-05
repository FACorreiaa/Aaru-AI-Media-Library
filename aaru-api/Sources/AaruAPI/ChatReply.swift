import Foundation

/// What one Chat turn's answer looks like so far, built from the frames of its stream (ASK-009).
///
/// Pure state: no I/O. Once the reply has ended (answered, stopped, cut off, cancelled or
/// failed) later frames and endings change nothing.
public struct ChatReply: Sendable {
    public enum State: Sendable, Equatable {
        case working, answered, stopped, cutOff, cancelled, failed
    }

    public private(set) var text = ""
    public private(set) var status: String?
    public private(set) var titles: [Components.Schemas.TitleSummary] = []
    public private(set) var plan: Components.Schemas.AgentPlan?
    /// A list Aaru sent to be matched (BOOK-003): a capture the person reviews like any other.
    public private(set) var importID: String?
    public private(set) var actionID: String?
    public private(set) var actionSummary: String?
    public private(set) var state: State = .working
    public private(set) var problem: String?

    public init() {}

    public mutating func apply(_ frame: ChatFrame) {
        guard state == .working else { return }
        switch frame {
        case let .status(line):
            status = line
        case let .delta(piece):
            text += piece
            status = nil
        case let .components(components):
            merge(components)
        case .done:
            status = nil
            state = .answered
        case let .error(_, message):
            status = nil
            problem = message
            state = .stopped
        }
    }

    /// The stream closed. Without a `done` or `error` first, the answer was cut off.
    public mutating func streamEnded() {
        guard state == .working else { return }
        status = nil
        problem = "That answer was cut off. Ask again."
        state = .cutOff
    }

    /// The person closed the card. What was written stays; a write already applied stays journaled.
    public mutating func cancel() {
        guard state == .working else { return }
        status = nil
        state = .cancelled
    }

    public mutating func fail(_ problem: String) {
        guard state == .working else { return }
        status = nil
        self.problem = problem
        state = .failed
    }

    private mutating func merge(_ components: Components.Schemas.ChatComponentsFrame) {
        for title in components.titles ?? [] where !titles.contains(where: { $0.id == title.id }) {
            titles.append(title)
        }
        plan = components.plan ?? plan
        importID = components.importId ?? importID
        actionID = components.actionId ?? actionID
        actionSummary = components.actionSummary ?? actionSummary
    }
}
