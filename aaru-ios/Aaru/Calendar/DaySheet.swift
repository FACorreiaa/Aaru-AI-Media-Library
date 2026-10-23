import SwiftUI

/// An iPhone month day, tapped: what airs that day, one row each (CAL-003). A row opens the
/// episode sheet from here, over this sheet, so the tap is never lost under it (UX-068).
struct DaySheet: View {
    let day: Date
    let feed: CalendarFeed
    /// "Open show": this sheet closes and the calendar pushes the show.
    var onOpenShow: (String) -> Void

    var body: some View {
        @Bindable var feed = feed
        let entries = feed.entries(on: day)
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries, id: \.cellID) { entry in
                        CalendarEpisodeRow(entry: entry, feed: feed)
                        // Inset past the row's poster: its leading padding, 40 pt of art, the gap.
                        Divider().padding(.leading, AaruSpace.page + AaruSpace.xlarge)
                    }
                    if entries.isEmpty {
                        Text(feed.filter.isActive
                            ? "No episodes match these filters this day."
                            : "Nothing from your shows airs this day.")
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
        .sheet(isPresented: $feed.openedID.isPresent) {
            CalendarEpisodeSheet(feed: feed, onOpenShow: onOpenShow)
        }
        .onAppear { feed.isDaySheetOpen = true }
        .onDisappear { feed.isDaySheetOpen = false }
    }
}
