import AaruAPI
import SwiftUI

/// Owner, admins, members and pending invites. The owner changes roles and transfers; admins
/// remove members. Aaru leads the list when it answers in this group.
struct MemberList: View {
    let groups: GroupsModel
    let groupID: String
    let onInvite: () -> Void

    @State private var removing: GroupMember?
    @State private var transferring: GroupMember?

    private var detail: GroupDetail? {
        groups.details[groupID]
    }

    private var myRole: Components.Schemas.GroupRole {
        detail?.group.role ?? .member
    }

    private func members(_ role: Components.Schemas.GroupRole) -> [GroupMember] {
        (detail?.members ?? []).filter { $0.role == role }
    }

    var body: some View {
        List {
            if detail?.agent == true {
                Section("Assistant") { AaruMemberRow() }
            }
            section("Owner", members(.owner))
            section("Admins", members(.admin))
            section("Members", members(.member))
            if let invited = detail?.invited, !invited.isEmpty {
                Section("Invited") {
                    ForEach(invited, id: \.userId) { user in
                        HStack(spacing: 12) {
                            Monogram(text: user.monogram, size: 32)
                            Text(user.label).lineLimit(1).foregroundStyle(Color(.muted))
                        }
                    }
                }
            }
            Section {
                Button("Invite friends", systemImage: "person.badge.plus", action: onInvite)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Members")
        .task { await groups.loadDetail(groupID) }
        .confirmationDialog(
            "Remove @\(removing?.user.handle ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: {
                if !$0 {
                    removing = nil
                }
            }),
            titleVisibility: .visible,
            presenting: removing
        ) { member in
            Button("Remove", role: .destructive) { Task { await groups.remove(member.user.userId, from: groupID) } }
        } message: { _ in
            Text("A friend in the group can invite them back.")
        }
        .confirmationDialog(
            "Make @\(transferring?.user.handle ?? "") the owner?",
            isPresented: Binding(get: { transferring != nil }, set: {
                if !$0 {
                    transferring = nil
                }
            }),
            titleVisibility: .visible,
            presenting: transferring
        ) { member in
            Button("Make owner") { Task { await groups.transfer(groupID, to: member) } }
        } message: { _ in
            Text("You become an admin. Only they can delete the group.")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ members: [GroupMember]) -> some View {
        if !members.isEmpty {
            Section(title) {
                ForEach(members, id: \.user.userId) { member in
                    HStack(spacing: 12) {
                        Monogram(text: member.user.monogram, size: 32)
                        Text(member.user.label).lineLimit(1)
                        if member.user.userId == groups.myUserID {
                            Text("You").font(.caption).foregroundStyle(Color(.muted))
                        }
                        Spacer(minLength: 8)
                        if hasActions(for: member) {
                            Menu {
                                actions(for: member)
                            } label: {
                                Image(systemName: "ellipsis.circle").accessibilityLabel("Actions")
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .fixedSize()
                        }
                    }
                    .contextMenu { actions(for: member) }
                }
            }
        }
    }

    private func hasActions(for member: GroupMember) -> Bool {
        guard member.user.userId != groups.myUserID else { return false }
        switch myRole {
        case .owner: return true
        case .admin: return member.role == .member
        case .member: return false
        }
    }

    @ViewBuilder
    private func actions(for member: GroupMember) -> some View {
        if hasActions(for: member) {
            if myRole == .owner {
                if member.role == .admin {
                    Button("Remove admin", systemImage: "person.badge.minus") {
                        Task { await groups.setAdmin(member, in: groupID, false) }
                    }
                } else {
                    Button("Make admin", systemImage: "person.badge.shield.checkmark") {
                        Task { await groups.setAdmin(member, in: groupID, true) }
                    }
                }
                Button("Make owner…", systemImage: "crown") { transferring = member }
            }
            Button("Remove from group", systemImage: "person.fill.xmark", role: .destructive) { removing = member }
        }
    }
}
