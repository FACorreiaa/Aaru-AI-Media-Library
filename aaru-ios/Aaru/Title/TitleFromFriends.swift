import AaruAPI
import SwiftUI

/// "From friends" on a title page (BOARD-003): up to five posts friends wrote about this title,
/// and "Write about this", which opens Friends on the Board with the composer holding the title.
/// Hidden while there is nothing to show. The rows carry no link to the post screen from here:
/// the comment count is a count, and the full thread is on the Board.
struct TitleFromFriends: View {
    let api: Client?
    let summary: TitleSummary

    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var board: BoardModel

    private static let limit = 5

    init(api: Client?, summary: TitleSummary) {
        self.api = api
        self.summary = summary
        _board = State(initialValue: BoardModel(api: api))
    }

    var body: some View {
        Group {
            if !board.posts.isEmpty {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    Text("From friends")
                        .eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    ForEach(board.posts.prefix(Self.limit), id: \.id) { post in
                        PostRow(post: post, myHandle: nil, board: board, standalone: true, hidesTitle: true)
                        if post.id != board.posts.prefix(Self.limit).last?.id {
                            Divider()
                        }
                    }
                    if let router {
                        Button("Write about this", systemImage: "square.and.pencil") {
                            router.pendingBoardTitle = BoardTitlePick(summary, inLibrary: true)
                            router.select(.friends)
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                    }
                }
                .panel()
            }
        }
        .task(id: summary.id) {
            board.adopt(await titlePosts(api: api, titleId: summary.id))
        }
    }
}
