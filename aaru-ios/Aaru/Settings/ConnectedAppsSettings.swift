import AaruAPI
import SwiftUI

/// Settings → Connected apps: what reaches Aaru with a token of its own, Stremio and agents.
struct ConnectedAppsSettings: View {
    let api: Client?
    let imports: ImportsModel

    var body: some View {
        Form {
            StremioSection(api: api) { imports.problem = $0 }
            ConnectionsSection(api: api) { imports.problem = $0 }
        }
        .settingsForm(imports)
        .navigationTitle("Connected apps")
    }
}
