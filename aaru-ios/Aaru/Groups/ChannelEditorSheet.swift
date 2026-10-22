import SwiftUI

/// A channel's name and topic. The server lowercases the name and turns spaces into dashes.
struct ChannelEditorSheet: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var topic = ""
    @State private var saving = false
    @State private var confirmsDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("#").foregroundStyle(Color(.muted))
                        TextField("movie-night", text: $name)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    }
                    TextField("Topic (optional)", text: $topic, axis: .vertical)
                        .lineLimit(1 ... 3)
                } footer: {
                    Text("Lowercase, with dashes for spaces.")
                }
                if let problem = groups.problem {
                    Text(problem).foregroundStyle(Color(.danger))
                }
                if !channel.isDefault {
                    Section {
                        Button("Delete channel", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete #\(channel.name)?", isPresented: $confirmsDelete) {
                Button("Delete channel", role: .destructive) {
                    Task {
                        if await groups.deleteChannel(channel, in: groupID) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Every group message in it goes, for everyone.")
            }
        }
        .onAppear {
            groups.problem = nil
            name = channel.name
            topic = channel.topic ?? ""
        }
    }

    private func save() {
        Task {
            saving = true
            defer { saving = false }
            if await groups.updateChannel(channel, in: groupID, name: name, topic: topic) {
                dismiss()
            }
        }
    }
}
