import SwiftUI

/// Friends only: a group is reachable no other way.
struct InviteFriendsSheet: View {
    let groups: GroupsModel
    let groupID: String
    /// No friends to invite: closes the sheet and opens Settings → Friends & privacy (UX-074).
    let onAddFriends: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var detail: GroupDetail? {
        groups.details[groupID]
    }

    var body: some View {
        NavigationStack {
            List {
                if groups.friends.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No friends yet. A group is open only to friends you invite.")
                            .foregroundStyle(Color(.muted))
                        Button("Add friends", action: onAddFriends)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(groups.friends, id: \.userId) { friend in
                    HStack(spacing: 12) {
                        Monogram(text: friend.monogram, avatarUrl: friend.avatarUrl)
                        Text(friend.label).lineLimit(1)
                        Spacer(minLength: 8)
                        if detail?.members.contains(where: { $0.user.userId == friend.userId }) == true {
                            Text("In group").foregroundStyle(Color(.muted))
                        } else if detail?.invited.contains(where: { $0.userId == friend.userId }) == true {
                            Text("Invited").foregroundStyle(Color(.muted))
                        } else {
                            Button("Invite") { Task { await groups.invite(friend, to: groupID) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .navigationTitle("Invite friends")
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: groups.problem) { groups.problem = nil } }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                await groups.loadFriends()
                await groups.loadDetail(groupID)
            }
        }
    }
}
