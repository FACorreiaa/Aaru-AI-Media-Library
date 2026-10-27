import SwiftUI

/// One row of a working import's ledger (DESIGN §3, IMP-017): a step, not a spinner.
struct ImportStep: Identifiable, Equatable {
    enum State { case done, current, todo }

    let label: String
    var detail: String?
    let state: State
    /// 0…1 on the matching step while it runs.
    var progress: Double?

    var id: String {
        label
    }
}

extension ImportJob {
    /// The steps of a queued or running import, in order; empty once it has a plan or an end.
    /// The same steps as the web's `importSteps`.
    var steps: [ImportStep] {
        guard isWorking else { return [] }
        if isListens {
            return listenSteps
        }
        let running = state == .running
        let known = rowsTotal > 0
        let entries = "\(rowsTotal.formatted()) \(rowsTotal == 1 ? "entry" : "entries")"
        let fromAccount = source == .trakt || source == .anilist
        let matching = running && known && rowsMatched < rowsTotal
        let checking = running && known && rowsMatched >= rowsTotal
        let waiting: String? = if running {
            nil
        } else if let errorSummary {
            "Paused: \(errorSummary) Trying again shortly; nothing is lost."
        } else {
            "Starts in a few seconds."
        }
        let matched: String? = if matching {
            "\(rowsMatched.formatted()) of \(rowsTotal.formatted())"
        } else if checking {
            "All \(entries)"
        } else {
            nil
        }
        return [
            ImportStep(
                label: isCapture ? "Read what you sent"
                    : fromAccount ? "Read your \(sourceLabel) library" : "Read your file",
                detail: known ? entries : nil,
                state: known ? .done : running ? .current : .todo
            ),
            ImportStep(label: "Wait for a free slot", detail: waiting, state: running ? .done : .current),
            ImportStep(
                label: "Match each title to the catalog",
                detail: matched,
                state: checking ? .done : matching ? .current : .todo,
                progress: matching ? Double(rowsMatched) / Double(rowsTotal) : nil
            ),
            ImportStep(label: "Check against your library", state: checking ? .current : .todo),
            ImportStep(label: "Ready for you to review", detail: "Nothing is added until you approve.", state: .todo),
        ]
    }
}

/// The ledger rows. Nothing loops: the bar moves only when the count does.
struct ImportLedger: View {
    let steps: [ImportStep]

    var body: some View {
        ForEach(steps) { step in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol(step.state))
                    .foregroundStyle(step.state == .todo ? Color(.muted) : Color(.accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.label)
                        .fontWeight(step.state == .todo ? .regular : .medium)
                        .foregroundStyle(step.state == .todo ? Color(.muted) : .primary)
                    if let detail = step.detail {
                        Text(detail).font(.footnote).foregroundStyle(Color(.muted)).monospacedDigit()
                    }
                    if let progress = step.progress {
                        ProgressView(value: progress)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(state(step.state))
        }
    }

    private func symbol(_ state: ImportStep.State) -> String {
        switch state {
        case .done: "checkmark.circle.fill"
        case .current: "circle.inset.filled"
        case .todo: "circle"
        }
    }

    private func state(_ state: ImportStep.State) -> String {
        switch state {
        case .done: "Done"
        case .current: "In progress"
        case .todo: "Not started"
        }
    }
}

private extension ImportJob {
    /// A listening import's steps (MUS-004): the plays are read, then checked against the log. The
    /// same steps as the web's.
    var listenSteps: [ImportStep] {
        let running = state == .running
        let fromAccount = source == .lastfm || source == .listenbrainz
        // An account is read page by page while running; the count grows as it goes.
        let reading = fromAccount && running
        let plays = "\(rowsTotal.formatted()) \(rowsTotal == 1 ? "play" : "plays")"
        let waiting: String? = if running {
            nil
        } else if let errorSummary {
            "Paused: \(errorSummary) Trying again shortly; nothing is lost."
        } else {
            "Starts in a few seconds."
        }
        return [
            ImportStep(
                label: fromAccount ? "Read your \(sourceLabel) listens" : "Read your file",
                detail: rowsTotal > 0 ? (reading ? "\(plays) so far" : plays) : nil,
                state: reading ? .current : fromAccount && !running ? .todo : .done
            ),
            ImportStep(label: "Wait for a free slot", detail: waiting, state: running ? .done : .current),
            ImportStep(label: "Check against your listening log", state: running && !reading ? .current : .todo),
            ImportStep(label: "Ready for you to review", detail: "Nothing is added until you approve.", state: .todo),
        ]
    }
}
