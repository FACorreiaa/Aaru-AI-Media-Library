import AaruAPI
import SwiftUI

/// GRP-004 / GRP-005: the Groups tab. A stack on iPhone (groups → channels → chat); a split
/// view on iPad and Mac, with groups and their channels in the sidebar and members in the
/// inspector. On iPhone it also holds Friends (SOC-003), which has no tab of its own there.
struct GroupsScreen: View {
    let groups: GroupsModel
    /// Friends, pushed from Groups on iPhone. Nil in previews.
    var social: SocialModel?
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(iOS)
            if sizeClass == .compact {
                GroupsStack(groups: groups, social: social)
            } else {
                GroupsSplit(groups: groups)
            }
        #else
            GroupsSplit(groups: groups)
        #endif
    }
}

private enum GroupRoute: Hashable {
    case group(String)
    case channel(group: String, channel: String)
}

/// iPhone: one column, pushed.
private struct GroupsStack: View {
    let groups: GroupsModel
    let social: SocialModel?
    @Environment(AppRouter.self) private var router
    @State private var path: [GroupRoute] = []
    @State private var sheet: GroupSheet?
    @State private var confirm: GroupConfirm?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $path) {
            GroupsHome(
                groups: groups,
                onOpen: { path = [.group($0.id)] },
                onCreate: { sheet = .create }
            )
            #if os(iOS)
            .toolbar {
                if social != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Friends", systemImage: "person.2") { router.showsFriendsInGroups = true }
                    }
                }
            }
            #endif
            .navigationDestination(isPresented: $router.showsFriendsInGroups) {
                if let social {
                    FriendsContent(model: social)
                }
            }
            .navigationDestination(for: GroupRoute.self) { route in
                switch route {
                case let .group(groupID):
                    ChannelListView(
                        groups: groups, groupID: groupID,
                        present: { sheet = $0 }, confirm: { confirm = $0 },
                        onOpen: { path.append(.channel(group: groupID, channel: $0.id)) }
                    )
                case let .channel(groupID, channelID):
                    ChannelDestination(groups: groups, groupID: groupID, channelID: channelID) {
                        sheet = .members(groupID)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: groups.problem) { groups.problem = nil } }
        .modifier(GroupPresentation(
            groups: groups, sheet: $sheet, confirm: $confirm,
            onCreated: { detail in
                let id = detail.group.id
                path = [.group(id), .channel(group: id, channel: detail.group.defaultChannelId)]
            },
            onChannelCreated: { groupID, channel in path.append(.channel(group: groupID, channel: channel.id)) },
            onShowMembers: { sheet = .members($0) }
        ))
        .task { await groups.load() }
        // Leaving or deleting a group, or being removed, closes it.
        .onChange(of: groups.groups.map(\.id)) { _, ids in
            if case let .group(groupID) = path.first, !ids.contains(groupID) {
                path = []
            }
        }
        // "Discuss in a group…" from a title.
        .onChange(of: groups.openRequest, initial: true) { _, request in
            guard let request else { return }
            path = [.group(request.group), .channel(group: request.group, channel: request.channel)]
            groups.openRequest = nil
        }
    }
}

/// iPad and Mac: groups and channels in the sidebar, the channel in the detail.
private struct GroupsSplit: View {
    let groups: GroupsModel
    @State private var selection: ChannelRef?
    @State private var collapsed: Set<String> = []
    @State private var showsMembers = false
    @State private var sheet: GroupSheet?
    @State private var confirm: GroupConfirm?

    struct ChannelRef: Hashable {
        let group: String
        let channel: String
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        // One banner for the whole split, whichever column caused it (UX-085).
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: groups.problem) { groups.problem = nil } }
        .modifier(GroupPresentation(
            groups: groups, sheet: $sheet, confirm: $confirm,
            onCreated: { detail in
                selection = ChannelRef(group: detail.group.id, channel: detail.group.defaultChannelId)
            },
            onChannelCreated: { groupID, channel in selection = ChannelRef(group: groupID, channel: channel.id) },
            onShowMembers: { present(.members($0)) }
        ))
        .task {
            await groups.load()
            await groups.loadAllDetails()
            if selection == nil, groups.openRequest == nil, let first = groups.groups.first {
                selection = ChannelRef(group: first.id, channel: first.defaultChannelId)
            }
        }
        .onChange(of: groups.groups.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection.group) {
                self.selection = nil
            }
        }
        // "Discuss in a group…" from a title.
        .onChange(of: groups.openRequest, initial: true) { _, request in
            guard let request else { return }
            collapsed.remove(request.group)
            selection = ChannelRef(group: request.group, channel: request.channel)
            groups.openRequest = nil
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            if groups.needsHandle {
                HandleNotice()
            }
            InvitesSection(groups: groups) { group in
                selection = ChannelRef(group: group.id, channel: group.defaultChannelId)
            }
            ForEach(groups.groups, id: \.id) { group in
                DisclosureGroup(isExpanded: expanded(group.id)) {
                    ForEach(groups.details[group.id]?.channels ?? [], id: \.id) { channel in
                        ChannelRow(channel: channel)
                            .tag(ChannelRef(group: group.id, channel: channel.id))
                            .contextMenu {
                                if group.role.manages {
                                    Button("Edit channel", systemImage: "pencil") {
                                        sheet = .editChannel(group.id, channel)
                                    }
                                }
                            }
                    }
                } label: {
                    HStack(spacing: AaruSpace.small) {
                        Monogram(text: group.monogram, size: 28)
                        Text(group.name).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 4)
                        UnreadBadge(unread: group.unread, mentions: group.mentions)
                        Menu("Actions for \(group.name)", systemImage: "ellipsis") {
                            GroupMenuItems(group: group, present: present, confirm: { confirm = $0 })
                        }
                        .labelStyle(.iconOnly)
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Group actions")
                    }
                    .contextMenu {
                        GroupMenuItems(group: group, present: present, confirm: { confirm = $0 })
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            GroupsListOverlay(groups: groups) { sheet = .create }
        }
        .navigationTitle("Groups")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New group", systemImage: "plus") { sheet = .create }.disabled(groups.needsHandle)
            }
        }
        .refreshable {
            await groups.load()
            await groups.loadAllDetails()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection {
            ChannelDestination(groups: groups, groupID: selection.group, channelID: selection.channel) {
                showsMembers.toggle()
            }
            .id(selection)
            .inspector(isPresented: $showsMembers) {
                MemberList(groups: groups, groupID: selection.group) { sheet = .invite(selection.group) }
                    .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
            }
        } else {
            OwlUnavailableView(
                title: "Pick a channel",
                message: "Talk about what you're watching, reading and listening to."
            )
            .background(Color(.paper))
        }
    }

    /// In the split, Members is always the inspector, from the menu as from the toolbar
    /// (UX-085). Members of another group selects that group first.
    private func present(_ request: GroupSheet) {
        if case let .members(groupID) = request {
            if selection?.group != groupID, let group = groups.groups.first(where: { $0.id == groupID }) {
                collapsed.remove(groupID)
                selection = ChannelRef(group: groupID, channel: group.defaultChannelId)
            }
            showsMembers = true
        } else {
            sheet = request
        }
    }

    private func expanded(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    collapsed.remove(groupID)
                } else {
                    collapsed.insert(groupID)
                }
            }
        )
    }
}

/// A channel by id: waits for the group's channels, and says so when the channel is gone.
private struct ChannelDestination: View {
    let groups: GroupsModel
    let groupID: String
    let channelID: String
    let onShowMembers: () -> Void

    var body: some View {
        if let channel = groups.details[groupID]?.channels.first(where: { $0.id == channelID }) {
            if channel.kind == .shelf {
                ShelfScreen(groups: groups, groupID: groupID, channel: channel, onShowMembers: onShowMembers)
            } else {
                ChannelView(groups: groups, groupID: groupID, channel: channel, onShowMembers: onShowMembers)
            }
        } else if groups.details[groupID] != nil {
            ContentUnavailableView("This channel is gone", systemImage: "number")
        } else if let problem = groups.detailProblems[groupID] {
            LoadFailedView(title: "Couldn't open this channel", message: problem) {
                await groups.loadDetail(groupID)
            }
        } else {
            ProgressView().task { await groups.loadDetail(groupID) }
        }
    }
}
