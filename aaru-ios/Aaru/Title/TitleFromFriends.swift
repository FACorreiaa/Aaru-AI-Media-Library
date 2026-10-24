import AaruAPI
import SwiftUI

/// "From friends" on a title page (BOARD-003): up to five posts friends wrote about this title,
/// and "Write about this", which opens Friends on the Board with the composer holding the title.
/// With friends but no posts yet it says so and still offers "Write about this"; hidden only when
/// there are no posts and no friends (DESIGN.md, as on the web). The rows carry no link to the
/// post screen from here: the comment count is a count, and the full thread is on the Board.
struct TitleFromFriends: View {
    let api: Client?
    let summary: TitleSummary

    @Environment(AppRouter.self) private var router: AppRouter?
    /// The app's shared friends, when Friends or Settings has loaded them.
    @Environment(SocialModel.self) private var social: SocialModel?
    @State private var board: BoardModel
    /// Whether you have friends, asked once when the shared model hasn't loaded yet.
    @State private var fetchedHasFriends = false

    private static let limit = 5

    init(api: Client?, summary: TitleSummary) {
        self.api = api
        self.summary = summary
        _board = State(initialValue: BoardModel(api: api))
    }

    private var hasFriends: Bool {
        if let social, social.hasLoaded {
            return !social.friends.isEmpty
        }
        return fetchedHasFriends
    }

    var body: some View {
        Group {
            if !board.posts.isEmpty || hasFriends {
                VStack(alignment: .leading, spacing: AaruSpace.large) {
                    Text("From friends")
                        .eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    if board.posts.isEmpty {
                        Text("None of your friends has written about this yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color(.muted))
                    }
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
            async let posts = titlePosts(api: api, titleId: summary.id)
            if social?.hasLoaded != true {
                fetchedHasFriends = await anyFriends(api: api)
            }
            board.adopt(await posts)
        }
    }
}

/// Whether the viewer has any friends: one friends read, for a title page opened before Friends
/// or Settings loaded the shared `SocialModel`. False when it can't tell.
private func anyFriends(api: Client?) async -> Bool {
    guard let api else { return false }
    do {
        if case let .ok(response) = try await api.listFriends() {
            return try !response.body.json.items.isEmpty
        }
    } catch {
        return false
    }
    return false
}
