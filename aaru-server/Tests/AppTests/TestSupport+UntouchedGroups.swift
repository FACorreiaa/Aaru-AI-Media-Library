import AaruCore
import Foundation
@testable import aaru

// Group stubs, apart from TestSupport+Untouched.swift to keep both under the file-length limit.

extension UntouchedStore: GroupStore {
    func groups(for _: UserID) async throws -> [GroupSummary] {
        throw Touched()
    }

    func summary(_: UUID, viewer _: UserID) async throws -> GroupSummary? {
        throw Touched()
    }

    func ownedCount(_: UserID) async throws -> Int {
        throw Touched()
    }

    func createGroup(id _: UUID, name _: String, owner _: UserID, general _: GroupChannel, now _: Date) async throws {
        throw Touched()
    }

    func renameGroup(_: UUID, name _: String, now _: Date) async throws {
        throw Touched()
    }

    func deleteGroup(_: UUID) async throws {
        throw Touched()
    }

    func members(_: UUID) async throws -> [GroupMember] {
        throw Touched()
    }

    func role(_: UUID, user _: UserID) async throws -> GroupRole? {
        throw Touched()
    }

    func setRole(_: UUID, user _: UserID, role _: GroupRole) async throws {
        throw Touched()
    }

    func removeMember(_: UUID, user _: UserID) async throws {
        throw Touched()
    }

    func transferOwnership(_: UUID, from _: UserID, to _: UserID) async throws {
        throw Touched()
    }

    func setMuted(_: UUID, user _: UserID, muted _: Bool) async throws {
        throw Touched()
    }

    func createInvite(
        id _: UUID, group _: UUID, inviter _: UserID, invitee _: UserID, now _: Date
    ) async throws -> Bool {
        throw Touched()
    }

    func invites(to _: UserID) async throws -> [GroupInvite] {
        throw Touched()
    }

    func invitesPending(_: UUID) async throws -> [GroupInvite] {
        throw Touched()
    }

    func acceptInvite(id _: UUID, invitee _: UserID, now _: Date) async throws -> UUID? {
        throw Touched()
    }

    func deleteInvite(id _: UUID, party _: UserID) async throws -> (group: UUID, invitee: UserID)? {
        throw Touched()
    }

    func channels(_: UUID, viewer _: UserID) async throws -> [GroupChannel] {
        throw Touched()
    }

    func channel(_: UUID, group _: UUID) async throws -> GroupChannel? {
        throw Touched()
    }

    func createChannel(_: GroupChannel) async throws {
        throw Touched()
    }

    func updateChannel(_: UUID, name _: String?, topic _: String??) async throws {
        throw Touched()
    }

    func deleteChannel(_: UUID) async throws -> Bool {
        throw Touched()
    }

    func messages(_: UUID, cursor _: MessageCursor, limit _: Int) async throws -> [GroupMessage] {
        throw Touched()
    }

    func message(_: UUID, channel _: UUID) async throws -> GroupMessage? {
        throw Touched()
    }

    func postMessage(_: GroupMessage, nonce _: String?) async throws -> GroupMessage {
        throw Touched()
    }

    func editMessage(_: UUID, body _: String, mentions _: [UserID], mentionsAgent _: Bool, now _: Date) async throws {
        throw Touched()
    }

    func deleteMessage(_: UUID, now _: Date) async throws {
        throw Touched()
    }

    func markRead(_: UserID, channel _: UUID, upTo _: UUID) async throws {
        throw Touched()
    }

    func exportMessages(_: UserID) async throws -> [ExportedGroupMessage] {
        throw Touched()
    }
}

extension UntouchedStore: GroupKindStore {
    func setShareProgress(_: UUID, user _: UserID, share _: Bool) async throws {
        throw Touched()
    }

    func progress(title _: TitleID, users _: [UserID]) async throws -> [UserID: TitleProgress] {
        throw Touched()
    }

    func shelfItems(_: UUID, viewer _: UserID) async throws -> [ShelfItem] {
        throw Touched()
    }

    func addShelfItem(_: UUID, title _: TitleID, by _: UserID, now _: Date) async throws -> Bool {
        throw Touched()
    }

    func removeShelfItem(_: UUID, title _: TitleID) async throws -> Bool {
        throw Touched()
    }

    func latestParty(_: UUID) async throws -> WatchParty? {
        throw Touched()
    }

    func createSession(_: WatchParty) async throws {
        throw Touched()
    }

    func setReady(_: UUID, user _: UserID, ready _: Bool) async throws {
        throw Touched()
    }

    func startSession(_: UUID, at _: Date) async throws {
        throw Touched()
    }

    func endSession(_: UUID, now _: Date) async throws {
        throw Touched()
    }
}

/// A date Postgres stores without loss (whole seconds).
func wholeSecondNow() -> Date {
    Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
}
