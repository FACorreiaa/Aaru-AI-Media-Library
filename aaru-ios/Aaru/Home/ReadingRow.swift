import AaruAPI
import SwiftUI

/// Home's Reading row (owner, 2026-10-25): books and manga in progress, last touched first, as
/// Now cards with their one step (page, chapter, read). Each step offers Undo in the toast, as a
/// tick does. Past `HomeModel.readingLimit` cards, "All N" opens the Reading page. Matches the
/// web's `ReadingRow`.
struct ReadingRow: View {
    let items: [NowItem]
    let library: LibraryModel
    let api: Client?
    let width: CGFloat
    /// Opens the Reading page (APP-018).
    var onShowAll: () -> Void
    /// Shows a failed write in Home's banner.
    var onProblem: (String) -> Void

    /// Nil in previews.
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    var body: some View {
        HomeRow(
            title: "Reading",
            trailing: items.count > HomeModel.readingLimit ? ("All \(items.count)", onShowAll) : nil
        ) {
            ForEach(items.prefix(HomeModel.readingLimit)) { item in
                NowCard(item: item, isPending: library.nowPending.contains(item.id)) { action in
                    Task { await run(action, on: item) }
                }
                .frame(width: width)
            }
        }
    }

    private func run(_ action: NowAction, on item: NowItem) async {
        let write = await library.perform(action, on: item, api: api)
        if let problem = write.problem {
            onProblem(problem)
        } else if let id = write.action, let message = Self.message(action, title: item.entry.title.title) {
            toasts?.show(message) { await library.undo(id, api: api) }
        }
    }

    /// What one step did, for its toast; the same words as the web's.
    static func message(_ action: NowAction, title: String) -> String? {
        switch action {
        case let .page(page): "On page \(page) of \(title)"
        case let .chapter(chapter): "Read to chapter \(chapter) of \(title)"
        case .finish: "Marked \(title) read"
        case .tickNext: nil
        }
    }
}

extension HomeModel {
    /// Cards in the Reading row; "All N" opens the Reading page past it.
    nonisolated static let readingLimit = 12

    /// Books and manga in progress, last touched first. Read from the shelf, so a page or chapter
    /// moved anywhere shows here at once, offline too.
    var reading: [NowItem] {
        library?.groupItems(.reading, kind: nil).active ?? []
    }
}
