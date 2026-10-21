import SwiftUI

/// The Field's focal card (VIEWS.md `TonightStrip`): the one thing to watch now, over its
/// backdrop, with why it is here and the next step. "Also tonight" names one more under it.
struct TonightCard: View {
    let tonight: Tonight
    let isPending: Bool
    /// Side by side on wide screens: the art, then the words and actions beside it.
    var wide = false
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
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .edgeLit()
            if let also = tonight.also {
                NavigationLink(value: also.libraryItemId) {
                    HStack(spacing: 4) {
                        Text("Also tonight").foregroundStyle(Color(.muted))
                        Text(also.title.title).foregroundStyle(Color(.accent))
                        Text("· \(also.episodeLine)").foregroundStyle(Color(.muted))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var art: some View {
        NavigationLink(value: tonight.primary.libraryItemId) {
            HomeArt(url: artURL, aspect: 16 / 9)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(tonight.primary.title.title)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tonight.primary.title.title)
                .font(.aaruDisplay(wide ? .title : .title2))
                .foregroundStyle(Color(.ink))
                .lineLimit(2)
            Text(tonight.primary.episodeLine)
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(1)
            Text(tonight.primary.reason)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
            actions.padding(.top, 8)
        }
        .padding(wide ? 24 : 16)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if case let .continuing(entry) = tonight.primary {
                Button {
                    onMarkWatched(entry)
                } label: {
                    Label("Mark watched", systemImage: "checkmark")
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPending)
                .accessibilityLabel("Mark \(entry.title.title) \(tonight.primary.episodeLine) watched")
            }
            NavigationLink(value: tonight.primary.libraryItemId) {
                Text("Open").frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var artURL: URL? {
        (tonight.primary.title.backdropUrl ?? tonight.primary.title.posterUrl).flatMap(URL.init(string:))
    }
}
