import SwiftUI

/// Home's invitation to the recap of the moment: the year from Dec 1 to Jan 15, last month in
/// the first week of a month (`RecapPeriod.offered`).
struct RecapBanner: View {
    let period: RecapPeriod
    var onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your recap is ready")
                        .font(.subheadline)
                        .opacity(0.8)
                    Text(period.month == nil ? "\(period.year) in Aaru" : period.label)
                        .font(.aaruDisplay(.title2))
                }
                Spacer(minLength: 0)
                Text("Play")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.paper), in: Capsule())
                    .foregroundStyle(Color(.ink))
            }
            .padding(20)
            .foregroundStyle(Color(.paper))
            .background(Color(.ink), in: RoundedRectangle(cornerRadius: AaruRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Plays your recap as a story")
    }
}
