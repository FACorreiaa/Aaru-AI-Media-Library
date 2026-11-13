import SwiftUI

/// Settings → Your data → AI data sharing (PRV-002): the disclosure the first run shows, with
/// the switch. Off stops anything new going to Aaru's AI provider; it deletes nothing.
struct AISharingPage: View {
    @Environment(AISharingModel.self) private var model: AISharingModel?
    /// What the switch was just set to, until the server has it. A failed save puts it back.
    @State private var pending: Bool?

    private var isOn: Binding<Bool> {
        Binding {
            pending ?? model?.isAllowed ?? false
        } set: { allowed in
            guard let model, pending == nil else { return }
            pending = allowed
            Task {
                await model.set(allowed)
                pending = nil
            }
        }
    }

    private var problem: Binding<String?> {
        Binding {
            model?.problem
        } set: {
            model?.problem = $0
        }
    }

    var body: some View {
        Form {
            Section {
                AISharingDisclosure {}
            }
            Section {
                Toggle("AI data sharing", isOn: isOn)
                    // Not before `Me` has been read: the switch would show a guess.
                    .disabled(model?.state == nil || pending != nil)
                    .accessibilityIdentifier("ai-sharing-switch")
            } footer: {
                Text("""
                Turning this off stops Aaru sending anything new to Anthropic. Chats you already had \
                stay until you delete them, in Your data or from the owl's History.
                """)
            }
        }
        .settingsPage(String(localized: "AI data sharing"), problem: problem)
        .task { await model?.refresh() }
    }
}
