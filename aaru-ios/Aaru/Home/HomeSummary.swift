import AaruAPI
import SwiftUI

extension LibraryCounts {
    var total: Int {
        wishlist + inProgress + finished + dropped
    }

    func count(_ status: LibraryStatus) -> Int {
        switch status {
        case .wishlist: wishlist
        case .inProgress: inProgress
        case .finished: finished
        case .dropped: dropped
        }
    }
}

/// This month at a glance: episodes · hours · finished · active days. Opens Insights.
struct StatsStrip: View {
    let totals: Components.Schemas.StatsTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This month")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.muted))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                figure(totals.episodesWatched.formatted(), totals.episodesWatched == 1 ? "episode" : "episodes")
                figure(hoursValue(minutes: totals.minutesWatched), "hours")
                figure(totals.finished.formatted(), "finished")
                figure(totals.activeDays.formatted(), totals.activeDays == 1 ? "active day" : "active days")
            }
        }
        .padding(14)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Insights")
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .serif, weight: .semibold))
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

/// The shelf by status, in neutral words. A tap opens Library filtered to that status.
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.18)))
                        .contentShape(Capsule())
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
        entry.next.map { "Resume at S\($0.season) · E\($0.number)" }
    }

    var body: some View {
        NavigationLink(value: entry.libraryItemId) {
            VStack(alignment: .leading, spacing: 6) {
                HomeArt(url: entry.title.posterURL, aspect: 2 / 3)
                    .overlay(alignment: .bottomLeading) {
                        HomeChip(text: reason).padding(6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.surface), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Home before the user has anything in progress: the ways in, above Discover's teaser.
struct HomeIntroCard: View {
    let onBrowse: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a show to see what's next")
                .font(.system(.title3, design: .serif, weight: .semibold))
            Text("Shows you are watching, things to start, and new episodes land here.")
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
            HStack(spacing: 10) {
                Button("Browse Discover", action: onBrowse)
                    .buttonStyle(.borderedProminent)
                Button("Search", action: onSearch)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 14))
    }
}
