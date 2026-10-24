import AaruAPI
import AaruCore
import SwiftUI

/// One post on the Board (BOARD-003): who and when, the title it is about with its stars, the
/// words, then Upvote and the comment count. Not one big link, so the words stay selectable. The
/// poster is not a link either: a friend's title is usually not in your library, so their posts
/// carry "Add to my library" instead. A post that may spoil what you haven't watched hides its
/// words and stars behind the veil until tapped; the author never sees a veil, and only the
/// author sees how it is marked. On the Board the comment count opens the post screen; on the
/// post screen (`standalone`) it is only a count, and the words can give way to an editor.
struct PostRow<Editor: View>: View {
    let post: BoardPost
    /// Your handle: mentions of you read in the accent.
    let myHandle: String?
    let board: BoardModel
    /// The post screen's row: the comment count is not a link to where you already are.
    var standalone = false
    /// On the title's own page: no poster, name or "Add to my library"; the stars and the mark stay.
    var hidesTitle = false
    /// The post screen upvotes through its own model, so its upvoters refresh. Nil: the Board's.
    var onUpvote: (() async -> Void)?
    /// Shown in place of the words while you edit them (the post screen).
    var editor: Editor?

    @State private var revealed = false
    @State private var adding = false
    @State private var added = false

    private var veiled: Bool {
        post.veiled && !post.mine && !revealed
    }

    var body: some View {
        HStack(alignment: .top, spacing: AaruSpace.medium) {
            Monogram(text: post.author.monogram)
            VStack(alignment: .leading, spacing: AaruSpace.small) {
                header
                if let title = post.title {
                    titleBlock(title)
                }
                if let editor {
                    editor
                } else if veiled {
                    SpoilerVeil { revealed = true }
                } else {
                    Text(MentionText.attributed(post.body, myHandle: myHandle))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
        }
    }

    /// "Ana · @ana · 2 hours ago · Edited", the name in Ink and the rest muted.
    private var header: some View {
        let name = Text(post.mine ? "You" : post.author.inviteName)
            .fontWeight(.semibold)
            .foregroundStyle(Color(.ink))
        let handle = post.author.displayName == nil ? Text(verbatim: "") : Text(verbatim: "@\(post.author.handle) · ")
        let date = Text(post.createdAt, format: .relative(presentation: .named))
        let edited = post.editedAt == nil ? Text(verbatim: "") : Text(" · Edited")
        return Text("\(name) \(handle)\(date)\(edited)")
            .font(.subheadline)
            .foregroundStyle(Color(.muted))
    }

    private func titleBlock(_ title: TitleSummary) -> some View {
        let kind = MediaKind(type: title._type, isAnime: title.isAnime)
        return HStack(spacing: AaruSpace.medium) {
            if !hidesTitle {
                PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                    .frame(width: 48)
            }
            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                if !hidesTitle {
                    Text(title.year.map { "\(title.title) · \(String($0))" } ?? title.title)
                        .font(.aaruDisplay(.body))
                        .lineLimit(2)
                }
                if let rating = post.rating, !veiled {
                    Text(BoardRules.stars(rating))
                        .foregroundStyle(Color(.gold))
                        .accessibilityLabel(BoardRules.ratingWords(rating))
                }
                if post.mine, let mark = post.spoiler?.label {
                    Label(mark, systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .accessibilityHint("Friends who haven't watched this far see it veiled. Only you see the mark.")
                }
                if !post.mine, !hidesTitle {
                    addToLibrary(title, kind: kind)
                }
            }
        }
    }

    @ViewBuilder
    private func addToLibrary(_ title: TitleSummary, kind: MediaKind) -> some View {
        if added {
            Label("Added to \(LibraryStatus.wishlist.label(for: kind))", systemImage: "checkmark")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        } else {
            Button {
                Task {
                    adding = true
                    added = await board.addToMyLibrary(title)
                    adding = false
                }
            } label: {
                HStack(spacing: AaruSpace.small) {
                    Label("Add to my library", systemImage: "plus")
                    if adding {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.footnote.weight(.medium))
                .frame(minHeight: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(adding)
        }
    }

    private var footer: some View {
        HStack(spacing: AaruSpace.large) {
            UpvoteButton(upvotes: post.upvotes, upvoted: post.upvotedByMe) {
                if let onUpvote {
                    await onUpvote()
                } else {
                    await board.toggleUpvote(post.id)
                }
            }
            if standalone {
                commentCount
                    .foregroundStyle(Color(.muted))
            } else {
                NavigationLink(value: PostRoute(postId: post.id, initial: post)) {
                    commentCount
                        .hoverInk()
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the post")
            }
        }
    }

    private var commentCount: some View {
        Label("\(post.commentCount)", systemImage: "bubble.right")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(post.commentCount == 1 ? "1 comment" : "\(post.commentCount) comments")
    }
}

/// The Board's row: no editor, and the comment count opens the post screen.
extension PostRow where Editor == EmptyView {
    init(post: BoardPost, myHandle: String?, board: BoardModel, standalone: Bool = false, hidesTitle: Bool = false) {
        self.standalone = standalone
        self.hidesTitle = hidesTitle
        self.post = post
        self.myHandle = myHandle
        self.board = board
    }
}
