import AaruAPI
import SwiftUI

/// Settings → Your data (§18): recap shortcuts, History with Undo (UX-060), and Export.
struct DataPage: View {
    let model: DataModel
    /// Recaps read their own data.
    let api: Client?

    @State private var recap: RecapPeriod?

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
        }
        .settingsPage("Your data", problem: $model.problem)
        .recapStory($recap, api: api)
    }
}
