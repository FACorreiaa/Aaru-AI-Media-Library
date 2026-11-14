import AaruAPI
import SwiftUI

/// Who is in the group, at a glance in the channel header: a few overlapping faces and the count.
/// A tap shows the members (a sheet on iPhone, the inspector on iPad and Mac).
struct MemberStrip: View {
    let members: [GroupMember]
    let onShow: () -> Void

    static let faces = 4
    private static let side: CGFloat = 24

    var body: some View {
        Button(action: onShow) {
            HStack(spacing: 6) {
                HStack(spacing: -Self.side / 3) {
                    ForEach(members.prefix(Self.faces), id: \.user.userId) { member in
                        Monogram(text: member.user.monogram, avatarUrl: member.user.avatarUrl, size: Self.side)
                            .overlay { Circle().stroke(Color(.paper), lineWidth: 1.5) }
                    }
                }
                Text(members.count, format: .number)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(.muted))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(members.count) members"))
        .accessibilityHint("Shows the members")
        .accessibilityAddTraits(.isButton)
    }
}
