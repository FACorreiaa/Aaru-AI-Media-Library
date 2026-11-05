import AaruAPI
import SwiftUI

/// IMP-021: "Match all" over a review's unmatched rows. One call does what fits in a few seconds, so
/// this asks again while the count falls and shows how far it got. Every guess is the person's to
/// check: nothing reaches the library until they approve.
struct MatchAllButton: View {
    let id: String
    let imports: ImportsModel
    /// How many rows the server has yet to try.
    let guessable: Int
    let onBatch: (MatchedImportRows) -> Void

    @State private var progress: (done: Int, total: Int)?

    var body: some View {
        Button {
            Task { await run() }
        } label: {
            if let progress {
                Text("Matching \(progress.done) of \(progress.total)")
                    .monospacedDigit()
            } else {
                Text("Match all")
            }
        }
        .font(.subheadline.weight(.medium))
        .textCase(nil)
        .buttonStyle(.borderless)
        .disabled(progress != nil)
        .frame(minHeight: 44)
    }

    private func run() async {
        let total = guessable
        var left = total
        progress = (0, total)
        defer { progress = nil }
        while left > 0 {
            guard let answer = await imports.matchAll(id) else { return }
            onBatch(answer)
            progress = (total - answer.remaining, total)
            if answer.remaining >= left {
                imports.problem = "The catalog did not answer. Try again in a moment."
                return
            }
            left = answer.remaining
        }
    }
}

/// A row Match all filled: what it found, and what the list said (IMP-021).
struct ImportGuessLabel: View {
    let row: ImportRow
    let guess: Components.Schemas.ImportRowGuess

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterView(
                url: guess.posterUrl.flatMap(URL.init(string:)),
                kind: MediaKind(type: row._type, isAnime: false)
            )
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(guess.title)
                    .foregroundStyle(row.leftOut == true ? Color(.muted) : Color(.ink))
                if let byline = guess.byline {
                    Text(byline).font(.caption).foregroundStyle(Color(.muted))
                }
                Text("Best guess for \u{201C}\(row.title)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
        }
    }
}

/// One row of a review: its tick, what it says, and how to match it.
struct ImportReviewRow: View {
    let row: ImportRow
    let canTick: Bool
    let canChange: Bool
    let canFind: Bool
    /// Called with the row's new `leftOut`.
    let onTick: (Bool) -> Void
    let onFind: () -> Void

    var body: some View {
        HStack {
            if canTick {
                tick
            }
            if let guess = row.guess {
                ImportGuessLabel(row: row, guess: guess)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .foregroundStyle(row.leftOut == true ? Color(.muted) : Color(.ink))
                    if canTick, let author = row.author {
                        Text(author).font(.caption).foregroundStyle(Color(.muted))
                    }
                    if let reason = row.reason {
                        Text(reason).font(.caption).foregroundStyle(Color(.muted))
                    }
                }
            }
            if canChange {
                Spacer(minLength: 8)
                Button("Change", action: onFind)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Change the guess for \(row.title)")
            }
            if canFind {
                Spacer(minLength: 8)
                Button("Find it", action: onFind)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Find \(row.title)")
            }
        }
    }

    private var tick: some View {
        let ticked = row.leftOut != true
        return Button(
            ticked ? "Leave out \(row.title)" : "Add \(row.title)",
            systemImage: ticked ? "checkmark.circle.fill" : "circle"
        ) {
            onTick(ticked)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(ticked ? Color(.accent) : Color(.muted))
        .buttonStyle(.borderless)
        .frame(minWidth: 44, minHeight: 44)
    }
}

extension ImportRow {
    /// "Dune (2021)": the name as the import file had it.
    var label: String {
        [title, year.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
    }
}
