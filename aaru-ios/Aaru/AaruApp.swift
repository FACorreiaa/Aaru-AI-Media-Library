import SwiftUI
import WidgetKit

@main
struct AaruApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView(api: services.api)
                .environment(services.session)
                .task {
                    AppGroup.lastAppLaunch = .now
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}
