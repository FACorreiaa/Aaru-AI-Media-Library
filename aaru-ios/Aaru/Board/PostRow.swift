import AaruAPI
import AaruCore
import SwiftUI

/// One post on the Board (BOARD-003): who and when, the title it is about with its stars, the
/// words, then Upvote and the comment count. Not one big link, so the words stay selectable. The
/// poster is not a link either: a friend's title is usually not in your library, so their posts
/// carry "Add to my library" instead. A post that may spoil what you haven't watched hides its
/// words and stars behind the veil until tapped; the author never sees a veil, and only the
/// author sees how it is marked.
struct PostRow: View {
    let post: BoardPost
    /// Your handle: mentions of you read in the accent.
    let myHandle: String?
    let board: BoardModel

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
                if veiled {
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
            PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                Text(title.year.map { "\(title.title) · \(String($0))" } ?? title.title)
                    .font(.aaruDisplay(.body))
                    .lineLimit(2)
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
                if !post.mine {
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
                await board.toggleUpvote(post.id)
            }
            // A count, not a link, until the post screen exists to open.
            Label("\(post.commentCount)", systemImage: "bubble.right")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(.muted))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(post.commentCount == 1 ? "1 comment" : "\(post.commentCount) comments")
        }
    }
}
