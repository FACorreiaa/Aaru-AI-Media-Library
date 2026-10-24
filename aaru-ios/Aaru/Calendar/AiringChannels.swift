import SwiftUI

/// CAL-005, "Group by: Channel": a section per channel or streamer, its header pinned while its
/// rows scroll, each row with the day and time where the network would be. Goes inside a
/// `LazyVStack` with `pinnedViews: [.sectionHeaders]`; the agenda and the wide week use it.
struct AiringChannelSections: View {
    let groups: [AiringChannel]
    let feed: CalendarFeed

    var body: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.entries, id: \.cellID) { entry in
                    CalendarEpisodeRow(entry: entry, feed: feed, detail: entry.dayAndTime)
                }
            } header: {
                AiringChannelHeader(group: group)
            }
        }
    }
}

/// "Netflix  3", in the agenda's heading style.
struct AiringChannelHeader: View {
    let group: AiringChannel
    /// The rows' own inset; the iPhone day pager's cards are already inset.
    var inset: CGFloat = AaruSpace.large

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(group.channel)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.accent))
            Text(group.entries.count, format: .number)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
        }
        .padding(.horizontal, inset)
        .padding(.top, AaruSpace.large)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.paper))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.channel), \(episodes)")
        .accessibilityAddTraits(.isHeader)
    }

    private var episodes: String {
        group.entries.count == 1 ? "1 episode" : "\(group.entries.count) episodes"
    }
}

/// Mac and iPad, Week grouped by channel: the seven days' episodes as channel sections, in
/// place of the day columns.
struct WeekAiringChannels: View {
    let model: WeekModel

    var body: some View {
        let groups = AiringChannel.group(model.days.flatMap(model.entries(on:)))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                AiringChannelSections(groups: groups, feed: model.feed)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
    }
}
