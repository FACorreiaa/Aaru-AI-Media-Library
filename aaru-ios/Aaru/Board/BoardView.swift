import AaruAPI
import AaruCore
import SwiftUI

/// The Board (BOARD-003): what you and your friends post, newest first or the week's most
/// upvoted. The composer stays on top whatever the Board holds, empty included. One column: full
/// width on iPhone, capped at a readable width and centred on iPad and Mac.
struct BoardView: View {
    let board: BoardModel
    /// Your handle, and how many friends you have (which empty Board this is).
    let social: SocialModel
    /// Switches Friends to Lately, where Invite lives.
    let onShowLately: () -> Void

    /// The readable column on iPad and Mac.
    private static let columnWidth: CGFloat = 640

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var switchingSort = false
    @State private var loadingOlder = false

    private var isWide: Bool {
        #if os(iOS)
            sizeClass == .regular
        #else
            true
        #endif
    }

    var body: some View {
        Group {
            if let problem = board.loadProblem, !board.hasLoaded {
                LoadFailedView(title: "The Board didn't load", message: problem) { await board.load() }
            } else {
                ScrollView {
                    column
                        .frame(maxWidth: Self.columnWidth)
                        .padding(.horizontal, AaruSpace.large)
                        .padding(.top, isWide ? AaruSpace.xxlarge : AaruSpace.medium)
                        .padding(.bottom, AaruSpace.section)
                        .frame(maxWidth: .infinity)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
            }
        }
        .background(Color(.paper))
        // The Board outlives switching to Lately and back. Shown again after a minute, it reloads
        // page one quietly: what is on screen stays until the new page replaces it (older pages
        // go). Pull to refresh and ⌘R reload it too.
        .task {
            if !board.hasLoaded || board.isStale() {
                await board.load()
            }
        }
        .refreshable { await board.load() }
        .refreshesOnCommand(.friends) { await board.load() }
        .onChange(of: board.sort) {
            Task {
                switchingSort = true
                await board.load()
                switchingSort = false
            }
        }
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: board.problem) { board.problem = nil } }
    }

    /// The composer sits outside the lazy stack, so a half-written post survives scrolling far down.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostComposer(board: board)
                .padding(.bottom, AaruSpace.xlarge)
            sortPicker
                .padding(.bottom, AaruSpace.small)
            posts
        }
    }

    private var posts: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if !board.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AaruSpace.section)
            } else if let empty = BoardRules.empty(postCount: board.posts.count, friendCount: social.friends.count) {
                emptyBoard(empty)
                    .padding(.top, AaruSpace.xxlarge)
            }
            ForEach(board.posts, id: \.id) { post in
                Divider()
                PostRow(post: post, myHandle: social.handle, board: board)
                    .padding(.vertical, AaruSpace.large)
            }
            if board.canShowOlder {
                showOlder
                    .padding(.top, AaruSpace.small)
            }
        }
    }

    private var sortPicker: some View {
        @Bindable var board = board
        return HStack(spacing: AaruSpace.medium) {
            Picker("Order posts by", selection: $board.sort) {
                ForEach(BoardModel.Sort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if switchingSort {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func emptyBoard(_ empty: BoardRules.Empty) -> some View {
        switch empty {
        case .noFriends:
            OwlUnavailableView(
                title: "Posts from your friends show here",
                message: "Invite someone from Lately."
            ) {
                Button("Open Lately", action: onShowLately)
                    .buttonStyle(.bordered)
            }
        case .quiet:
            OwlUnavailableView(title: "Nothing yet", message: "Say what you're watching.", pose: .sleeping)
        }
    }

    private var showOlder: some View {
        Button {
            Task {
                loadingOlder = true
                await board.showOlder()
                loadingOlder = false
            }
        } label: {
            ZStack {
                Text("Show older").opacity(loadingOlder ? 0 : 1)
                if loadingOlder {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(loadingOlder)
    }
}
