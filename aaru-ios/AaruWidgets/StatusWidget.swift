import SwiftUI
import WidgetKit

/// Placeholder widget that proves the App Group is shared (REL-003).
/// The real widgets are WID-002…WID-006.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AaruStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Aaru")
        .description("Shows when Aaru was last opened.")
        .supportedFamilies([.systemSmall])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let lastAppLaunch: Date?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in _: Context) -> StatusEntry {
        StatusEntry(date: .now, lastAppLaunch: .now)
    }

    func getSnapshot(in _: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, lastAppLaunch: AppGroup.lastAppLaunch))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: .now, lastAppLaunch: AppGroup.lastAppLaunch)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aaru")
                .font(.headline)
            if let launch = entry.lastAppLaunch {
                Text("Opened \(launch, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open Aaru once to start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
