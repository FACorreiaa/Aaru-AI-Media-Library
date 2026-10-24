import AaruAPI
import AaruCore
import SwiftUI

/// Whom a comment answers: the top-level comment it hangs from (`id`), the `@who ` the box starts
/// with when answering a reply (`prefill`), and who "Replying to" names.
struct CommentReply: Equatable {
    let id: String
    let prefill: String
    let name: String

    init(_ comment: BoardComment) {
        let target = BoardRules.replyTarget(comment)
        id = target.id
        prefill = target.prefill
        name = comment.author.map { "@\($0.handle)" } ?? "Aaru"
    }
}

/// CommentComposer (BOARD-003): the box pinned under a post's thread. One line that grows; `@`
/// suggests the post's author and your friends, never Aaru (BOARD-004). Replying names who above
/// the box, with ✕ (or Escape) to drop it; answering a reply starts the box with `@who `, so they
/// are tagged though the reply hangs off the top-level comment. ⌘↩ sends.
struct CommentComposer: View {
    let model: PostModel
    /// Who `@` suggests: the post's author and your friends, without you.
    let handles: [String]
    @Binding var reply: CommentReply?
    /// The new comment's id, so the thread can scroll to it.
    let onPosted: (String) -> Void

    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var sending = false

    private var remaining: Int? {
        BoardRules.remaining(text)
    }

    private var tooLong: Bool {
        (remaining ?? 0) < 0
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tooLong && !sending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            if let reply {
                replying(reply)
            }
            MentionSuggestionStrip(suggestions: MentionSuggestions.suggestions(for: text, handles: handles)) {
                text = MentionSuggestions.complete(text, with: $0)
            }
            HStack(alignment: .bottom, spacing: AaruSpace.xsmall) {
                field
                sendButton
            }
            if let remaining {
                Text(remaining, format: .number)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(tooLong ? Color(.danger) : Color(.muted))
                    .accessibilityLabel(tooLong ? "\(-remaining) characters over" : "\(remaining) characters left")
            }
        }
        .padding(.horizontal, AaruSpace.large)
        .padding(.vertical, AaruSpace.small)
        .background(.bar)
        // A new reply target swaps its `@who ` in (or out), keeping anything typed after it.
        .onChange(of: reply) { old, new in
            text = BoardRules.prefillReply(text, from: old?.prefill ?? "", to: new?.prefill ?? "")
            if new != nil {
                focused = true
            }
        }
    }

    /// "Replying to @ana ✕".
    private func replying(_ reply: CommentReply) -> some View {
        HStack(spacing: AaruSpace.xsmall) {
            Text("Replying to \(Text(reply.name).fontWeight(.semibold).foregroundStyle(Color(.ink)))")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
            Button("Stop replying", systemImage: "xmark") {
                self.reply = nil
            }
            .labelStyle(.iconOnly)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(.muted))
            .buttonStyle(.borderless)
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(.rect)
        }
    }

    private var field: some View {
        TextField("Comment on this post", text: $text, axis: .vertical)
            .lineLimit(1 ... 6)
            .textFieldStyle(.plain)
            .padding(.horizontal, AaruSpace.medium)
            .padding(.vertical, AaruSpace.small)
            .card()
            .overlay {
                if tooLong {
                    RoundedRectangle(cornerRadius: AaruRadius.card, style: .continuous)
                        .strokeBorder(Color(.danger))
                }
            }
            .focused($focused)
            .accessibilityLabel(reply.map { "Reply to \($0.name)" } ?? "Comment on this post")
            .onKeyPress(.escape) {
                guard reply != nil else { return .ignored }
                reply = nil
                return .handled
            }
    }

    private var sendButton: some View {
        Button(reply == nil ? "Comment" : "Reply", systemImage: "arrow.up.circle.fill", action: send)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(canSend ? Color(.accent) : Color(.muted))
            .opacity(sending ? 0 : 1)
            .overlay {
                if sending {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(reply == nil ? "Comment (⌘↩)" : "Reply (⌘↩)")
    }

    private func send() {
        guard canSend else { return }
        Task {
            sending = true
            let posted = await model.comment(text, replyTo: reply?.id)
            sending = false
            guard posted else { return }
            text = ""
            reply = nil
            if let id = model.comments.last?.id {
                onPosted(id)
            }
        }
    }
}
