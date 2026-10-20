import AaruAPI
import SwiftUI

/// One growing box. Return sends on Mac (Option-Return adds a line); on iPhone and iPad the send
/// button sends. Typing `@` suggests members.
struct Composer: View {
    @Binding var text: String
    let channelName: String
    let editing: GroupMessage?
    let members: [GroupMember]
    /// Title channels only: how the message is marked for spoilers.
    var spoiler: Binding<SpoilerChoice>?
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onCancelEdit: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= ChannelModel.maxLength
    }

    /// The `@` word being typed, without the `@`.
    private var mentionPrefix: String? {
        let word = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard text.last?.isWhitespace != true, word.hasPrefix("@") else { return nil }
        return String(word.dropFirst()).lowercased()
    }

    private var suggestions: [GroupMember] {
        guard let prefix = mentionPrefix else { return [] }
        return Array(members.filter { $0.user.handle.hasPrefix(prefix) }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing != nil {
                HStack {
                    Label("Editing message", systemImage: "pencil").font(.caption)
                    Spacer()
                    Button("Cancel", action: onCancelEdit).font(.caption).buttonStyle(.borderless)
                }
                .foregroundStyle(Color(.muted))
            }
            if let spoiler, editing == nil {
                SpoilerMenu(choice: spoiler)
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.user.userId) { member in
                            Button {
                                complete(member.user.handle)
                            } label: {
                                Label("@\(member.user.handle)", systemImage: "at")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                field
                Button(editing == nil ? "Send" : "Save", systemImage: "arrow.up.circle.fill", action: onSend)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(canSend ? Color(.accent) : Color(.muted))
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            if text.count > ChannelModel.maxLength - 500 {
                Text("\(text.count) / \(ChannelModel.maxLength)")
                    .font(.caption)
                    .foregroundStyle(text.count > ChannelModel.maxLength ? .red : Color(.muted))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var field: some View {
        TextField("Message #\(channelName)", text: $text, axis: .vertical)
            .lineLimit(1 ... 6)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.surface), in: RoundedRectangle(cornerRadius: 18))
            .focused(focused)
        #if os(macOS)
            .onSubmit(onSend)
        #endif
    }

    private func complete(_ handle: String) {
        guard let range = text.range(of: "@", options: .backwards) else { return }
        text.replaceSubrange(range.lowerBound..., with: "@\(handle) ")
    }
}
