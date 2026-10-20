import AaruAPI
import SwiftUI

/// The iPhone's first screen: invites waiting, then the user's groups.
struct GroupsHome: View {
    let groups: GroupsModel
    let onOpen: (GroupSummary) -> Void
    let onCreate: () -> Void

    var body: some View {
        List {
            if groups.needsHandle {
                HandleNotice()
            }
            InvitesSection(groups: groups, onJoined: onOpen)
            if !groups.groups.isEmpty {
                Section("Groups") {
                    ForEach(groups.groups, id: \.id) { group in
                        Button { onOpen(group) } label: {
                            GroupRow(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .overlay {
            if groups.hasLoaded, groups.groups.isEmpty, groups.invites.isEmpty {
                GroupsEmptyState(canCreate: !groups.needsHandle, onCreate: onCreate)
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New group", systemImage: "plus", action: onCreate).disabled(groups.needsHandle)
            }
        }
        .refreshable { await groups.load() }
    }
}

/// "Make a place to talk with friends."
struct GroupsEmptyState: View {
    let canCreate: Bool
    let onCreate: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No groups yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Make a place to talk with friends.")
        } actions: {
            if canCreate {
                Button("Create a group", action: onCreate).buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Groups need a handle, so friends see who is talking.
struct HandleNotice: View {
    var body: some View {
        Label {
            Text("Choose a handle first, in Settings → Profile and friends.")
        } icon: {
            Image(systemName: "at")
        }
        .foregroundStyle(Color(.muted))
    }
}

struct InvitesSection: View {
    let groups: GroupsModel
    let onJoined: (GroupSummary) -> Void

    var body: some View {
        if !groups.invites.isEmpty {
            Section("Invites") {
                ForEach(groups.invites, id: \.id) { invite in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(invite.groupName).font(.headline)
                        Text("From \(invite.inviter.label)").font(.callout).foregroundStyle(Color(.muted))
                        HStack {
                            Button("Join") {
                                Task {
                                    if let group = await groups.accept(invite) {
                                        onJoined(group)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Decline") { Task { await groups.decline(invite) } }
                                .buttonStyle(.bordered)
                        }
                        .disabled(groups.needsHandle)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// A group on the list: monogram, name, and its unread state.
struct GroupRow: View {
    let group: GroupSummary

    var body: some View {
        HStack(spacing: 12) {
            Monogram(text: group.monogram, size: 44)
            Text(group.name)
                .fontWeight(group.unread > 0 ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 8)
            UnreadBadge(unread: group.unread, mentions: group.mentions)
        }
        .contentShape(.rect)
    }
}

/// A mention count in the accent, else a quiet dot for unread messages.
struct UnreadBadge: View {
    let unread: Int
    let mentions: Int

    var body: some View {
        if mentions > 0 {
            Text("\(mentions)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color(.accent), in: .capsule)
                .accessibilityLabel(mentions == 1 ? "1 mention" : "\(mentions) mentions")
        } else if unread > 0 {
            Circle()
                .fill(Color(.accent))
                .frame(width: 8, height: 8)
                .accessibilityLabel("Unread")
        }
    }
}

/// A text channel on a list: `#name`, bold when unread.
struct ChannelRow: View {
    let channel: GroupChannel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .foregroundStyle(Color(.muted))
                .accessibilityHidden(true)
            Text(channel.name)
                .fontWeight(channel.unread > 0 ? .semibold : .regular)
                .foregroundStyle(channel.unread > 0 ? Color.primary : Color(.muted))
                .lineLimit(1)
            Spacer(minLength: 8)
            UnreadBadge(unread: 0, mentions: channel.mentions)
        }
        .accessibilityLabel("#\(channel.name)")
    }
}

/// The iPhone's second screen: one group's channels and its menu.
struct ChannelListView: View {
    let groups: GroupsModel
    let groupID: String
    let present: (GroupSheet) -> Void
    let confirm: (GroupConfirm) -> Void
    let onOpen: (GroupChannel) -> Void

    private var detail: GroupDetail? {
        groups.details[groupID]
    }

    var body: some View {
        List {
            if let detail {
                Section("Text channels") {
                    ForEach(detail.channels, id: \.id) { channel in
                        Button { onOpen(channel) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                ChannelRow(channel: channel)
                                if let topic = channel.topic {
                                    Text(topic).font(.caption).foregroundStyle(Color(.muted)).lineLimit(1)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if detail.group.role.manages {
                                Button("Edit channel", systemImage: "pencil") {
                                    present(.editChannel(groupID, channel))
                                }
                            }
                        }
                    }
                }
                if detail.members.count == 1 {
                    Section {
                        Button("Invite friends", systemImage: "person.badge.plus") { present(.invite(groupID)) }
                    } footer: {
                        Text("It's just you so far.")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle(detail?.group.name ?? "")
        .toolbar {
            if let group = detail?.group {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Group", systemImage: "ellipsis.circle") {
                        GroupMenuItems(group: group, present: present, confirm: confirm)
                    }
                }
            }
        }
        .refreshable { await groups.loadDetail(groupID) }
        .task { await groups.loadDetail(groupID) }
    }
}
