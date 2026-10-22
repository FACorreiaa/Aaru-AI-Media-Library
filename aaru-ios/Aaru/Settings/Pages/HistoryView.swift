import SwiftUI

/// Settings → Your data → History (UX-060): every journaled action, newest first, who made it
/// (you, an import, a connection), and Undo. An undo is journaled too and shows here.
struct HistoryView: View {
    let model: HistoryModel
    /// After an undo: the library and lists catch up.
    var onUndone: () async -> Void

    @State private var confirming: JournalAction?

    var body: some View {
        @Bindable var model = model
        content
            .background(Color(.paper))
            .navigationTitle("History")
            .safeAreaInset(edge: .bottom) {
                ProblemBanner(message: model.problem) { model.problem = nil }
            }
            .refreshable { await model.load() }
            .refreshesOnCommand(.settings) { await model.load() }
            .task { await model.load() }
            .confirmationDialog(
                "Undo “\(confirming?.summary ?? "")”?",
                isPresented: $confirming.isPresent,
                titleVisibility: .visible,
                presenting: confirming
            ) { action in
                Button("Undo") { Task { await undo(action) } }
            } message: { action in
                Text(action.itemIds.count > 1
                    ? "This puts back \(action.itemIds.count) titles as they were before."
                    : "This puts it back as it was before.")
            }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.loadFailure, !model.hasLoaded {
            LoadFailedView(title: "History didn't load", message: failure) { await model.load() }
        } else if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.actions.isEmpty {
            ContentUnavailableView(
                "Nothing yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("What you add, change or remove shows up here, with Undo.")
            )
        } else {
            List(model.actions, id: \.id) { action in
                HistoryRow(action: action, undoing: model.undoing == action.id) { confirming = action }
                    .listRowBackground(Color(.surface))
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func undo(_ action: JournalAction) async {
        if await model.undo(action) {
            await onUndone()
        }
    }
}

/// One action: what happened, by whom and when, and Undo while it can be undone.
private struct HistoryRow: View {
    let action: JournalAction
    let undoing: Bool
    var onUndo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: action.symbol)
                .foregroundStyle(action.undoneAt == nil ? Color(.accent) : Color(.muted))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.summary)
                    .foregroundStyle(action.undoneAt == nil ? Color(.ink) : Color(.muted))
                    .strikethrough(action.undoneAt != nil)
                Text("\(action.byline) · \(action.createdAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
                if action.undoneAt != nil {
                    Text("Undone").font(.caption.weight(.medium)).foregroundStyle(Color(.muted))
                }
            }
            Spacer(minLength: 8)
            if undoing {
                ProgressView()
            } else if action.canUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Undo \(action.summary)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if action.canUndo {
                Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(
            model: HistoryModel(preview: [
                JournalAction(
                    id: "1", actor: .user, kind: "add", summary: "Added Andor", itemIds: ["a"], createdAt: .now
                ),
                JournalAction(
                    id: "2", actor: .externalAgent, kind: "update", summary: "Marked Severance watching",
                    itemIds: ["b"], createdAt: .now.addingTimeInterval(-3600), agentName: "Claude"
                ),
                JournalAction(
                    id: "3", actor: .user, kind: "import", summary: "Imported 212 titles from Letterboxd",
                    itemIds: ["c", "d"], createdAt: .now.addingTimeInterval(-86400),
                    undoneAt: .now.addingTimeInterval(-600)
                ),
            ]),
            onUndone: {}
        )
    }
    .environment(AppRouter())
}
