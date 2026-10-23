import AaruAPI
import SwiftUI

/// GRP-007: how a message in a title channel is marked. By default the server stamps it with
/// where the author is in the title; only the author ever sees that stamp.
enum SpoilerChoice: Hashable {
    case auto
    case free
    case ending
    case upTo(season: Int, episode: Int)

    /// The hand-set stamp the server takes; nil for automatic and spoiler-free.
    var stamp: Components.Schemas.SpoilerStamp? {
        switch self {
        case .auto, .free: nil
        case .ending: .init(ending: true)
        case let .upTo(season, episode): .init(season: season, episode: episode)
        }
    }

    var label: String {
        switch self {
        case .auto: "At your progress"
        case .free: "No spoilers"
        case .ending: "Spoils the ending"
        case let .upTo(season, episode): "Up to \(EpisodeCode.text(season: season, episode: episode))"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "eye.slash"
        case .free: "checkmark.shield"
        case .ending: "flag.checkered"
        case .upTo: "list.number"
        }
    }
}

extension Components.Schemas.SpoilerStamp {
    /// "Up to S1E3" or "Spoils the ending", for the author's own messages.
    var label: String? {
        if ending == true {
            return "Spoils the ending"
        }
        guard let season, let episode else { return nil }
        return "Up to \(EpisodeCode.text(season: season, episode: episode))"
    }
}

/// The composer's spoiler menu, for title channels.
struct SpoilerMenu: View {
    @Binding var choice: SpoilerChoice
    @State private var picksEpisode = false
    @State private var season = 1
    @State private var episode = 1

    var body: some View {
        Menu {
            Picker("Spoilers", selection: simpleChoice) {
                Label(SpoilerChoice.auto.label, systemImage: SpoilerChoice.auto.symbol).tag(SpoilerChoice.auto)
                Label(SpoilerChoice.ending.label, systemImage: SpoilerChoice.ending.symbol)
                    .tag(SpoilerChoice.ending)
                Label(SpoilerChoice.free.label, systemImage: SpoilerChoice.free.symbol).tag(SpoilerChoice.free)
            }
            Button("Up to an episode…", systemImage: SpoilerChoice.upTo(season: 1, episode: 1).symbol) {
                if case let .upTo(season, episode) = choice {
                    self.season = season
                    self.episode = episode
                }
                picksEpisode = true
            }
        } label: {
            Label(choice.label, systemImage: choice.symbol)
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(choice == .auto ? Color(.muted) : Color(.accent))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityHint("Who sees this veiled until they catch up.")
        .sheet(isPresented: $picksEpisode) {
            NavigationStack {
                Form {
                    Section {
                        Stepper("Season \(season)", value: $season, in: 0 ... 99)
                        Stepper("Episode \(episode)", value: $episode, in: 1 ... 999)
                    } footer: {
                        Text("Anyone who hasn't watched up to this episode sees it veiled until they tap it.")
                    }
                }
                .paperPage()
                .navigationTitle("Spoils up to")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picksEpisode = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            choice = .upTo(season: season, episode: episode)
                            picksEpisode = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    /// The menu's picker covers the three fixed choices; an episode stamp shows none ticked.
    private var simpleChoice: Binding<SpoilerChoice> {
        Binding(get: { choice }, set: { choice = $0 })
    }
}

/// A veiled message: tap to read it. The reveal is local and lasts while the row is on screen.
struct SpoilerVeil: View {
    let onReveal: () -> Void

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                Text("May spoil what you haven't watched yet")
                Text("Show").fontWeight(.semibold).foregroundStyle(Color(.accent))
            }
            .font(.callout)
            .foregroundStyle(Color(.muted))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color(.muted).opacity(AaruAlpha.tint),
                in: RoundedRectangle(cornerRadius: AaruRadius.row, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spoiler hidden. Show it.")
    }
}
