import SwiftUI

/// A group's name: create or rename.
struct GroupNameSheet: View {
    let title: String
    let initial: String
    /// True when saved; the sheet then closes.
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .onSubmit(save)
                } footer: {
                    Text("Only friends you invite can find it.")
                }
            }
            .paperPage()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(saving || trimmed.isEmpty || trimmed.count > 50)
                }
            }
        }
        .onAppear {
            name = initial
            focused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty, trimmed.count <= 50 else { return }
        Task {
            saving = true
            if await onSave(trimmed) {
                dismiss()
            }
            saving = false
        }
    }
}
