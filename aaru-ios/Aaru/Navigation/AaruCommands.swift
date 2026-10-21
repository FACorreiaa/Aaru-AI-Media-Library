import SwiftUI

/// The menu bar on the Mac, and the ⌘ shortcuts a hardware keyboard shows on iPad: New List
/// (⌘N), Search (⌘F), Refresh (⌘R), the Go menu (⌘1…⌘7), and the standard sidebar and toolbar
/// commands. ⌘, comes from the Settings scene.
struct AaruCommands: Commands {
    let router: AppRouter
    let session: SessionStore

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(replacing: .newItem) {
            Button("New List") { router.showLists(startingNew: true) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!session.isSignedIn)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Titles") { router.showsSearch = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!session.isSignedIn)
        }
        CommandGroup(before: .toolbar) {
            Button("Refresh") { router.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!session.isSignedIn)
            Divider()
        }
        CommandMenu("Go") {
            ForEach(Array(AppTab.goMenu.enumerated()), id: \.element) { index, destination in
                Button(destination.title) { router.select(destination) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            .disabled(!session.isSignedIn)
            #if os(iOS)
                Divider()
                Button("Settings") { router.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(!session.isSignedIn)
            #endif
        }
    }
}
