import AaruAPI
import AaruCore
import SwiftUI

/// CommentThread (BOARD-003): a post's comments as rows of the post screen's list, oldest first,
/// one level of replies hung under the comment they answer on a hairline. A deleted comment that
/// still has replies stays as a muted "Comment deleted" with no author. Reply answers the
/// top-level comment; Delete is yours, or anyone's on your post. Both sit in the context menu and
/// the swipe, and Reply is a visible button too. More comes by "Show more comments", never by
/// scrolling.
struct CommentThread: View {
    let model: PostModel
    /// The post is yours: you may delete any comment on it.
    let postMine: Bool
    let myHandle: String?
    /// The readable column's side margin, from the post screen.
    let inset: CGFloat
    let onReply: (BoardComment) -> Void

    @State private var pendingDelete: BoardComment?
    @State private var confirmingDelete = false
    @State private var loadingMore = false

    private var threads: [BoardThread<BoardComment>] {
        BoardRules.threads(model.comments)
    }

    var body: some View {
        let threads = threads
        heading
            .padding(.top, AaruSpace.xlarge)
            .padding(.bottom, AaruSpace.xsmall)
            .postListRow(inset: inset)
            .confirmationDialog(
                "Delete this comment?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { comment in
                Button("Delete comment", role: .destructive) {
                    Task { await model.deleteComment(comment.id) }
                }
            } message: { comment in
                if threads.first(where: { $0.comment.id == comment.id })?.replies.isEmpty == false {
                    Text("Replies to it stay, under “Comment deleted”.")
                }
            }
        if threads.isEmpty, model.next == nil {
            Text("No comments yet")
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
                .padding(.vertical, AaruSpace.small)
                .postListRow(inset: inset)
        }
        ForEach(threads, id: \.comment.id) { thread in
            VStack(spacing: 0) {
                if thread.comment.id != threads.first?.comment.id {
                    Divider()
                }
                row(thread.comment)
                    .padding(.vertical, AaruSpace.large)
            }
            .postListRow(inset: inset)
            .modifier(actions(thread.comment))
            ForEach(thread.replies, id: \.id) { reply in
                // The spine: a hairline from under the parent's monogram, replies hung off it.
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(.line))
                        .frame(width: 1)
                        .accessibilityHidden(true)
                    row(reply)
                        .padding(.leading, AaruSpace.xlarge)
                        .padding(.bottom, AaruSpace.large)
                }
                .postListRow(inset: inset, indent: CommentRow.side / 2)
                .modifier(actions(reply))
            }
        }
        if BoardRules.shouldLoadMore(next: model.next) {
            showMore
                .padding(.vertical, AaruSpace.small)
                .postListRow(inset: inset)
        }
    }

    /// "Comments 12".
    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: AaruSpace.small) {
            Text("Comments")
                .font(.aaruDisplay(.title3))
            if let count = model.post?.commentCount, count > 0 {
                Text(count, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color(.muted))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ comment: BoardComment) -> some View {
        CommentRow(comment: comment, myHandle: myHandle) { onReply(comment) }
    }

    private func actions(_ comment: BoardComment) -> CommentActions {
        CommentActions(comment: comment, canDelete: canDelete(comment), onReply: onReply, onDelete: askToDelete)
    }

    private func askToDelete(_ comment: BoardComment) {
        pendingDelete = comment
        confirmingDelete = true
    }

    private func canDelete(_ comment: BoardComment) -> Bool {
        !comment.deleted && (comment.mine == true || postMine)
    }

    private var showMore: some View {
        Button {
            Task {
                loadingMore = true
                await model.showMoreComments()
                loadingMore = false
            }
        } label: {
            ZStack {
                Text("Show more comments").opacity(loadingMore ? 0 : 1)
                if loadingMore {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(loadingMore)
    }
}

/// One comment: monogram, name, when, and the words with mentions styled, then Reply. A deleted
/// one is a dashed ring and "Comment deleted", with no author and nothing to do.
private struct CommentRow: View {
    static let side: CGFloat = 32

    let comment: BoardComment
    let myHandle: String?
    let onReply: () -> Void

    private var name: String {
        if comment.mine == true {
            return "You"
        }
        return comment.author?.inviteName ?? "Aaru"
    }

    var body: some View {
        if comment.deleted {
            HStack(spacing: AaruSpace.medium) {
                Circle()
                    .strokeBorder(Color(.line), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: Self.side, height: Self.side)
                    .accessibilityHidden(true)
                Text("Comment deleted")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Color(.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: AaruSpace.medium) {
                Monogram(text: comment.author?.monogram ?? "A", size: Self.side)
                VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                    header
                    Text(MentionText.attributed(comment.body, myHandle: myHandle))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onReply) {
                        Text("Reply")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(.muted))
                            .frame(minHeight: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reply to \(comment.mine == true ? "you" : name)")
                }
            }
        }
    }

    /// "Ana · @ana · 2 hours ago", the name in Ink and the rest muted.
    private var header: some View {
        let author = Text(name)
            .fontWeight(.semibold)
            .foregroundStyle(Color(.ink))
        let handle = comment.mine != true && comment.author?.displayName != nil
            ? Text(verbatim: "@\(comment.author?.handle ?? "") · ")
            : Text(verbatim: "")
        let date = Text(comment.createdAt, format: .relative(presentation: .named))
        return Text("\(author) \(handle)\(date)")
            .font(.subheadline)
            .foregroundStyle(Color(.muted))
    }
}

/// Reply, and Delete where you may, in the context menu and the trailing swipe. A deleted comment
/// offers nothing.
private struct CommentActions: ViewModifier {
    let comment: BoardComment
    let canDelete: Bool
    let onReply: (BoardComment) -> Void
    let onDelete: (BoardComment) -> Void

    func body(content: Content) -> some View {
        if comment.deleted {
            content
        } else {
            content
                .contextMenu {
                    Button("Reply", systemImage: "arrowshape.turn.up.left") { onReply(comment) }
                    if canDelete {
                        Button("Delete comment", systemImage: "trash", role: .destructive) { onDelete(comment) }
                    }
                }
                // Delete asks first, so the swipe takes no destructive role (that would animate the
                // row away before the answer).
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canDelete {
                        Button("Delete", systemImage: "trash") { onDelete(comment) }
                            .tint(Color(.danger))
                    }
                    Button("Reply", systemImage: "arrowshape.turn.up.left") { onReply(comment) }
                        .tint(Color(.accent))
                }
        }
    }
}
