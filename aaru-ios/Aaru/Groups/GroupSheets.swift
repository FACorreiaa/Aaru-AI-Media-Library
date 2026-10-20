import AaruAPI
import SwiftUI

/// Sheets the groups screens open, shared by the iPhone stack and the iPad/Mac split view.
enum GroupSheet: Identifiable {
    case create
    case rename(String)
    case invite(String)
    case members(String)
    case newChannel(String)
    case editChannel(String, GroupChannel)

    var id: String {
        switch self {
        case .create: "create"
        case let .rename(group): "rename-\(group)"
        case let .invite(group): "invite-\(group)"
        case let .members(group): "members-\(group)"
        case let .newChannel(group): "channel-\(group)"
        case let .editChannel(_, channel): "edit-\(channel.id)"
        }
    }
}

enum GroupConfirm: Identifiable {
    case leave(GroupSummary)
    case delete(GroupSummary)

    var id: String {
        switch self {
        case let .leave(group): "leave-\(group.id)"
        case let .delete(group): "delete-\(group.id)"
        }
    }
}

/// Attaches the groups sheets and the leave/delete confirmations.
struct GroupPresentation: ViewModifier {
    let groups: GroupsModel
    @Binding var sheet: GroupSheet?
    @Binding var confirm: GroupConfirm?
    /// A new group opens on its first channel.
    let onCreated: (GroupDetail) -> Void
    let onChannelCreated: (String, GroupChannel) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { sheet in sheetContent(sheet) }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(get: { confirm != nil }, set: {
                    if !$0 {
                        confirm = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: confirm
            ) { confirm in
                switch confirm {
                case let .leave(group):
                    Button("Leave", role: .destructive) { Task { await groups.leave(group.id) } }
                case let .delete(group):
                    Button("Delete group", role: .destructive) { Task { await groups.delete(group.id) } }
                }
            } message: { confirm in
                switch confirm {
                case .leave: Text("You stop seeing its channels. A friend in it can invite you back.")
                case .delete: Text("Every channel and message goes, for everyone. This can't be undone.")
                }
            }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: GroupSheet) -> some View {
        switch sheet {
        case .create:
            GroupNameSheet(title: "New group", initial: "") { name in
                guard let detail = await groups.create(named: name) else { return false }
                onCreated(detail)
                return true
            }
        case let .rename(groupID):
            GroupNameSheet(title: "Rename group", initial: groups.details[groupID]?.group.name ?? "") { name in
                await groups.rename(groupID, to: name)
            }
        case let .invite(groupID):
            InviteFriendsSheet(groups: groups, groupID: groupID)
        case let .members(groupID):
            NavigationStack {
                MemberList(groups: groups, groupID: groupID) { self.sheet = .invite(groupID) }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { self.sheet = nil }
                        }
                    }
            }
        case let .newChannel(groupID):
            NewChannelSheet(groups: groups, groupID: groupID) { channel in
                onChannelCreated(groupID, channel)
            }
        case let .editChannel(groupID, channel):
            ChannelEditorSheet(groups: groups, groupID: groupID, channel: channel)
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case let .leave(group): "Leave \(group.name)?"
        case let .delete(group): "Delete \(group.name)?"
        case nil: ""
        }
    }
}

/// The group's actions, for a toolbar menu or a context menu.
struct GroupMenuItems: View {
    let group: GroupSummary
    let present: (GroupSheet) -> Void
    let confirm: (GroupConfirm) -> Void

    var body: some View {
        Button("Invite friends", systemImage: "person.badge.plus") { present(.invite(group.id)) }
        Button("Members", systemImage: "person.2") { present(.members(group.id)) }
        if group.role.manages {
            Button("New channel", systemImage: "plus.bubble") { present(.newChannel(group.id)) }
            Button("Rename group", systemImage: "pencil") { present(.rename(group.id)) }
        }
        Divider()
        if group.role == .owner {
            Button("Delete group", systemImage: "trash", role: .destructive) { confirm(.delete(group)) }
        } else {
            Button("Leave group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirm(.leave(group))
            }
        }
    }
}

/// A group's name: create or rename.
private struct GroupNameSheet: View {
    let title: String
    let initial: String
    /// True when saved; the sheet then closes.
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .onSubmit(save)
                } footer: {
                    Text("Only friends you invite can find it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(saving || trimmed.isEmpty || trimmed.count > 50)
                }
            }
        }
        .onAppear {
            name = initial
            focused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty, trimmed.count <= 50 else { return }
        Task {
            saving = true
            if await onSave(trimmed) {
                dismiss()
            }
            saving = false
        }
    }
}

/// A channel's name and topic. The server lowercases the name and turns spaces into dashes.
private struct ChannelEditorSheet: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var topic = ""
    @State private var saving = false
    @State private var confirmsDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("#").foregroundStyle(Color(.muted))
                        TextField("movie-night", text: $name)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    }
                    TextField("Topic (optional)", text: $topic, axis: .vertical)
                        .lineLimit(1 ... 3)
                } footer: {
                    Text("Lowercase, with dashes for spaces.")
                }
                if let problem = groups.problem {
                    Text(problem).foregroundStyle(.red)
                }
                if !channel.isDefault {
                    Section {
                        Button("Delete channel", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete #\(channel.name)?", isPresented: $confirmsDelete) {
                Button("Delete channel", role: .destructive) {
                    Task {
                        if await groups.deleteChannel(channel, in: groupID) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Every message in it goes, for everyone.")
            }
        }
        .onAppear {
            groups.problem = nil
            name = channel.name
            topic = channel.topic ?? ""
        }
    }

    private func save() {
        Task {
            saving = true
            defer { saving = false }
            if await groups.updateChannel(channel, in: groupID, name: name, topic: topic) {
                dismiss()
            }
        }
    }
}

/// Friends only: a group is reachable no other way.
private struct InviteFriendsSheet: View {
    let groups: GroupsModel
    let groupID: String
    @Environment(\.dismiss) private var dismiss

    private var detail: GroupDetail? {
        groups.details[groupID]
    }

    var body: some View {
        NavigationStack {
            List {
                if groups.friends.isEmpty {
                    Text("No friends yet. Add them in Settings → Profile and friends.")
                        .foregroundStyle(Color(.muted))
                }
                ForEach(groups.friends, id: \.userId) { friend in
                    HStack(spacing: 12) {
                        Monogram(text: friend.monogram)
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
