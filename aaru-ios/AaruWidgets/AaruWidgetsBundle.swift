import SwiftUI
import WidgetKit

@main
struct AaruWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        CountdownWidget()
        WeekWidget()
        ListeningWidget()
        StreakWidget()
        #if os(iOS)
            NowPlayingLiveActivity()
            NowWatchingLiveActivity()
        #endif
    }
}
