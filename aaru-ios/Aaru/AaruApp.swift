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
        AaruType.registerFonts()
    }

    var body: some Scene {
        mainWindow
        #if os(macOS)
            // Cmd-, opens the same Settings the tab shows.
            Settings {
                SettingsWindow(
                    api: services.api, imports: services.imports, library: services.library, lists: services.lists
                )
                .environment(services.session)
                .tint(Color(.accent))
                .appliesAppearance()
            }
        #endif
    }

    private var mainWindow: some Scene {
        let scene = WindowGroup {
            RootView(
                api: services.api, library: services.library, lists: services.lists, imports: services.imports,
                groups: services.groups, realtime: services.realtime
            )
            .environment(services.session)
            // The asset catalog's global accent (NSAccentColorName) does not reach SwiftUI on
            // iOS 26, so the brand teal is set here. Views use `Color(.accent)`, never
            // `Color.accentColor`.
            .tint(Color(.accent))
            .appliesAppearance()
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
