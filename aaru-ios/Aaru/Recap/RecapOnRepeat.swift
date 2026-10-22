import SwiftUI

/// MUS-008: the top artist large, its plays and time, then its three most played tracks.
struct OnRepeatCard: View {
    let artist: String
    let plays: Int
    let minutes: Int
    let tracks: [String]

    var body: some View {
        Eyebrow(text: "On repeat")
        Text(artist)
            .font(.aaruDisplay(size: 56))
            .lineLimit(2)
            .padding(.top, 16)
            .rise(0.12)
        Text(minutes > 0 ? "\(Listening.plays(plays)) · \(hoursValue(minutes: minutes)) hours" : Listening.plays(plays))
            .font(.title3)
            .padding(.top, 8)
            .rise(0.2)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { rank, track in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("\(rank + 1)")
                        .font(.aaruDisplay(.title2))
                        .monospacedDigit()
                        .opacity(0.7)
                        .frame(width: 24, alignment: .leading)
                    Text(track)
                        .font(.aaruDisplay(.title))
                        .lineLimit(1)
                }
                .rise(0.36 + Double(rank) * 0.16)
            }
        }
        .padding(.top, 24)
    }
}
