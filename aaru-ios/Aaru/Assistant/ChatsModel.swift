import AaruAPI
import Foundation
import Observation

/// The user's chats with Aaru, latest first (ASK-011): one page at a time, with delete. The owl's
/// card and Settings → Your data each hold one; a delete in either reaches the other.
@MainActor
@Observable
final class ChatsModel {
    private(set) var chats: [Components.Schemas.ChatSummary] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// The first load failed: the list shows the error, not "No chats yet".
    private(set) var loadFailure: String?
    /// The chat being deleted, so its row shows progress.
    private(set) var deleting: String?
    var problem: String?

    @ObservationIgnored private let api: Client?
    /// The next page's cursor; nil on the last page.
    @ObservationIgnored private var next: String?

    var hasMore: Bool {
        next != nil
    }

    init(api: Client?) {
        self.api = api
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .aaruChatDeleted) {
                guard let self else { return }
                if let id = note.object as? String {
                    chats.removeAll { $0.id == id }
                }
            }
        }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .aaruChatsDeleted) {
                guard let self else { return }
                chats = []
                next = nil
            }
        }
    }

    /// For previews: these chats, nothing to fetch.
    convenience init(preview chats: [Components.Schemas.ChatSummary]) {
        self.init(api: nil)
        self.chats = chats
        hasLoaded = true
    }

    /// The first page, replacing what is shown.
    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        switch await api.chatHistory() {
        case let .loaded(page):
            chats = page.chats
            next = page.next
            hasLoaded = true
            loadFailure = nil
        case let .failed(message):
            if hasLoaded {
                problem = message
            } else {
                loadFailure = message
            }
        }
    }

    /// The page after the last one shown.
    func loadMore() async {
        guard let api, let cursor = next, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        switch await api.chatHistory(after: cursor) {
        case let .loaded(page):
            let known = Set(chats.map(\.id))
            chats += page.chats.filter { !known.contains($0.id) }
            next = page.next
        case let .failed(message):
            problem = message
        }
    }

    func delete(_ chat: Components.Schemas.ChatSummary) async {
        guard let api, deleting == nil else { return }
        deleting = chat.id
        problem = nil
        defer { deleting = nil }
        if let failure = await api.removeChat(chat.id) {
            problem = failure
            return
        }
        chats.removeAll { $0.id == chat.id }
        NotificationCenter.default.post(name: .aaruChatDeleted, object: chat.id)
    }

    func reset() {
        chats = []
        next = nil
        hasLoaded = false
        loadFailure = nil
        problem = nil
    }
}
