import AaruAPI
import AaruCore
import SwiftUI

/// The post screen (BOARD-003): one post on its own, who upvoted it, its thread (one level of
/// replies) and the comment box pinned to the bottom. Your own post can be edited (its words
/// only) or deleted; a friend's can be reported. Edits and deletes reach the Board's row at once.
/// A post that is not there for you (deleted, or its author no longer your friend) says so in
/// place. One readable column, as the Board: full width on iPhone, centred on iPad and Mac.
struct PostScreen: View {
    let board: BoardModel
    /// Your friends' handles: `@` suggests them, and the post's author, never you.
    let friendHandles: [String]
    /// Your handle: mentions of you read in the accent, and your upvote reads "You".
    let myHandle: String?

    /// The readable column on iPad and Mac, the Board's.
    private static let columnWidth: CGFloat = 640

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var monogramScale: CGFloat = 1
    @State private var model: PostModel
    @State private var reply: CommentReply?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var reporting = false
    @State private var showsUpvoters = false
    @State private var columnInset = AaruSpace.large

    init(postId: String, initial: BoardPost?, board: BoardModel, friendHandles: [String], myHandle: String?) {
        self.board = board
        self.friendHandles = friendHandles
        self.myHandle = myHandle
        _model = State(initialValue: PostModel(api: board.api, postId: postId, initial: initial))
    }

    /// The post's author first, then friends; you are never suggested.
    private var mentionHandles: [String] {
        var seen: Set<String> = myHandle.map { [$0] } ?? []
        let author = model.post.map { [$0.author.handle] } ?? []
        return (author + friendHandles).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Group {
            if model.unavailable {
                OwlUnavailableView(
                    title: "This post isn't available",
                    message: "It was deleted, or you and its author are no longer friends."
                )
            } else if let post = model.post {
                content(post)
            } else if let problem = model.problem {
                LoadFailedView(title: "This post didn't load", message: problem) { await model.load() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.paper))
        .navigationTitle("Post")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if let post = model.post, !model.unavailable {
                    ToolbarItem(placement: .primaryAction) { actions(post) }
                }
            }
            .task {
                await model.load()
                // A first page the server emptied (hidden rows) with more behind it.
                if model.comments.isEmpty, BoardRules.shouldLoadMore(next: model.next) {
                    await model.showMoreComments()
                }
            }
            // The Board's row follows: upvotes, the comment count, an edit.
            .onChange(of: model.post) { _, post in
                if let post {
                    board.replace(post)
                }
            }
            .onChange(of: model.unavailable) { _, gone in
                if gone {
                    board.remove(model.postId)
                }
            }
            // The comment being answered went away.
            .onChange(of: model.comments.map(\.id)) { _, ids in
                if let reply, !ids.contains(reply.id) {
                    self.reply = nil
                }
            }
            .confirmationDialog("Delete this post?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete post", role: .destructive, action: deletePost)
            } message: {
                Text("Its comments and upvotes go with it.")
            }
            .sheet(isPresented: $reporting) { ReportPostSheet(model: model) }
            .sheet(isPresented: $showsUpvoters) { UpvotersSheet(people: model.upvoters, myHandle: myHandle) }
    }

    private func content(_ post: BoardPost) -> some View {
        ScrollViewReader { proxy in
            List {
                PostRow(
                    post: post,
                    myHandle: myHandle,
                    board: board,
                    standalone: true,
                    onUpvote: { await model.toggleUpvote() },
                    editor: editing ? PostEditor(post: post, model: model) { editing = false } : nil
                )
                .padding(.top, AaruSpace.large)
                .postListRow(inset: columnInset)
                if let line = BoardRules.upvotersLine(upvoterNames(post)) {
                    upvoters(line, count: post.upvotes)
                        .padding(.leading, 36 * min(monogramScale, 1.6) + AaruSpace.medium)
                        .postListRow(inset: columnInset)
                }
                CommentThread(
                    model: model,
                    postMine: post.mine,
                    myHandle: myHandle,
                    inset: columnInset
                ) { reply = CommentReply($0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
            #endif
                .refreshable { await model.load() }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    columnInset = max(AaruSpace.large, (width - Self.columnWidth) / 2)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        ProblemBanner(message: model.problem) { model.problem = nil }
                        CommentComposer(model: model, handles: mentionHandles, reply: $reply) { id in
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
        }
    }

    /// Who upvoted, "You" first when you did.
    private func upvoterNames(_ post: BoardPost) -> [String] {
        let others = model.upvoters.filter { $0.handle != myHandle }.map(\.inviteName)
        return post.upvotedByMe ? ["You"] + others : others
    }

    /// "▲ 12 · Ana, Ben and 10 others": a tap lists everyone.
    private func upvoters(_ line: String, count: Int) -> some View {
        Button {
            showsUpvoters = true
        } label: {
            Text("\(Text(verbatim: "▲").foregroundStyle(Color(.accent))) \(count) · \(line)")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upvoted by \(line)")
        .accessibilityHint("Shows everyone who upvoted")
    }

    private func actions(_ post: BoardPost) -> some View {
        Menu("Post actions", systemImage: "ellipsis.circle") {
            if post.mine {
                Button("Edit post", systemImage: "pencil") { editing = true }
                Button("Delete post", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } else {
                Button("Report post", systemImage: "flag") { reporting = true }
            }
        }
    }

    private func deletePost() {
        Task {
            if await model.delete() {
                board.remove(model.postId)
                dismiss()
            }
        }
    }
}

extension View {
    /// A row of the post screen's list: no separator, no row background, inside the readable
    /// column. `indent` hangs a reply under its parent.
    func postListRow(inset: CGFloat, indent: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: inset + indent, bottom: 0, trailing: inset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// The post's words in a box, in place of them (body only). Escape cancels; ⌘↩ saves.
private struct PostEditor: View {
    let post: BoardPost
    let model: PostModel
    let onDone: () -> Void

    @FocusState private var focused: Bool
    @State private var text: String
    @State private var saving = false

    init(post: BoardPost, model: PostModel, onDone: @escaping () -> Void) {
        self.post = post
        self.model = model
        self.onDone = onDone
        _text = State(initialValue: post.body)
    }

    private var remaining: Int? {
        BoardRules.remaining(text)
    }

    private var tooLong: Bool {
        (remaining ?? 0) < 0
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != post.body && !tooLong && !saving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            TextField("Edit your post", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3 ... 12)
                .focused($focused)
                .onKeyPress(.escape) {
                    onDone()
                    return .handled
                }
            HStack(spacing: AaruSpace.medium) {
                if let remaining {
                    Text(remaining, format: .number)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(tooLong ? Color(.danger) : Color(.muted))
                        .accessibilityLabel(tooLong ? "\(-remaining) characters over" : "\(remaining) characters left")
                }
                Spacer(minLength: 0)
                Button("Cancel", action: onDone)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color(.muted))
                Button(action: save) {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(.paper))
                        .opacity(saving ? 0 : 1)
                        .overlay {
                            if saving {
                                ProgressView().controlSize(.small).tint(Color(.paper))
                            }
                        }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.ink))
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(AaruSpace.medium)
        .background(Color(.surface), in: .rect(cornerRadius: AaruRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AaruRadius.panel, style: .continuous)
                .strokeBorder(tooLong ? Color(.danger) : Color(.accent).opacity(AaruAlpha.half))
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard canSave else { return }
        Task {
            saving = true
            let saved = await model.edit(body: text)
            saving = false
            if saved {
                onDone()
            }
        }
    }
}

/// Everyone who upvoted, "You" among them by name.
private struct UpvotersSheet: View {
    let people: [SocialUser]
    let myHandle: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(people, id: \.userId) { person in
                HStack(spacing: AaruSpace.medium) {
                    Monogram(text: person.monogram, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(person.handle == myHandle ? "You" : person.inviteName)
                            .fontWeight(.medium)
                        if person.handle != myHandle, person.displayName != nil {
                            Text(verbatim: "@\(person.handle)")
                                .font(.subheadline)
                                .foregroundStyle(Color(.muted))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color(.surface))
            }
            .paperPage()
            .navigationTitle(people.count == 1 ? "1 upvote" : "\(people.count) upvotes")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
