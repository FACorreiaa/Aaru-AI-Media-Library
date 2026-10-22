import SwiftUI

/// Settings → Notifications (§18): three switches, per account, on every platform (UX-032).
struct NotificationsPage: View {
    let model: NotificationsModel

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("New episodes", isOn: binding(\.airing))
                Toggle("Mentions in groups", isOn: binding(\.groupMentions))
                Toggle("Group invites", isOn: binding(\.groupInvites))
            } footer: {
                Text(footer)
            }
            .disabled(!model.hasLoaded)
        }
        .settingsPage("Notifications", problem: $model.problem)
        .task { await model.load() }
    }

    private var footer: String {
        var lines = [
            "New episodes of shows you are watching, mentions in groups you have not muted, and invites. A "
                + "mention says who tagged you and where, never what they wrote.",
            "Requests from your connected agents always alert you.",
        ]
        #if os(macOS)
            lines.append("Alerts go to your iPhone and your browsers.")
        #endif
        return lines.joined(separator: "\n\n")
    }

    /// The switch shows the saved value; flipping it saves, and asks the system first on iPhone.
    private func binding(_ setting: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: setting] },
            set: { value in Task { await model.set(setting, value) } }
        )
    }
}
