import AaruAPI
import AaruCore
import SwiftUI

/// PostComposer (BOARD-003): the inline box on top of the Board. One quiet line until it is
/// focused, then it grows and offers a title. With a title come the stars, the spoiler mark, and
/// one line saying what posting does to your library. No sheet for writing and no floating button
/// (owner, 2026-10-23); only the title picker is a sheet, as everywhere else.
struct PostComposer: View {
    let board: BoardModel
    /// Who `@` suggests: your friends. Never `@aaru` until BOARD-004.
    let mentionHandles: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppRouter.self) private var router: AppRouter?
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var picked: BoardTitlePick?
    @State private var rating: Double?
    @State private var spoiler = SpoilerChoice.auto
    @State private var picking = false
    @State private var posting = false

    /// Open while focused, and while anything is in it.
    private var expanded: Bool {
        focused || !text.isEmpty || picked != nil || picking
    }

    private var remaining: Int? {
        BoardRules.remaining(text)
    }

    private var tooLong: Bool {
        (remaining ?? 0) < 0
    }

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tooLong && !posting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            TextField("Write something…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(expanded ? 3 ... 8 : 1 ... 1)
                .focused($focused)
                .accessibilityLabel("Write a post")
            MentionSuggestionStrip(suggestions: MentionSuggestions.suggestions(for: text, handles: mentionHandles)) {
                text = MentionSuggestions.complete(text, with: $0)
            }
            if expanded {
                if let picked {
                    PickedTitle(
                        title: picked,
                        rating: $rating,
                        spoiler: $spoiler,
                        onRemove: removeTitle
                    )
                } else {
                    Button("Add a title", systemImage: "plus") { picking = true }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .frame(minHeight: 32)
                }
                actions
            }
        }
        .padding(AaruSpace.medium)
        .background(Color(.surface), in: .rect(cornerRadius: AaruRadius.panel, style: .continuous))
        .overlay {
            if tooLong || focused {
                RoundedRectangle(cornerRadius: AaruRadius.panel, style: .continuous)
                    .strokeBorder(tooLong ? Color(.danger) : Color(.accent).opacity(AaruAlpha.half))
            }
        }
        .animation(reduceMotion ? nil : AaruMotion.ease(), value: expanded)
        // "Write about this" from a title page: take the title once, open, and clear it.
        .onChange(of: router?.pendingBoardTitle, initial: true) { _, pick in
            guard let pick else { return }
            picked = pick
            focused = true
            router?.pendingBoardTitle = nil
        }
        .sheet(isPresented: $picking) {
            TitlePickerSheet(api: board.api, navigationTitle: "Add a title") { hit in
                picked = BoardTitlePick(hit)
                return true
            }
        }
    }

    private var actions: some View {
        HStack(spacing: AaruSpace.medium) {
            if let remaining {
                Text(remaining, format: .number)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(tooLong ? Color(.danger) : Color(.muted))
                    .accessibilityLabel(tooLong ? "\(-remaining) characters over" : "\(remaining) characters left")
            }
            Spacer(minLength: 0)
            Button("Cancel", action: reset)
                .buttonStyle(.borderless)
                .foregroundStyle(Color(.muted))
            Button(action: post) {
                Text("Post")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.paper))
                    .opacity(posting ? 0 : 1)
                    .overlay {
                        if posting {
                            ProgressView().controlSize(.small).tint(Color(.paper))
                        }
                    }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(.ink))
            .disabled(!canPost)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func removeTitle() {
        picked = nil
        rating = nil
        spoiler = .auto
    }

    /// Back to one empty line.
    private func reset() {
        text = ""
        removeTitle()
        focused = false
    }

    private func post() {
        guard canPost else { return }
        Task {
            posting = true
            let posted = await board.post(body: text, title: picked, rating: rating, spoiler: spoiler)
            posting = false
            if posted {
                reset()
            }
        }
    }
}

/// The title a post is about, in the composer: poster, name and year, then the stars, the spoiler
/// mark, and what posting does to the library ("Adds Severance to Watched, ★★★★½").
private struct PickedTitle: View {
    let title: BoardTitlePick
    @Binding var rating: Double?
    @Binding var spoiler: SpoilerChoice
    let onRemove: () -> Void

    private var kind: MediaKind {
        MediaKind(type: title.type, isAnime: title.isAnime)
    }

    private var effect: String? {
        BoardRules.reviewEffect(
            title: title.title,
            isShow: title.type == .show,
            inLibrary: title.inLibrary,
            rating: rating,
            finishedLabel: LibraryStatus.finished.label(for: kind),
            inProgressLabel: LibraryStatus.inProgress.label(for: kind)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            HStack(spacing: AaruSpace.medium) {
                PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                    .frame(width: 40)
                Text(title.year.map { "\(title.title) · \(String($0))" } ?? title.title)
                    .font(.aaruDisplay(.body))
                    .lineLimit(2)
                Spacer(minLength: AaruSpace.small)
                Button("Remove \(title.title)", systemImage: "xmark.circle.fill", action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color(.muted))
                    .frame(minWidth: 44, minHeight: 44)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    RatingStars(rating: rating) { rating = $0 }
                    Spacer(minLength: AaruSpace.medium)
                    SpoilerMenu(choice: $spoiler)
                }
                VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                    RatingStars(rating: rating) { rating = $0 }
                    SpoilerMenu(choice: $spoiler)
                }
            }
            if let effect {
                Text(effect)
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
        .padding(AaruSpace.medium)
        .background(Color(.paper), in: .rect(cornerRadius: AaruRadius.field, style: .continuous))
    }
}
