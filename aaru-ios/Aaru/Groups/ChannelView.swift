import AaruAPI
import SwiftUI

/// GRP-003: one channel. Flat rows pinned to the bottom, a "New" line where reading stopped, and
/// the composer in the bottom inset. Polls every five seconds while it is on screen and the app is
/// active, until the realtime gateway replaces that (M3).
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    channelStart
                    messageRows
                    outboxRows
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
        .safeAreaInset(edge: .top, spacing: 0) { ChannelHeader(topic: channel.topic) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ProblemBanner(message: model.problem) { model.problem = nil }
                Composer(
                    text: $draft,
                    channelName: channel.name,
                    editing: editing,
                    members: (detail?.members ?? []).filter { $0.user.userId != groups.myUserID },
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
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { break }
                    await model.pollNewer()
                }
            }
            .confirmationDialog(
                "Delete this message?",
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

    @ViewBuilder
    private var channelStart: some View {
        if model.reachedStart {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(channel.name)").font(.title2.weight(.semibold))
                Text(channel.isDefault ? "The start of the group." : "The start of #\(channel.name).")
                    .foregroundStyle(Color(.muted))
            }
            .padding(16)
        } else if model.hasLoaded {
            Button(model.loadingOlder ? "Loading…" : "Load earlier messages") {
                Task { await model.loadOlder() }
            }
            .buttonStyle(.borderless)
            .disabled(model.loadingOlder)
            .frame(maxWidth: .infinity)
            .padding(12)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(24)
        }
    }

    private var messageRows: some View {
        ForEach(MessageLine.lines(model.messages, firstUnreadID: model.firstUnreadID)) { line in
            if let day = line.day {
                DayDivider(day: day)
            }
            if line.isFirstUnread {
                NewDivider()
            }
            MessageRow(line: line, myUserID: groups.myUserID, myHandle: groups.myHandle)
                .id(line.id)
                .contextMenu { actions(for: line.message) }
                .onAppear {
                    if line.id == model.messages.last?.id {
                        markRead()
                    }
                }
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
            Task { await model.send(text) }
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

/// The topic and the "Not end-to-end" chip, which never hides.
private struct ChannelHeader: View {
    let topic: String?
    @State private var explains = false

    var body: some View {
        HStack(spacing: 12) {
            if let topic {
                Text(topic)
                    .font(.callout)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                explains = true
            } label: {
                Label("Not end-to-end", systemImage: "lock.open")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.muted).opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(.muted))
            .popover(isPresented: $explains) {
                Text("""
                Group messages are stored on Aaru's server in a form it can read, so the group works \
                on all your devices. Only members of this group can see them.
                """)
                .font(.callout)
                .padding()
                .frame(idealWidth: 300)
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.paper))
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
    }
}

/// One growing box. Return sends on Mac (Option-Return adds a line); on iPhone and iPad the send
/// button sends. Typing `@` suggests members.
private struct Composer: View {
    @Binding var text: String
    let channelName: String
    let editing: GroupMessage?
    let members: [GroupMember]
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onCancelEdit: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= ChannelModel.maxLength
    }

    /// The `@` word being typed, without the `@`.
    private var mentionPrefix: String? {
        let word = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard text.last?.isWhitespace != true, word.hasPrefix("@") else { return nil }
        return String(word.dropFirst()).lowercased()
    }

    private var suggestions: [GroupMember] {
        guard let prefix = mentionPrefix else { return [] }
        return Array(members.filter { $0.user.handle.hasPrefix(prefix) }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing != nil {
                HStack {
                    Label("Editing message", systemImage: "pencil").font(.caption)
                    Spacer()
                    Button("Cancel", action: onCancelEdit).font(.caption).buttonStyle(.borderless)
                }
                .foregroundStyle(Color(.muted))
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.user.userId) { member in
                            Button {
                                complete(member.user.handle)
                            } label: {
                                Label("@\(member.user.handle)", systemImage: "at")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                field
                Button(editing == nil ? "Send" : "Save", systemImage: "arrow.up.circle.fill", action: onSend)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(canSend ? Color(.accent) : Color(.muted))
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            if text.count > ChannelModel.maxLength - 500 {
                Text("\(text.count) / \(ChannelModel.maxLength)")
                    .font(.caption)
                    .foregroundStyle(text.count > ChannelModel.maxLength ? .red : Color(.muted))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var field: some View {
        TextField("Message #\(channelName)", text: $text, axis: .vertical)
            .lineLimit(1 ... 6)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.surface), in: RoundedRectangle(cornerRadius: 18))
            .focused(focused)
        #if os(macOS)
            .onSubmit(onSend)
        #endif
    }

    private func complete(_ handle: String) {
        guard let range = text.range(of: "@", options: .backwards) else { return }
        text.replaceSubrange(range.lowerBound..., with: "@\(handle) ")
    }
}

/// The system pasteboard on either platform.
enum Clipboard {
    static func copy(_ string: String) {
        #if os(iOS)
            UIPasteboard.general.string = string
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
