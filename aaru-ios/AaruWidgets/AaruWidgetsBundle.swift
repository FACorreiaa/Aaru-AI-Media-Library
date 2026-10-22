import SwiftUI
import WidgetKit

@main
struct AaruWidgetsBundle: WidgetBundle {
    init() {
        WidgetType.registerFont()
    }

    var body: some Widget {
        UpNextWidget()
        CountdownWidget()
        WeekWidget()
        ListeningWidget()
        StreakWidget()
        #if os(iOS)
            NowWatchingLiveActivity()
        #endif
    }
}
