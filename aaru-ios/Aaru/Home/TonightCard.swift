import AaruAPI
import SwiftUI

typealias TonightVerdict = Components.Schemas.TonightFeedback.VerdictPayload

/// The Field's focal card (VIEWS.md `TonightStrip`): the one thing to watch now, over its
/// backdrop, with why it is here and the next step. "Also tonight" names one more under it.
/// Either can be set aside: "Not tonight" for today, "Not for me" for longer (AG-005).
struct TonightCard: View {
    let tonight: Tonight
    let isPending: Bool
    /// Side by side on wide screens: the art, then the words and actions beside it.
    var wide = false
    var onSetAside: (TonightPick, TonightVerdict) -> Void = { _, _ in }
    var onMarkSeasonWatched: (ContinueEntry) -> Void = { _ in }
    let onMarkWatched: (ContinueEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight").eyebrow()
                .accessibilityAddTraits(.isHeader)
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 0) {
                        art.frame(maxWidth: .infinity)
                        details.frame(width: 320, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        art
                        details
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.surface))
            .clipShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
            .edgeLit()
            if let also = tonight.also {
                NavigationLink(value: also.libraryItemId) {
                    HStack(spacing: 4) {
                        Text("Also tonight").foregroundStyle(Color(.muted))
                        Text(also.title.title).foregroundStyle(Color(.accent))
                        if !also.episodeLine.isEmpty {
                            Text("· \(also.episodeLine)").foregroundStyle(Color(.muted))
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .contextMenu { setAsideButtons(also) }
            }
        }
    }

    private var art: some View {
        NavigationLink(value: tonight.primary.libraryItemId) {
            HomeArt(url: artURL, aspect: 16 / 9)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contextMenu { setAsideButtons(tonight.primary) }
        .accessibilityLabel("Open \(tonight.primary.title.title)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tonight.primary.title.title)
                .font(.aaruDisplay(wide ? .title : .title2))
                .foregroundStyle(Color(.ink))
                .lineLimit(2)
            if !tonight.primary.episodeLine.isEmpty {
                Text(tonight.primary.episodeLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(tonight.primary.reason)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
            actions.padding(.top, 8)
        }
        .padding(wide ? 24 : 16)
    }

    /// The full phrasing on one row where it fits, then the ticks drop to the bare code. On a
    /// narrow iPhone with the season tick too, Open and More move to a second row, and at the
    /// largest text sizes each tick takes its own row. A label never wraps inside its button.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ticks(short: false)
                navigation
            }
            HStack(spacing: 12) {
                ticks(short: true)
                navigation
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) { ticks(short: true) }
                HStack(spacing: 12) { navigation }
            }
            VStack(alignment: .leading, spacing: 12) {
                ticks(short: true)
                HStack(spacing: 12) { navigation }
            }
        }
        .lineLimit(1)
        .controlSize(.large)
    }

    @ViewBuilder private func ticks(short: Bool) -> some View {
        if let entry = tonight.primary.markable {
            let code = EpisodeCode.short(season: entry.next.season, number: entry.next.number)
            Button {
                onMarkWatched(entry)
            } label: {
                // One phrasing for the tick wherever the episode is named (UX-044).
                Label(short ? code : "Mark \(code) watched", systemImage: "checkmark")
                    .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(isPending)
            .accessibilityLabel("Mark \(entry.title.title) \(code) watched")
        }
        if let entry = tonight.primary.seasonMarkable {
            Button {
                onMarkSeasonWatched(entry)
            } label: {
                Label(
                    short ? "Season \(entry.next.season)" : "Season \(entry.next.season) watched",
                    systemImage: "checkmark.circle"
                )
                .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(isPending)
            .accessibilityLabel("Mark \(entry.title.title) season \(entry.next.season) watched")
        }
    }

    @ViewBuilder private var navigation: some View {
        NavigationLink(value: tonight.primary.libraryItemId) {
            Text("Open").frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .fixedSize()
        Menu {
            setAsideButtons(tonight.primary)
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .accessibilityLabel("Set \(tonight.primary.title.title) aside")
    }

    @ViewBuilder private func setAsideButtons(_ pick: TonightPick) -> some View {
        Button {
            onSetAside(pick, .notTonight)
        } label: {
            Label("Not tonight", systemImage: "moon.zzz")
        }
        Button {
            onSetAside(pick, .rejected)
        } label: {
            Label("Not for me", systemImage: "hand.thumbsdown")
        }
    }

    private var artURL: URL? {
        (tonight.primary.title.backdropUrl ?? tonight.primary.title.posterUrl).flatMap(URL.init(string:))
    }
}

// MARK: Previews

#Preview("Tonight") {
    if let tonight = HomeModel.sample.tonight {
        NavigationStack {
            TonightCard(tonight: tonight, isPending: false) { _ in }
                .padding(20)
        }
    }
}

#Preview("Tonight, narrow iPhone · dark", traits: .fixedLayout(width: 375, height: 640)) {
    if let tonight = HomeModel.sample.tonight {
        NavigationStack {
            TonightCard(tonight: tonight, isPending: false) { _ in }
                .padding(16)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Tonight, wide · dark", traits: .fixedLayout(width: 900, height: 420)) {
    if let tonight = HomeModel.sample.tonight {
        NavigationStack {
            TonightCard(tonight: tonight, isPending: false, wide: true) { _ in }
                .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}
