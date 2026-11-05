import AaruAPI
import SwiftUI

/// One Chat turn in the Assistant card: the question, then Aaru's reply as far as it has come.
struct AssistantTurnView: View {
    let turn: AssistantTurn
    let model: AssistantModel
    let api: Client?
    let library: LibraryModel
    let onOpenTitle: (TitleSummary) -> Void
    let onShowHistory: () -> Void

    private var reply: ChatReply {
        turn.reply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            question
            if !reply.text.isEmpty {
                Text(Self.formatted(reply.text))
                    .font(.body)
                    .foregroundStyle(Color(.ink))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let line = statusLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            if !reply.titles.isEmpty {
                titles
            }
            // A Plan needs a client; without one there is nothing it could answer.
            if let plan = reply.plan, let api {
                PlanCardView(
                    api: api,
                    plan: model.decidedPlans[plan.id] ?? plan,
                    onShowHistory: onShowHistory,
                    onDecided: { decided in
                        Task { await model.planDecided(decided) }
                    }
                )
                .id(plan.id)
            }
            if let importID = reply.importID {
                // BOOK-003: the list waits in an ordinary review, opened as a capture's push opens it.
                Button("Review the list") { PushInbox.shared.importID = importID }
                    .buttonStyle(.borderedProminent)
            }
            if let actionID = reply.actionID {
                UndoRibbon(turn: turn, actionID: actionID, model: model)
            }
            if let problem = reply.problem {
                Text(problem)
                    .font(.footnote)
                    // "Aaru is resting" is not a fault.
                    .foregroundStyle(reply.state == .stopped ? Color(.muted) : Color(.danger))
            }
        }
    }

    private var question: some View {
        Text(turn.question)
            .font(.body)
            .foregroundStyle(Color(.ink))
            .textSelection(.enabled)
            .padding(.horizontal, AaruSpace.medium)
            .padding(.vertical, AaruSpace.small)
            .background(
                Color(.accent).opacity(AaruAlpha.wash),
                in: .rect(cornerRadius: AaruRadius.panel, style: .continuous)
            )
            .padding(.leading, AaruSpace.block)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The server's line while it works; before its first frame, the words the group channels use.
    private var statusLine: String? {
        if let status = reply.status {
            return status
        }
        return reply.state == .working && reply.text.isEmpty ? "Aaru is thinking…" : nil
    }

    private var titles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AaruSpace.medium) {
                ForEach(reply.titles, id: \.id) { title in
                    AgentTitleCard(
                        title: title,
                        onAdd: { await library.add(CatalogHit($0), status: .wishlist, api: api) },
                        onOpen: onOpenTitle
                    )
                }
            }
            .padding(.vertical, AaruSpace.xsmall)
        }
    }

    /// Inline Markdown only, keeping line breaks; anything it can't read shows as plain text.
    private static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// What a turn changed, spoken or typed, and its Undo. It stays until the card clears: a misheard
/// sentence can apply one change straight away, so this is not a timed toast.
private struct UndoRibbon: View {
    let turn: AssistantTurn
    let actionID: String
    let model: AssistantModel

    /// `AssistantModel.undo` marks the turn only after the server and a library sync, so a second
    /// tap in between would undo twice.
    @State private var undoing = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            if turn.undone {
                Text("Undone.")
                    .foregroundStyle(Color(.muted))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AaruSpace.xsmall) {
                    Text("\(turn.reply.actionSummary ?? "Aaru changed your library") ·")
                        .foregroundStyle(Color(.ink))
                    Button("Undo", action: undo)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(.accent))
                        .buttonStyle(.plain)
                        .disabled(undoing)
                }
                if let problem {
                    Text(problem)
                        .foregroundStyle(Color(.danger))
                }
            }
        }
        .font(.footnote)
        .padding(.horizontal, AaruSpace.medium)
        .padding(.vertical, AaruSpace.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .contain)
    }

    private func undo() {
        undoing = true
        problem = nil
        Task {
            problem = await model.undo(turn.id)
            undoing = false
        }
    }
}
