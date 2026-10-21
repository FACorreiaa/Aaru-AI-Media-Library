import AaruAPI
import SwiftUI

/// GRP-003 / GRP-006: one channel. Flat rows pinned to the bottom, a "New" line where reading
/// stopped, and the composer in the bottom inset. The socket keeps it live; only while the socket
/// is down does it poll, every 30 seconds, and only while on screen with the app active.
struct ChannelView: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel
    /// Shows the members: a sheet on iPhone, the inspector on iPad and Mac.
    let onShowMembers: () -> Void

    @State private var model: ChannelModel
    @State private var draft = ""
    @State private var editing: GroupMessage?
    @State private var deleting: GroupMessage?
    @State private var nearBottom = true
    /// Title channels: how the next message is marked for spoilers. Back to automatic after each.
    @State private var spoiler = SpoilerChoice.auto
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(groups: GroupsModel, groupID: String, channel: GroupChannel, onShowMembers: @escaping () -> Void) {
        self.groups = groups
        self.groupID = groupID
        self.channel = channel
        self.onShowMembers = onShowMembers
        _model = State(initialValue: ChannelModel(
            api: groups.api, groupID: groupID, channelID: channel.id, unread: channel.unread, myUserID: groups.myUserID
        ))
    }

    private var detail: GroupDetail? {
        groups.details[groupID]
    }

    private var myself: SocialUser? {
        detail?.members.first { $0.user.userId == groups.myUserID }?.user
    }

    private var canModerate: Bool {
        detail?.group.role.manages ?? false
    }

    private var socketOpen: Bool {
        groups.realtime?.state == .open
    }

    static let fallbackPollInterval: Duration = .seconds(30)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ChannelStart(channel: channel, model: model)
                    messageRows
                    outboxRows
                    if !model.thinking.isEmpty {
                        AgentThinkingRow()
                    }
                    Color.clear.frame(height: 8).id(Self.bottomID)
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 160
            } action: { _, isNear in
                nearBottom = isNear
            }
            .overlay(alignment: .bottomTrailing) {
                if !nearBottom {
                    Button("Jump to present", systemImage: "arrow.down") { scrollToBottom(proxy) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(12)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .onChange(of: model.messages.last?.id) {
                if nearBottom {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: model.outbox.count) { scrollToBottom(proxy) }
        }
        .background(Color(.paper))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ChannelHeader(
                    topic: channel.topic,
                    disconnectedSince: socketOpen ? nil : groups.realtime?.disconnectedSince,
                    agent: detail?.agent ?? false
                )
                ChannelKindPanel(groups: groups, groupID: groupID, channel: channel)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ProblemBanner(message: model.problem) { model.problem = nil }
                if let line = model.typingLine {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .transition(reduceMotion ? .identity : .opacity)
                }
                Composer(
                    text: $draft,
                    channelName: channel.name,
                    editing: editing,
                    members: (detail?.members ?? []).filter { $0.user.userId != groups.myUserID },
                    agent: detail?.agent ?? false,
                    spoiler: channel.kind == .title ? $spoiler : nil,
                    focused: $composerFocused,
                    onSend: submit,
                    onCancelEdit: {
                        editing = nil
                        draft = ""
                    }
                )
            }
        }
        .navigationTitle("#\(channel.name)")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Members", systemImage: "person.2", action: onShowMembers)
                }
            }
            .task { await model.loadLatest() }
            .task {
                guard let realtime = groups.realtime else { return }
                for await event in realtime.events() {
                    await model.apply(event)
                }
            }
            // The fallback while the socket is down: on screen, app active, every 30 s.
            .task(id: scenePhase == .active && !socketOpen) {
                guard scenePhase == .active, !socketOpen else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.fallbackPollInterval)
                    guard !Task.isCancelled else { break }
                    await model.pollNewer()
                }
            }
            .onChange(of: draft) { _, text in
                if editing == nil, !text.isEmpty {
                    groups.realtime?.sendTyping(group: groupID, channel: channel.id)
                }
            }
            .confirmationDialog(
                "Delete this group message?",
                isPresented: Binding(get: { deleting != nil }, set: {
                    if !$0 {
                        deleting = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: deleting
            ) { message in
                Button("Delete", role: .destructive) { Task { await model.delete(message) } }
            } message: { _ in
                Text("Everyone in the group stops seeing it.")
            }
    }

    private static let bottomID = "bottom"

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= ChannelModel.maxLength else { return }
        if let message = editing {
            Task {
                if await model.edit(message, to: text) {
                    editing = nil
                    draft = ""
                }
            }
        } else {
            draft = ""
            let marked = spoiler
            spoiler = .auto
            Task { await model.send(text, spoiler: marked) }
        }
    }

    private func markRead() {
        Task {
            if await model.markRead() {
                await groups.refreshCounts(groupID)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }
}

extension ChannelView {
    private var messageRows: some View {
        ForEach(MessageLine.lines(model.messages, firstUnreadID: model.firstUnreadID)) { line in
            if let day = line.day {
                DayDivider(day: day)
            }
            if line.isFirstUnread {
                NewDivider()
            }
            row(line)
                .id(line.id)
                .contextMenu { actions(for: line.message) }
                .onAppear {
                    if line.id == model.messages.last?.id {
                        markRead()
                    }
                }
        }
    }

    @ViewBuilder
    private func row(_ line: MessageLine) -> some View {
        if line.message.fromAgent {
            AgentMessageRow(
                message: line.message, answering: model.messages.first { $0.id == line.message.replyTo },
                myHandle: groups.myHandle,
                onAdd: { await groups.addToMyLibrary($0) }
            )
        } else {
            MessageRow(line: line, myUserID: groups.myUserID, myHandle: groups.myHandle)
        }
    }

    private var outboxRows: some View {
        ForEach(Array(model.outbox.enumerated()), id: \.element.id) { index, outgoing in
            OutgoingRow(
                outgoing: outgoing,
                startsRun: index == 0 && model.messages.last?.author?.userId != groups.myUserID,
                sender: myself,
                onRetry: { Task { await model.retry(outgoing) } },
                onDiscard: { model.discard(outgoing) }
            )
        }
    }

    @ViewBuilder
    private func actions(for message: GroupMessage) -> some View {
        if !message.deleted {
            Button("Copy text", systemImage: "doc.on.doc") { Clipboard.copy(message.body) }
            if message.author?.userId == groups.myUserID {
                Button("Edit", systemImage: "pencil") {
                    editing = message
                    draft = message.body
                    composerFocused = true
                }
            }
            if message.author?.userId == groups.myUserID || canModerate {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = message }
            }
        }
    }
}
