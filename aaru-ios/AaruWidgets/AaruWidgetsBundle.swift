import SwiftUI
import WidgetKit

@main
struct AaruWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        CountdownWidget()
        WeekWidget()
        ListeningWidget()
        #if os(iOS)
            NowWatchingLiveActivity()
        #endif
    }
}
