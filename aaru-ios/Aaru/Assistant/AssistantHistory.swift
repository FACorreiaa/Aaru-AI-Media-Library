import AaruAPI
import Foundation
import Observation

/// The owl card's history (ASK-011): the list of past chats, whether the card shows it, and
/// opening one or starting a new chat. The turns themselves stay the `AssistantModel`'s.
@MainActor
@Observable
final class AssistantHistory {
    /// What the card shows: the chat, or the list of past chats.
    enum Panel: Equatable {
        case chat, list
    }

    var panel = Panel.chat
    let chats: ChatsModel
    /// A chat is being fetched.
    private(set) var opening = false
    /// Why a chat did not open.
    private(set) var problem: String?

    @ObservationIgnored weak var assistant: AssistantModel?
    @ObservationIgnored private let api: Client?
    /// Bumped on sign-out, so a chat still on its way does not show for the next account.
    @ObservationIgnored private var account = 0

    init(api: Client?) {
        self.api = api
        chats = ChatsModel(api: api)
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .aaruChatDeleted) {
                guard let self else { return }
                if let id = note.object as? String {
                    await chatDeleted(id)
                }
            }
        }
    }

    /// The card opens on the chat, never on the list.
    func cardOpened() {
        panel = .chat
        problem = nil
    }

    /// Ends the chat on screen and starts an empty one. The old one stays in the list.
    func newChat() async {
        panel = .chat
        await assistant?.show(nil)
    }

    /// Shows a chat from the list; the next question continues it.
    func open(_ id: String) async {
        guard let api, !opening else { return }
        opening = true
        problem = nil
        defer { opening = false }
        let started = account
        switch await api.storedChat(id) {
        case let .loaded(chat):
            guard started == account else { return }
            await assistant?.show(chat)
            panel = .chat
        case let .failed(message):
            problem = message
        }
    }

    /// Sign-out.
    func reset() {
        account += 1
        panel = .chat
        problem = nil
        chats.reset()
    }

    /// One chat was deleted, here or in Settings: the card empties only if it was showing that one.
    private func chatDeleted(_ id: String) async {
        guard await assistant?.currentChat() == id else { return }
        await assistant?.chatsDeleted()
    }
}
