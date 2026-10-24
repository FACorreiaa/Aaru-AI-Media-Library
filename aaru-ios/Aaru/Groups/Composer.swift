import AaruAPI
import SwiftUI

/// One growing box. Return sends on Mac (Option-Return adds a line); on iPhone and iPad the send
/// button sends. Typing `@` suggests members.
struct Composer: View {
    @Binding var text: String
    let channelName: String
    let editing: GroupMessage?
    let members: [GroupMember]
    /// `@aaru` answers here, so it leads the suggestions.
    var agent = false
    /// Title channels only: how the message is marked for spoilers.
    var spoiler: Binding<SpoilerChoice>?
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onCancelEdit: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= ChannelModel.maxLength
    }

    /// Handles to suggest: Aaru first when it answers here, then members.
    private var suggestions: [String] {
        MentionSuggestions.suggestions(for: text, handles: members.map(\.user.handle), agent: agent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing != nil {
                HStack {
                    Label("Editing", systemImage: "pencil").font(.caption)
                    Spacer()
                    Button("Cancel", action: onCancelEdit).font(.caption).buttonStyle(.borderless)
                }
                .foregroundStyle(Color(.muted))
            }
            if let spoiler, editing == nil {
                SpoilerMenu(choice: spoiler)
            }
            MentionSuggestionStrip(suggestions: suggestions) { text = MentionSuggestions.complete(text, with: $0) }
            HStack(alignment: .bottom, spacing: 4) {
                field
                Button(editing == nil ? "Send" : "Save", systemImage: "arrow.up.circle.fill", action: onSend)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(canSend ? Color(.accent) : Color(.muted))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(editing == nil ? "Send (⌘↩)" : "Save (⌘↩)")
            }
            if text.count > ChannelModel.maxLength - 500 {
                Text("\(text.count) / \(ChannelModel.maxLength)")
                    .font(.caption)
                    .foregroundStyle(text.count > ChannelModel.maxLength ? Color(.danger) : Color(.muted))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var field: some View {
        TextField("Write in #\(channelName)", text: $text, axis: .vertical)
            .lineLimit(1 ... 6)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .card()
            .focused(focused)
        #if os(macOS)
            .onSubmit(onSend)
        #endif
    }
}
