import SwiftUI

/// One airing up close (CAL-003): the still, the poster, when and where, the synopsis, the tick
/// and the way to the show. Medium and large detents on iPhone; a sheet on Mac and iPad.
struct CalendarEpisodeSheet: View {
    let feed: CalendarFeed
    /// Pushes the show on the calendar's own navigation stack.
    var onOpenShow: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let entry = feed.opened {
                    content(entry)
                }
            }
            .background(Color(.paper))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    // A way out on every platform; the Mac has no swipe down (UX-069).
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func content(_ entry: CalendarEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                still(entry)
                header(entry)
                Text(when(entry))
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                if let overview = entry.episodeOverview {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(Color(.ink))
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions(entry)
            }
            .padding(20)
        }
    }

    private func header(_ entry: CalendarEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PosterView(
                url: entry.title.posterUrl.flatMap(URL.init(string:)),
                kind: entry.title.isAnime ? .anime : .show
            )
            .frame(width: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4, y: 2)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.title.title) · \(entry.shortCode)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(.muted))
                Text(entry.episodeName ?? "Episode \(entry.number)")
                    .font(.aaruDisplay(.title2, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
                if let badge = entry.badge {
                    WeekBadge(badge: badge)
                }
            }
        }
    }

    private func actions(_ entry: CalendarEntry) -> some View {
        // Side by side; stacked at accessibility sizes so neither label is cut.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons(entry) }
            VStack(alignment: .leading, spacing: 10) { actionButtons(entry) }
        }
    }

    @ViewBuilder private func actionButtons(_ entry: CalendarEntry) -> some View {
        Button {
            Task { await feed.toggle(entry) }
        } label: {
            Label(
                entry.watched ? "Watched" : aired(entry) ? "Mark watched" : "Not aired yet",
                systemImage: entry.watched ? "checkmark.circle.fill" : "circle"
            )
            .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .tint(entry.watched ? Color(.accent) : Color(.ink).opacity(0.75))
        .disabled(feed.pending.contains(entry.cellID) || (!aired(entry) && !entry.watched))
        Button {
            dismiss()
            onOpenShow(entry.libraryItemId)
        } label: {
            Label("Open show", systemImage: "info.circle").frame(minHeight: 30)
        }
        .buttonStyle(.bordered)
    }

    private func still(_ entry: CalendarEntry) -> some View {
        Color(.surface)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: (entry.stillUrl ?? entry.title.backdropUrl).flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color(.accent).opacity(0.15)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    private func aired(_ entry: CalendarEntry) -> Bool {
        entry.airsAt <= .now
    }

    /// "Airs Thursday 15 October, 9:00 PM on Netflix · 50 min".
    private func when(_ entry: CalendarEntry) -> String {
        let date = entry.airTimeKnown
            ? entry.airsAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
            : entry.airsAt.formatted(
                Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.wide)
            )
        var text = (aired(entry) ? "" : "Airs ") + date
        if let network = entry.title.network {
            text += " on \(network)"
        }
        if let minutes = entry.runtimeMinutes {
            text += " · \(minutes) min"
        }
        return text
    }
}
