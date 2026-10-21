import AaruAPI
import SwiftUI

// The Title room's pieces (`TitleDetailView`): a season's episode list, one episode row, the
// rating stars and the hero's backdrop.

/// One season's episode list, collapsed behind its header. "Mark watched" lives on the season map.
struct SeasonSection: View {
    let season: Components.Schemas.Season
    let model: TitleDetailModel
    @Binding var isExpanded: Bool
    let onOpen: (EpisodeKey) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(season.number == 0 ? "Specials" : "Season \(season.number)")
                        .font(.aaruDisplay(.headline))
                        .foregroundStyle(Color(.ink))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.muted))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                ForEach(season.episodes, id: \.number) { episode in
                    Divider()
                    EpisodeRow(episode: episode, model: model) { onOpen(EpisodeKey(episode)) }
                }
            }
        }
        .panel()
    }
}

/// The tick ticks; the rest of the row opens the episode sheet. Unaired episodes cannot be ticked.
struct EpisodeRow: View {
    let episode: Episode
    let model: TitleDetailModel
    let onOpen: () -> Void

    private var key: EpisodeKey {
        EpisodeKey(episode)
    }

    var body: some View {
        let isWatched = model.watched.contains(key)
        HStack(spacing: 12) {
            Button {
                Task { await model.toggle(key) }
            } label: {
                ZStack {
                    if model.pending.contains(key) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isWatched ? Color(.accent) : Color(.muted))
                    }
                }
                .frame(width: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canToggle(episode))
            .accessibilityLabel("Episode \(episode.number), \(episode.name ?? "")")
            .accessibilityValue(isWatched ? "Watched" : "Not watched")

            Button(action: onOpen) {
                HStack(spacing: 12) {
                    EpisodeStill(url: episode.stillUrl.flatMap(URL.init(string:)), cornerRadius: 4)
                        .frame(width: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(episode.number). \(episode.name ?? "Episode \(episode.number)")")
                            .foregroundStyle(Color(.ink))
                            .lineLimit(2)
                        if let airsAt = episode.airsAt {
                            Text(airDate(airsAt))
                                .font(.caption)
                                .foregroundStyle(Color(.muted))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(episode.name ?? "Episode \(episode.number)") details")
        }
        #if os(iOS)
        .contextMenu {
            if model.hasAired(episode), !isWatched {
                Button("Start watching", systemImage: "play.circle") {
                    Task { await model.startWatching(episode) }
                }
            }
        }
        #endif
    }

    /// Aired: the date. Upcoming: "Airs …", with the time only when the source knows it.
    private func airDate(_ airsAt: Date) -> String {
        if model.hasAired(episode) {
            return airsAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "Airs \(airsAt.formatted(date: .abbreviated, time: episode.airTimeKnown ? .shortened : .omitted))"
    }
}

/// Five stars, each worth two points of the 1–10 scale. Tapping the current value clears it.
struct RatingStars: View {
    let rating: Double?
    let onChange: (Double?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1 ... 5, id: \.self) { star in
                let value = Double(star * 2)
                Button {
                    onChange(rating == value ? nil : value)
                } label: {
                    Image(systemName: (rating ?? 0) >= value ? "star.fill"
                        : (rating ?? 0) >= value - 1 ? "star.leadinghalf.filled" : "star")
                        .foregroundStyle(Color(.gold))
                        .frame(minWidth: 28, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                .accessibilityAddTraits(rating == value ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating.map { "\(Int($0)) of 10" } ?? "Not rated")
    }
}

/// The title's backdrop under a veil that fades into Paper, or, without art, the room's own reed
/// code on Surface.
struct HeroBackdrop: View {
    let url: URL?
    let seed: String

    var body: some View {
        Color(.surface)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ReedCode(seed: seed)
                    }
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, Color(.paper).opacity(0.85)],
                    startPoint: .center, endPoint: .bottom
                )
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
