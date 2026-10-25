import SwiftUI

/// Claim or change the handle, and the optional display name.
struct ProfileEditor: View {
    let model: SocialModel
    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Color(.muted)).accessibilityHidden(true)
                    TextField("Handle", text: $handle)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
            } footer: {
                Text(SocialModel.handleProblem(handle) ?? "3–20 letters, numbers or underscores.")
            }
            if let problem = model.problem {
                Text(problem).foregroundStyle(Color(.danger))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Name and handle")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        saving = true
                        if await model.saveProfile(handle: handle, displayName: name) {
                            dismiss()
                        }
                        saving = false
                    }
                }
                .disabled(saving || SocialModel.handleProblem(handle) != nil)
            }
        }
        .onAppear {
            model.problem = nil
            handle = model.handle ?? ""
            name = model.displayName ?? ""
        }
    }
}
