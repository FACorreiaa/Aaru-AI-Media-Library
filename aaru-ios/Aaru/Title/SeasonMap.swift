import AaruAPI
import SwiftUI

/// A4: the centre of the Title room. One heat grid per season, one cell per episode; a tap
/// corrects one episode, "Mark watched" paints the season. Every write goes through the model.
struct SeasonMap: View {
    let model: TitleDetailModel
    let onOpen: (EpisodeKey) -> Void

    var body: some View {
        Section("Season map") {
            ForEach(model.orderedSeasons, id: \.number) { season in
                SeasonMapRow(season: season, next: model.nextEpisode, model: model, onOpen: onOpen)
            }
        }
    }
}

private struct SeasonMapRow: View {
    let season: Components.Schemas.Season
    let next: EpisodeKey?
    let model: TitleDetailModel
    let onOpen: (EpisodeKey) -> Void

    private let columns = [GridItem(.adaptive(minimum: 28, maximum: 40), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(season.number == 0 ? "Specials" : "Season \(season.number)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.ink))
                let watched = season.episodes.count { model.watched.contains(EpisodeKey($0)) }
                Text("\(watched) of \(season.episodes.count)")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .contentTransition(.numericText())
                Spacer()
                if season.number > 0, !model.airedEpisodes(in: season.number).isSubset(of: model.watched) {
                    Button("Mark watched") { Task { await model.markSeasonWatched(season.number) } }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(season.episodes, id: \.number) { episode in
                    SeasonMapCell(episode: episode, state: state(of: episode), model: model, onOpen: onOpen)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func state(of episode: Episode) -> SeasonMapCell.Heat {
        let key = EpisodeKey(episode)
        if model.watched.contains(key) {
            return .watched
        }
        if key == next {
            return .next
        }
        return model.hasAired(episode) ? .aired : .unaired
    }
}

private struct SeasonMapCell: View {
    enum Heat {
        case watched, next, aired, unaired

        var label: String {
            switch self {
            case .watched: "watched"
            case .next: "up next"
            case .aired: "not watched"
            case .unaired: "not aired yet"
            }
        }
    }

    let episode: Episode
    let state: Heat
    let model: TitleDetailModel
    let onOpen: (EpisodeKey) -> Void

    private var key: EpisodeKey {
        EpisodeKey(episode)
    }

    var body: some View {
        Button {
            Task { await model.toggle(key) }
        } label: {
            Text(episode.number, format: .number.grouping(.never))
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(fill, in: shape)
                .overlay { border }
                .opacity(model.pending.contains(key) ? 0.5 : 1)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!model.canToggle(episode))
        .contextMenu {
            Button("Episode details", systemImage: "info.circle") { onOpen(key) }
        }
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Episode details") { onOpen(key) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6)
    }

    private var fill: Color {
        switch state {
        case .watched: .accentColor
        case .next: .accentColor.opacity(0.15)
        case .aired: Color(.muted).opacity(0.15)
        case .unaired: .clear
        }
    }

    private var foreground: Color {
        switch state {
        case .watched: .white
        case .next: .accentColor
        case .aired: Color(.ink)
        case .unaired: Color(.muted).opacity(0.6)
        }
    }

    @ViewBuilder private var border: some View {
        switch state {
        case .next: shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
        case .unaired: shape.strokeBorder(Color(.muted).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .watched, .aired: EmptyView()
        }
    }

    private var accessibilityText: String {
        let season = episode.season == 0 ? "Specials" : "Season \(episode.season)"
        return [season, "episode \(episode.number)", episode.name, state.label]
            .compactMap(\.self).joined(separator: ", ")
    }
}
