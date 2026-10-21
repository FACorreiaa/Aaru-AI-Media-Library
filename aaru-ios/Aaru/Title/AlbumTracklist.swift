import AaruAPI
import SwiftUI

typealias AlbumTrack = Components.Schemas.AlbumTrack

/// The tracklist as plain list sections: number, name, length. "Disc 1"… headers only when the
/// release has more than one disc. No playback and no ticks: an album has a status, not progress.
struct AlbumTracklist: View {
    /// Nil until the server has fetched the tracklist from MusicBrainz.
    let tracks: [AlbumTrack]?
    /// The title is still loading: placeholders at the rows' real size, still.
    let isLoading: Bool

    private var discs: [(number: Int, tracks: [AlbumTrack])] {
        Dictionary(grouping: tracks ?? [], by: \.disc)
            .map { (number: $0.key, tracks: $0.value.sorted { $0.position < $1.position }) }
            .sorted { $0.number < $1.number }
    }

    var body: some View {
        if let tracks, !tracks.isEmpty {
            let discs = discs
            ForEach(discs, id: \.number) { disc in
                Section {
                    ForEach(disc.tracks, id: \.self) { TrackRow(track: $0) }
                } header: {
                    if discs.count > 1 {
                        Text("Disc \(disc.number)")
                    }
                } footer: {
                    if disc.number == discs.last?.number {
                        Text(Self.summary(tracks))
                    }
                }
            }
        } else if isLoading {
            Section {
                ForEach(Self.placeholders, id: \.position) { TrackRow(track: $0) }
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        } else {
            Section {
                Text("Tracklist not available yet")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
    }

    /// "12 tracks, 53 minutes"; just the count when a length is missing.
    static func summary(_ tracks: [AlbumTrack]) -> String {
        let count = tracks.count == 1 ? "1 track" : "\(tracks.count) tracks"
        let lengths = tracks.compactMap(\.lengthMs)
        guard lengths.count == tracks.count else { return count }
        let minutes = Int((Double(lengths.reduce(0, +)) / 60000).rounded())
        return "\(count), \(minutes == 1 ? "1 minute" : "\(minutes) minutes")"
    }

    private static let placeholders = (1 ... 8).map {
        AlbumTrack(disc: 1, position: $0, name: "Track name here", lengthMs: 240_000)
    }
}

/// One track: its number (secondary, monospaced digits), name and length (m:ss).
private struct TrackRow: View {
    let track: AlbumTrack
    @ScaledMetric(relativeTo: .body) private var numberWidth = 24

    private var length: Duration? {
        track.lengthMs.map { .milliseconds($0) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(track.position, format: .number.grouping(.never))
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
                .frame(minWidth: numberWidth, alignment: .trailing)
            Text(track.name)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let length {
                Text(length, format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let duration = length?.formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return ["Track \(track.position)", track.name, duration].compactMap(\.self).joined(separator: ", ")
    }
}

#Preview("Tracklist loading") {
    Form { AlbumTracklist(tracks: nil, isLoading: true) }
        .formStyle(.grouped)
}
