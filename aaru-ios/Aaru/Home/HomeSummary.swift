import AaruAPI
import Charts
import SwiftUI

extension LibraryCounts {
    var total: Int {
        wishlist + inProgress + onHold + finished + dropped
    }

    func count(_ status: LibraryStatus) -> Int {
        switch status {
        case .wishlist: wishlist
        case .inProgress: inProgress
        case .onHold: onHold
        case .finished: finished
        case .dropped: dropped
        }
    }
}

/// GAM-006d: the last 7 days at a glance, a bar per day by time, then episodes · hours ·
/// finished · active days. Shown at zero too. Opens Insights on the same window.
struct WeekStrip: View {
    let stats: Stats
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var totals: Components.Schemas.StatsTotals {
        stats.totals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            HStack(spacing: AaruSpace.small) {
                WeekBars(buckets: stats.buckets)
                    .frame(width: 64, height: 24)
                    .accessibilityHidden(true)
                Text("Last 7 days")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.muted))
                    .accessibilityHidden(true)
            }
            // Four across, or two by two at the accessibility sizes so the figures stay whole.
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8, alignment: .leading),
                    count: dynamicType.isAccessibilitySize ? 2 : 4
                ),
                alignment: .leading,
                spacing: AaruSpace.medium
            ) {
                figure(totals.episodesWatched.formatted(), totals.episodesWatched == 1 ? "episode" : "episodes")
                figure(hoursValue(minutes: totals.minutesWatched), "hours")
                figure(totals.finished.formatted(), "finished")
                figure(totals.activeDays.formatted(), totals.activeDays == 1 ? "active day" : "active days")
            }
        }
        .panel()
        .contentShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Insights")
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.aaruDisplay(.title3, weight: .semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(.muted))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Seven bars, one per day, scaled to the busiest by time. An empty day keeps a thin track.
private struct WeekBars: View {
    let buckets: [Components.Schemas.StatsBucket]

    var body: some View {
        let tallest = Double(max(1, buckets.map(\.minutes).max() ?? 0))
        Chart(buckets, id: \.start) { bucket in
            BarMark(
                x: .value("Day", bucket.start),
                y: .value("Time", bucket.minutes == 0 ? 0.06 : max(0.15, Double(bucket.minutes) / tallest))
            )
            .foregroundStyle(bucket.minutes == 0 ? Color(.muted).opacity(AaruAlpha.ghost) : Color(.accent))
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... 1)
    }
}

/// The library by status, in neutral words. A tap opens Library filtered to that status.
struct CountChips: View {
    let counts: LibraryCounts
    let onSelect: (LibraryStatus) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LibraryStatus.allCases) { status in
                    Button { onSelect(status) } label: {
                        HStack(spacing: 6) {
                            Text(status.label(for: nil))
                            Text(counts.count(status).formatted())
                                .foregroundStyle(Color(.muted))
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, AaruSpace.medium)
                        .padding(.vertical, AaruSpace.small)
                        .overlay(Capsule().strokeBorder(Color(.lineStrong)))
                        // The chip stays slim; the tap target is 44pt tall.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows these in Library")
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}

/// `UnfinishedRow` card: a dropped or paused title, with where to pick it up.
struct UnfinishedCard: View {
    let entry: UnfinishedEntry
    /// "Dropped", "Paused 6 weeks".
    let reason: String
    let width: CGFloat

    private var resume: String? {
        entry.next.map { "Resume at \(EpisodeCode.short(season: $0.season, number: $0.number))" }
    }

    var body: some View {
        NavigationLink(value: entry.libraryItemId) {
            VStack(alignment: .leading, spacing: 6) {
                HomeArt(url: entry.title.posterURL, aspect: entry.title.mediaKind.posterAspect)
                    .overlay(alignment: .bottomLeading) {
                        HomeChip(text: reason).padding(6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous))
                Text(entry.title.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let resume {
                    Text(resume)
                        .font(.caption2)
                        .foregroundStyle(Color(.muted))
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
        .accessibilityElement(children: .combine)
    }
}

/// One of the user's lists on Home.
struct ListChip: View {
    let list: ListSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(list.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(list.itemCount.formatted())
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
                .monospacedDigit()
        }
        .padding(.horizontal, AaruSpace.large)
        .padding(.vertical, 10)
        .background(Color(.surface), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
