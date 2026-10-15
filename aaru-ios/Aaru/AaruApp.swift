import SwiftUI
import WidgetKit

@main
struct AaruApp: App {
    @State private var services = AppServices()

    init() {
        // Posters are referenced by catalog URL, never re-hosted; keep them warm on disk.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView(api: services.api, library: services.library, lists: services.lists)
                .environment(services.session)
                .task {
                    AppGroup.lastAppLaunch = .now
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}
