import SwiftUI

/// An iPhone month day, tapped: what airs that day, one row each (CAL-003).
struct DaySheet: View {
    let day: Date
    let feed: CalendarFeed

    var body: some View {
        let entries = feed.entries(on: day)
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries, id: \.cellID) { entry in
                        CalendarEpisodeRow(entry: entry, feed: feed)
                        Divider().padding(.leading, 66)
                    }
                    if entries.isEmpty {
                        Text("Nothing from your shows airs this day.")
                            .font(.callout)
                            .foregroundStyle(Color(.muted))
                            .padding(24)
                    }
                }
            }
            .background(Color(.paper))
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
