import SwiftUI
import WidgetKit

@main
struct AaruApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    AppGroup.lastAppLaunch = .now
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}
