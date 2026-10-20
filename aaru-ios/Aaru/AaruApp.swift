import SwiftUI
import WidgetKit

@main
struct AaruApp: App {
    @State private var services = AppServices()
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
        @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        // Posters are referenced by catalog URL, never re-hosted; keep them warm on disk.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        let scene = WindowGroup {
            RootView(api: services.api, library: services.library, lists: services.lists, imports: services.imports)
                .environment(services.session)
                .task { WidgetCenter.shared.reloadAllTimelines() }
        }
        #if os(iOS)
            return scene
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        WidgetRefresh.schedule()
                    } else if phase == .active {
                        // A "Now watching" activity never outlives its episode by more than the grace.
                        Task { await NowWatching.endStale() }
                    }
                }
                .backgroundTask(.appRefresh(WidgetRefresh.taskID)) {
                    await WidgetRefresh.run()
                }
        #else
            return scene
        #endif
    }
}
