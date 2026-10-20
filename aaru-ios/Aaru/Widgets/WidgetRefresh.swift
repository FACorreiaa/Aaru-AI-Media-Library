#if os(iOS)
    import BackgroundTasks
    import Foundation

    /// Keeps the widgets' snapshot fresh while the app is closed (WID-001): an app-refresh task,
    /// asked for about once an hour (iOS decides when it really runs), that reloads up next and the
    /// calendar window and republishes. The identifier is listed in Info.plist.
    enum WidgetRefresh {
        static let taskID = SessionKeychain.appService + ".widget-refresh"

        /// Asks iOS for the next run. Harmless to call often: one pending request per identifier.
        static func schedule() {
            let request = BGAppRefreshTaskRequest(identifier: taskID)
            request.earliestBeginDate = .now.addingTimeInterval(3600)
            try? BGTaskScheduler.shared.submit(request)
        }

        /// The task itself: refresh, then queue the next one. Signed out: nothing to do.
        static func run() async {
            schedule()
            await NowWatching.endStale()
            guard let api = SharedAPI.client() else { return }
            try? await WidgetSync.refresh(api: api)
        }
    }
#endif
