import SwiftUI

/// SCR-007: how to connect Aaru's browser extension. It connects from Chrome or Firefox on a
/// computer, where it opens Aaru's connect page; nothing to set up on this device.
struct BrowserExtensionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Finish an episode or a film on Netflix, Disney+ or Prime Video in your browser and it is "
                            + "marked watched here. A YouTube video shows in Now playing while it plays. "
                            + "The extension can’t read your library."
                    )
                }
                Section("On your computer") {
                    Label("Install Aaru for Chrome or Firefox.", systemImage: "1.circle")
                    Label("Click Aaru in the toolbar, then Connect.", systemImage: "2.circle")
                    Label("Approve on the page it opens.", systemImage: "3.circle")
                }
                Section {
                    Text("Not in the Chrome Web Store or Firefox Add-ons yet.")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Connected browsers appear in Settings → Connections, where you can disconnect them.")
                }
            }
            .navigationTitle("Browser extension")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
