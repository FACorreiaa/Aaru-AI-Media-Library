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
    /// The owner asked to leave: they must hand the group on first (UX-084).
    case ownerLeave(GroupSummary)
    case delete(GroupSummary)

    var id: String {
        switch self {
        case let .leave(group): "leave-\(group.id)"
        case let .ownerLeave(group): "owner-leave-\(group.id)"
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
    /// Members: a sheet on iPhone, the inspector in the split.
    let onShowMembers: (String) -> Void

    @Environment(AppRouter.self) private var router
    /// A Settings page to open once the sheet in the way has closed.
    @State private var settingsAfterSheet: SettingsPage?

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet, onDismiss: openPendingSettings) { sheet in sheetContent(sheet) }
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
                case let .ownerLeave(group):
                    Button("Open Members") { onShowMembers(group.id) }
                case let .delete(group):
                    Button("Delete group", role: .destructive) { Task { await groups.delete(group.id) } }
                }
            } message: { confirm in
                switch confirm {
                case .leave: Text("You stop seeing its channels. A friend in it can invite you back.")
                case .ownerLeave:
                    Text("Make someone else owner first, in Members. Then you can leave, or delete the group instead.")
                case .delete: Text("Every channel and group message goes, for everyone. This can't be undone.")
                }
            }
    }

    private func openPendingSettings() {
        guard let page = settingsAfterSheet else { return }
        settingsAfterSheet = nil
        router.openSettings(page)
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
            InviteFriendsSheet(groups: groups, groupID: groupID) {
                settingsAfterSheet = .friends
                self.sheet = nil
            }
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
        case let .leave(group), let .ownerLeave(group): "Leave \(group.name)?"
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
    @Environment(GroupsModel.self) private var groups: GroupsModel?

    var body: some View {
        Button("Invite friends", systemImage: "person.badge.plus") { present(.invite(group.id)) }
        Button("Members", systemImage: "person.2") { present(.members(group.id)) }
        if group.role.manages {
            Button("New channel", systemImage: "plus.bubble") { present(.newChannel(group.id)) }
            Button("Rename group", systemImage: "pencil") { present(.rename(group.id)) }
        }
        if group.muted {
            Button("Unmute mentions", systemImage: "bell") { Task { await groups?.setMuted(group.id, false) } }
        } else {
            Button("Mute mentions", systemImage: "bell.slash") { Task { await groups?.setMuted(group.id, true) } }
        }
        Divider()
        if group.role == .owner {
            // The owner can't leave without handing the group on; the dialog says how (UX-084).
            Button("Leave group…", systemImage: "rectangle.portrait.and.arrow.right") { confirm(.ownerLeave(group)) }
            Button("Delete group", systemImage: "trash", role: .destructive) { confirm(.delete(group)) }
        } else {
            Button("Leave group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirm(.leave(group))
            }
        }
    }
}
