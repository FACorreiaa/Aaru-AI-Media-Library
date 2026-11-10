import AaruAPI
import SwiftUI

/// One chat in a history list: the start of its first question and when it was last used.
struct ChatHistoryRow: View {
    let chat: Components.Schemas.ChatSummary
    let deleting: Bool

    var body: some View {
        HStack(spacing: AaruSpace.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title ?? "A chat with Aaru")
                    .foregroundStyle(Color(.ink))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(chat.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: AaruSpace.small)
            if deleting {
                ProgressView()
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The history inside the owl's card (ASK-011): tap a chat to read it again and carry on, delete
/// one from its menu or its button.
struct AssistantHistoryPanel: View {
    let model: ChatsModel
    /// A chat is being fetched: taps wait.
    let opening: Bool
    let problem: String?
    let onOpen: (Components.Schemas.ChatSummary) -> Void

    @State private var confirming: Components.Schemas.ChatSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AaruSpace.small) {
                Text("Your chats")
                    .font(.aaruDisplay(.headline, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .accessibilityAddTraits(.isHeader)
                if let line = problem ?? model.problem ?? model.loadFailure {
                    Text(line).font(.footnote).foregroundStyle(Color(.danger))
                }
                content
            }
            .padding(.horizontal, AaruSpace.large)
            .padding(.top, AaruSpace.xsmall)
            .padding(.bottom, AaruSpace.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { await model.load() }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: $confirming.isPresent,
            titleVisibility: .visible,
            presenting: confirming
        ) { chat in
            Button("Delete chat", role: .destructive) { Task { await model.delete(chat) } }
        } message: { _ in
            Text("This removes what you and Aaru said in it. Changes Aaru made to your library stay.")
        }
    }

    @ViewBuilder private var content: some View {
        if !model.hasLoaded, model.loadFailure == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, AaruSpace.large)
        } else if model.chats.isEmpty, model.loadFailure == nil {
            Text("No chats yet.")
                .font(.callout)
                .foregroundStyle(Color(.muted))
        } else {
            ForEach(model.chats, id: \.id) { chat in
                HStack(spacing: 0) {
                    Button { onOpen(chat) } label: {
                        ChatHistoryRow(chat: chat, deleting: model.deleting == chat.id)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(opening)
                    Button("Delete", systemImage: "trash") { confirming = chat }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color(.muted))
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Delete the chat: \(chat.title ?? "untitled")")
                }
                Rectangle().fill(Color(.line)).frame(height: 1)
            }
            if model.hasMore {
                Button(model.isLoading ? "Loading…" : "Show more") { Task { await model.loadMore() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
            }
            if opening {
                Text("Opening…").font(.footnote).foregroundStyle(Color(.muted))
            }
        }
    }
}

/// Settings → Your data → Chats with Aaru (ASK-011): every chat, latest first. A row opens the chat
/// to read; continuing it is the owl's History. Swipe or the menu deletes one.
struct ChatsPage: View {
    let model: ChatsModel
    var push: (SettingsRoute) -> Void

    @State private var confirming: Components.Schemas.ChatSummary?

    var body: some View {
        @Bindable var model = model
        content
            .background(Color(.paper))
            .navigationTitle("Chats with Aaru")
            .safeAreaInset(edge: .bottom) {
                ProblemBanner(message: model.problem) { model.problem = nil }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .confirmationDialog(
                "Delete this chat?",
                isPresented: $confirming.isPresent,
                titleVisibility: .visible,
                presenting: confirming
            ) { chat in
                Button("Delete chat", role: .destructive) { Task { await model.delete(chat) } }
            } message: { _ in
                Text("This removes what you and Aaru said in it. Changes Aaru made to your library stay.")
            }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.loadFailure, !model.hasLoaded {
            LoadFailedView(title: "Your chats didn't load", message: failure) { await model.load() }
        } else if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.chats.isEmpty {
            ContentUnavailableView(
                "No chats yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("What you ask Aaru from the owl shows up here.")
            )
        } else {
            List {
                ForEach(model.chats, id: \.id) { chat in
                    Button { push(.chat(chat.id)) } label: {
                        ChatHistoryRow(chat: chat, deleting: model.deleting == chat.id)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(.surface))
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirming = chat }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirming = chat }
                    }
                }
                if model.hasMore {
                    Button(model.isLoading ? "Loading…" : "Show more") { Task { await model.loadMore() } }
                        .disabled(model.isLoading)
                        .listRowBackground(Color(.surface))
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// One stored chat, read-only, in Settings (ASK-011): each question and what Aaru answered, with
/// the roadmap it planned. Carrying on with it is done from the owl's History.
struct StoredChatView: View {
    let id: String
    let api: Client?

    @State private var chat: StoredChat?
    @State private var failure: String?

    var body: some View {
        content
            .background(Color(.paper))
            .navigationTitle(chat?.title ?? "Chat")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if let chat {
            ScrollView {
                VStack(alignment: .leading, spacing: AaruSpace.xlarge) {
                    ForEach(Array(chat.exchanges.enumerated()), id: \.offset) { _, exchange in
                        exchangeView(exchange)
                    }
                    Text("To carry on with this chat, open the owl and choose it under Chats.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                }
                .padding(AaruSpace.large)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        } else if let failure {
            LoadFailedView(title: "This chat didn't load", message: failure) { await load() }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exchangeView(_ exchange: ChatExchange) -> some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            if !exchange.question.isEmpty {
                Text(exchange.question)
                    .foregroundStyle(Color(.ink))
                    .textSelection(.enabled)
                    .padding(.horizontal, AaruSpace.medium)
                    .padding(.vertical, AaruSpace.small)
                    .background(
                        Color(.accent).opacity(AaruAlpha.wash),
                        in: .rect(cornerRadius: AaruRadius.panel, style: .continuous)
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !exchange.reply.text.isEmpty {
                Text(exchange.reply.text)
                    .foregroundStyle(Color(.ink))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !exchange.reply.titles.isEmpty {
                Text(exchange.reply.titles.map(\.title).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            if let roadmap = exchange.reply.roadmap {
                RoadmapCardView(roadmap: roadmap, importID: exchange.reply.importID) {
                    PushInbox.shared.importID = $0
                }
            }
            if let problem = exchange.reply.problem {
                Text(problem).font(.footnote).foregroundStyle(Color(.muted))
            }
        }
    }

    private func load() async {
        guard let api else {
            failure = "Sign in to read your chats."
            return
        }
        switch await api.storedChat(id) {
        case let .loaded(stored):
            chat = stored
            failure = nil
        case let .failed(message):
            failure = message
        }
    }
}

#Preview {
    NavigationStack {
        ChatsPage(
            model: ChatsModel(preview: [
                .init(id: "1", title: "What do I watch before Secret Wars?", createdAt: .now, updatedAt: .now),
                .init(
                    id: "2", title: "How many films did I finish this year?", createdAt: .now,
                    updatedAt: .now.addingTimeInterval(-86400)
                ),
            ]),
            push: { _ in }
        )
    }
}
