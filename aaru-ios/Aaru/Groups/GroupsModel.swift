import AaruAPI
import Foundation
import Observation

typealias GroupSummary = Components.Schemas.GroupSummary
typealias GroupDetail = Components.Schemas.GroupDetail
typealias GroupChannel = Components.Schemas.Channel
typealias GroupMember = Components.Schemas.GroupMember
typealias GroupInvite = Components.Schemas.GroupInvite
typealias GroupMessage = Components.Schemas.GroupMessage

/// GRP-001 / GRP-002: the user's groups, invites waiting for them, and each group's channels and
/// members. Friends-only: the only way into a group is an invite from a friend.
@MainActor
@Observable
final class GroupsModel {
    private(set) var groups: [GroupSummary] = []
    private(set) var invites: [GroupInvite] = []
    private(set) var details: [String: GroupDetail] = [:]
    private(set) var friends: [SocialUser] = []
    private(set) var myUserID: String?
    private(set) var myHandle: String?
    private(set) var hasLoaded = false
    var problem: String?

    @ObservationIgnored let api: Client?

    init(api: Client?) {
        self.api = api
    }

    /// Unread mentions across every group, for the tab badge.
    var mentionTotal: Int {
        groups.reduce(0) { $0 + $1.mentions }
    }

    /// Group actions need a handle, so friends can see who is talking.
    var needsHandle: Bool {
        hasLoaded && myHandle == nil
    }

    func role(in groupID: String) -> Components.Schemas.GroupRole? {
        details[groupID]?.group.role ?? groups.first { $0.id == groupID }?.role
    }

    func reset() {
        groups = []
        invites = []
        details = [:]
        friends = []
        myUserID = nil
        myHandle = nil
        hasLoaded = false
        problem = nil
    }

    // MARK: Reads

    func load() async {
        guard let api else { return }
        do {
            async let meCall = api.getMe()
            async let groupsCall = api.listGroups()
            async let invitesCall = api.listGroupInvites()
            if case let .ok(response) = try await meCall, let account = try? response.body.json {
                myUserID = account.userId
                myHandle = account.handle
            }
            if case let .ok(response) = try await groupsCall {
                groups = try response.body.json.items
            }
            if case let .ok(response) = try await invitesCall {
                invites = try response.body.json.items
            }
            details = details.filter { id, _ in groups.contains { $0.id == id } }
            hasLoaded = true
        } catch {
            problem = "Your groups could not be loaded. Aaru could not reach the server."
        }
    }

    /// Loads every group's channels and members; there are only ever a few.
    func loadAllDetails() async {
        await withTaskGroup(of: Void.self) { tasks in
            for group in groups {
                tasks.addTask { await self.loadDetail(group.id) }
            }
        }
    }

    func loadDetail(_ groupID: String) async {
        guard let api else { return }
        do {
            switch try await api.getGroup(path: .init(groupId: groupID)) {
            case let .ok(response):
                let detail = try response.body.json
                details[groupID] = detail
                if let index = groups.firstIndex(where: { $0.id == groupID }) {
                    groups[index] = detail.group
                }
            case .default:
                // Gone, or no longer a member.
                details[groupID] = nil
                groups.removeAll { $0.id == groupID }
            }
        } catch {
            problem = "That group could not be loaded. Aaru could not reach the server."
        }
    }

    func loadFriends() async {
        guard let api else { return }
        if case let .ok(response) = try? await api.listFriends(), let list = try? response.body.json {
            friends = list.items
        }
    }

    /// After reading a channel: refresh its counts and the group's.
    func refreshCounts(_ groupID: String) async {
        await loadDetail(groupID)
    }

    // MARK: Groups

    func create(named name: String) async -> GroupDetail? {
        guard let api else { return nil }
        var created: GroupDetail?
        await run("The group was not created.") {
            switch try await api.createGroup(body: .json(.init(name: name))) {
            case let .ok(response):
                let detail = try response.body.json
                details[detail.group.id] = detail
                groups.append(detail.group)
                created = detail
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
        return created
    }

    func rename(_ groupID: String, to name: String) async -> Bool {
        guard let api else { return false }
        return await run("The group was not renamed.") {
            switch try await api.updateGroup(path: .init(groupId: groupID), body: .json(.init(name: name))) {
            case let .ok(response):
                let detail = try response.body.json
                details[groupID] = detail
                if let index = groups.firstIndex(where: { $0.id == groupID }) {
                    groups[index] = detail.group
                }
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    func delete(_ groupID: String) async -> Bool {
        guard let api else { return false }
        return await run("The group was not deleted.") {
            switch try await api.deleteGroup(path: .init(groupId: groupID)) {
            case .noContent: forget(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    func leave(_ groupID: String) async -> Bool {
        guard let myUserID else { return false }
        return await remove(myUserID, from: groupID)
    }

    // MARK: Members

    func setAdmin(_ member: GroupMember, in groupID: String, _ isAdmin: Bool) async {
        guard let api else { return }
        await run("That role was not changed.") {
            switch try await api.updateGroupMember(
                path: .init(groupId: groupID, userId: member.user.userId),
                body: .json(.init(role: isAdmin ? .admin : .member))
            ) {
            case .noContent: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    /// Removes a member, or the user themselves to leave.
    @discardableResult
    func remove(_ userID: String, from groupID: String) async -> Bool {
        guard let api else { return false }
        return await run("That member was not removed.") {
            switch try await api.removeGroupMember(path: .init(groupId: groupID, userId: userID)) {
            case .noContent:
                if userID == myUserID {
                    forget(groupID)
                } else {
                    await loadDetail(groupID)
                }
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    func transfer(_ groupID: String, to member: GroupMember) async {
        guard let api else { return }
        await run("Ownership was not transferred.") {
            switch try await api.transferGroup(
                path: .init(groupId: groupID), body: .json(.init(userId: member.user.userId))
            ) {
            case .noContent: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    // MARK: Invites

    func invite(_ friend: SocialUser, to groupID: String) async {
        guard let api else { return }
        await run("That invite was not sent.") {
            switch try await api.inviteToGroup(
                path: .init(groupId: groupID), body: .json(.init(userId: friend.userId))
            ) {
            case .noContent: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    func accept(_ invite: GroupInvite) async -> GroupSummary? {
        guard let api else { return nil }
        var joined: GroupSummary?
        await run("That invite could not be accepted.") {
            switch try await api.acceptGroupInvite(path: .init(id: invite.id)) {
            case let .ok(response):
                let group = try response.body.json
                invites.removeAll { $0.id == invite.id }
                groups.removeAll { $0.id == group.id }
                groups.append(group)
                joined = group
                await loadDetail(group.id)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
        return joined
    }

    func decline(_ invite: GroupInvite) async {
        guard let api else { return }
        await run("That invite is already gone.") {
            switch try await api.declineGroupInvite(path: .init(id: invite.id)) {
            case .noContent: invites.removeAll { $0.id == invite.id }
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    // MARK: Plumbing

    private func forget(_ groupID: String) {
        groups.removeAll { $0.id == groupID }
        details[groupID] = nil
    }

    struct Failure: Error {
        let response: Components.Schemas.ErrorResponse?
        init(_ response: Components.Schemas.ErrorResponse?) {
            self.response = response
        }
    }

    /// Runs one write and turns any failure into one visible message. True when it succeeded.
    @discardableResult
    private func run(_ fallback: String, _ call: () async throws -> Void) async -> Bool {
        problem = nil
        do {
            try await call()
            return true
        } catch let failure as Failure {
            if failure.response?.code == "handle_required" {
                myHandle = nil
            }
            problem = failure.response?.message ?? fallback
        } catch {
            problem = "\(fallback) Aaru could not reach the server."
        }
        return false
    }
}

extension GroupsModel {
    // MARK: Channels

    func createChannel(in groupID: String, name: String, topic: String) async -> GroupChannel? {
        guard let api else { return nil }
        var created: GroupChannel?
        await run("The channel was not created.") {
            switch try await api.createChannel(
                path: .init(groupId: groupID), body: .json(.init(name: name, topic: topic.isEmpty ? nil : topic))
            ) {
            case let .ok(response):
                created = try response.body.json
                await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
        return created
    }

    /// An empty topic clears it.
    func updateChannel(_ channel: GroupChannel, in groupID: String, name: String, topic: String) async -> Bool {
        guard let api else { return false }
        return await run("The channel was not saved.") {
            switch try await api.updateChannel(
                path: .init(groupId: groupID, channelId: channel.id),
                body: .json(.init(name: name, topic: topic))
            ) {
            case .ok: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    func deleteChannel(_ channel: GroupChannel, in groupID: String) async -> Bool {
        guard let api else { return false }
        return await run("The channel was not deleted.") {
            switch try await api.deleteChannel(path: .init(groupId: groupID, channelId: channel.id)) {
            case .noContent: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }
}

extension GroupSummary {
    /// One or two letters for the rail.
    var monogram: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return String(name.first ?? "?").uppercased()
    }
}

extension Components.Schemas.GroupRole {
    var manages: Bool {
        self != .member
    }
}
