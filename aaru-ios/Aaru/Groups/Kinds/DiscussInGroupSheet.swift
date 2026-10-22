import AaruAPI
import SwiftUI

extension GroupsModel {
    /// Groups where the user can add channels.
    var managedGroups: [GroupSummary] {
        groups.filter(\.role.manages)
    }

    /// The group's channel about this title, if it has one.
    func titleChannel(for title: TitleSummary, in groupID: String) -> GroupChannel? {
        details[groupID]?.channels.first { $0.kind == .title && $0.title?.id == title.id }
    }

    /// Opens the group's channel about this title, creating it first when there is none and the
    /// user manages the group.
    func discuss(_ title: TitleSummary, in groupID: String) async -> Bool {
        if details[groupID] == nil {
            await loadDetail(groupID)
        }
        if let existing = titleChannel(for: title, in: groupID) {
            openRequest = ChannelOpenRequest(group: groupID, channel: existing.id)
            return true
        }
        guard role(in: groupID)?.manages == true,
              let created = await createChannel(in: groupID, kind: .title, name: "", topic: "", title: title.mediaRef)
        else { return false }
        openRequest = ChannelOpenRequest(group: groupID, channel: created.id)
        return true
    }
}

/// "Discuss in a group…" from a title: every group the user is in (UX-083). "Open" where the
/// group already has a channel about the title; where it has none, only a manager can start one.
struct DiscussInGroupSheet: View {
    let groups: GroupsModel
    let title: TitleSummary
    @Environment(\.dismiss) private var dismiss
    @State private var working: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups.groups, id: \.id) { group in
                        DiscussRow(
                            group: group,
                            action: action(in: group),
                            working: working == group.id
                        ) { open(group) }
                            .disabled(working != nil || action(in: group) == .unavailable)
                    }
                } footer: {
                    Text("Group messages there hide spoilers from anyone who hasn't caught up.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .navigationTitle("Discuss \(title.title)")
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: groups.problem) { groups.problem = nil } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await groups.loadAllDetails() }
        }
    }

    private func action(in group: GroupSummary) -> DiscussRow.Action {
        if groups.titleChannel(for: title, in: group.id) != nil {
            return .open
        }
        return group.role.manages ? .start : .unavailable
    }

    private func open(_ group: GroupSummary) {
        Task {
            working = group.id
            defer { working = nil }
            if await groups.discuss(title, in: group.id) {
                dismiss()
            }
        }
    }
}

private struct DiscussRow: View {
    enum Action {
        case open, start, unavailable
    }

    let group: GroupSummary
    let action: Action
    let working: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Monogram(text: group.monogram, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).lineLimit(2)
                    if action == .unavailable {
                        Text("No channel about it yet. An admin can start one.")
                            .font(.caption)
                            .foregroundStyle(Color(.muted))
                    }
                }
                Spacer(minLength: 8)
                if working {
                    ProgressView()
                } else {
                    switch action {
                    case .open: Text("Open").foregroundStyle(Color(.accent))
                    case .start: Text("Start").foregroundStyle(Color(.accent))
                    case .unavailable: EmptyView()
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
