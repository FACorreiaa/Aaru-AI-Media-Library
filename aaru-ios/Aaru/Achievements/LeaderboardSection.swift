import AaruAPI
import SwiftUI

/// Friends' "This week" (GAM-005, DESIGN.md §17): you and the friends who joined, ranked by this
/// week's points, your row marked. Before you join, one card explains it and offers to. Friends
/// only, opt-in, never global, never all-time.
struct LeaderboardSection: View {
    let board: FriendsBoard?
    let joining: Bool
    let onJoin: () -> Void

    var body: some View {
        if let board {
            Section {
                if board.optedIn {
                    ForEach(board.entries, id: \.user.userId) { entry in
                        BoardRow(entry: entry)
                    }
                    if board.entries.count <= 1 {
                        Text("Only you so far. Friends appear once they join the board too.")
                            .font(.footnote)
                            .foregroundStyle(Color(.muted))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A weekly board, just for friends")
                            .font(.aaruDisplay(.title3))
                        Text(
                            "Join to see this week's points next to friends who joined too. It starts over every "
                                + "Monday, and nobody outside your friends ever sees it."
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                        Button(action: onJoin) {
                            Text("Join the board").frame(minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(.ink))
                        .disabled(joining)
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("This week")
            }
        }
    }
}

private struct BoardRow: View {
    let entry: Components.Schemas.LeaderboardEntry
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
                .frame(minWidth: 20, alignment: .trailing)
            Text(entry.user.monogram)
                .font(.footnote.weight(.medium))
                .frame(width: side, height: side)
                .background(Color(.medallion).opacity(0.2), in: .circle)
                .accessibilityHidden(true)
            Text(entry.you ? "You" : entry.user.inviteName)
                .fontWeight(entry.you ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(entry.points.formatted())
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .listRowBackground(entry.you ? Color(.accent).opacity(0.08) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.rank), \(entry.you ? "You" : entry.user.inviteName), \(entry.points) points")
    }
}
