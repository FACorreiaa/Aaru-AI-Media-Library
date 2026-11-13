import AaruAPI
import SwiftUI

/// Settings → Your data (§18): recap shortcuts, History with Undo (UX-060), and Export.
struct DataPage: View {
    let model: DataModel
    /// Recaps read their own data.
    let api: Client?

    @State private var recap: RecapPeriod?
    @State private var confirmingDeleteChats = false
    @Environment(AISharingModel.self) private var aiSharing: AISharingModel?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(RecapPeriod.shortcuts(now: .now, calendar: .aaru)) { period in
                    Button(period.label, systemImage: "sparkles") { recap = period }
                }
            } header: {
                Text("Recaps")
            } footer: {
                Text("A month or a year of what you watched, read and listened to, played as a story.")
            }
            Section {
                NavigationLink(value: SettingsRoute.history) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("Every change to your library, newest first: yours, an import's or a connection's, with Undo.")
            }
            ExportDataSection(model: model)
            Section {
                NavigationLink(value: SettingsRoute.aiSharing) {
                    LabeledContent {
                        if let state = aiSharing?.state {
                            Text(state == .allowed ? String(localized: "On") : String(localized: "Off"))
                        }
                    } label: {
                        Label("AI data sharing", systemImage: "lock.shield")
                    }
                }
            } footer: {
                Text("Whether Aaru may send your data to Anthropic to answer the owl, capture and @aaru in groups.")
            }
            Section {
                NavigationLink(value: SettingsRoute.chats) {
                    Label("Chats with Aaru", systemImage: "bubble.left.and.bubble.right")
                }
                Button("Delete my chats with Aaru", role: .destructive) {
                    confirmingDeleteChats = true
                }
                .disabled(model.deletingChats || !model.isAvailable)
            } footer: {
                Text("Aaru keeps your chats until you delete them, one at a time or all at once.")
            }
        }
        .settingsPage(String(localized: "Your data"), problem: $model.problem)
        .recapStory($recap, api: api)
        .confirmationDialog(
            "Delete your chats with Aaru?",
            isPresented: $confirmingDeleteChats,
            titleVisibility: .visible
        ) {
            Button("Delete my chats", role: .destructive) {
                Task { await model.deleteChats() }
            }
        } message: {
            Text("""
            This removes everything you and Aaru said. Changes Aaru made to your library stay, \
            and your daily count of questions stays.
            """)
        }
    }
}
