import AaruCore
import Foundation
@testable import aaru

/// Later halves of `UntouchedStore`, kept apart so TestSupport stays under the file-length limit.
extension UntouchedStore: AgentTokenStore, WatchEventStore {
    func record(
        _: PlaybackReport, titleID _: TitleID?, userID _: UserID, agentTokenID _: UUID?, now _: Date
    ) async throws -> WatchSession {
        throw Touched()
    }

    func close(_: UUID, at _: Date) async throws {
        throw Touched()
    }

    func stoppedRecently(userID _: UserID, source _: WatchSource, externalRef _: String, since _: Date) async throws
        -> Bool
    {
        throw Touched()
    }

    func create(_: AgentToken, tokenHash _: String, userID _: UserID) async throws {
        throw Touched()
    }

    func tokens(userID _: UserID) async throws -> [AgentToken] {
        throw Touched()
    }

    func revoke(id _: UUID, userID _: UserID, now _: Date) async throws -> Bool {
        throw Touched()
    }

    func token(forHash _: String, now _: Date) async throws -> (token: AgentToken, userID: UserID)? {
        throw Touched()
    }

    func touch(id _: UUID, at _: Date) async throws {
        throw Touched()
    }
}

extension UntouchedStore {
    func upsertMany(_: [AnimeMapping]) async throws {
        throw Touched()
    }

    func mappings(anilist _: [String]) async throws -> [AnimeMapping] {
        throw Touched()
    }

    func libraryCounts(userID _: UserID) async throws -> LibraryCounts {
        throw Touched()
    }

    func unfinished(userID _: UserID, stalledBefore _: Date, now _: Date, limit _: Int) async throws
        -> [UnfinishedEntry]
    {
        throw Touched()
    }

    func airing(ids _: [TitleID], now _: Date) async throws -> [TitleID: TitleAiring] {
        throw Touched()
    }

    func staleTrackedShows(now _: Date, retryAfter _: Date, limit _: Int) async throws -> [TitleID] {
        throw Touched()
    }

    func markEpisodesAttempted(_: TitleID, at _: Date) async throws {
        throw Touched()
    }

    func saveWebPush(_: WebPushSubscription, userID _: UserID) async throws {
        throw Touched()
    }

    func deleteWebPush(endpoint _: String, userID _: UserID) async throws {
        throw Touched()
    }

    func forgetWebPush(endpoint _: String) async throws {
        throw Touched()
    }

    func webPushSubscriptions(userID _: UserID) async throws -> [WebPushSubscription] {
        throw Touched()
    }

    func mapping(mal _: String) async throws -> AnimeMapping? {
        throw Touched()
    }

    func statusSetByHand(itemID _: LibraryItemID) async throws -> Bool {
        throw Touched()
    }

    func apply(_: LibraryOp, userID _: UserID, caller _: Caller, kind _: String, summary _: String) async throws
        -> ActionRecord
    {
        throw Touched()
    }
}

extension UntouchedStore: SocialStore {
    func socialUser(_: UserID) async throws -> SocialUser? {
        throw Touched()
    }

    func socialUser(handle _: String) async throws -> SocialUser? {
        throw Touched()
    }

    func saveProfile(_: UserID, handle _: String, displayName _: String??) async throws {
        throw Touched()
    }

    func isBlocked(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func areFriends(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func pendingRequest(sender _: UserID, recipient _: UserID) async throws -> UUID? {
        throw Touched()
    }

    func createRequest(id _: UUID, sender _: UserID, recipient _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func incomingRequests(_: UserID) async throws -> [FriendRequest] {
        throw Touched()
    }

    func outgoingRequests(_: UserID) async throws -> [FriendRequest] {
        throw Touched()
    }

    func acceptRequest(id _: UUID, recipient _: UserID, now _: Date) async throws -> UserID? {
        throw Touched()
    }

    func deleteRequest(id _: UUID, party _: UserID) async throws -> Bool {
        throw Touched()
    }

    func friends(_: UserID) async throws -> [SocialUser] {
        throw Touched()
    }

    func unfriend(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func block(_: UserID, _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func unblock(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func blocked(by _: UserID) async throws -> [SocialUser] {
        throw Touched()
    }

    func report(_: UserReport) async throws {
        throw Touched()
    }
}

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

    func createInvite(id _: UUID, group _: UUID, inviter _: UserID, invitee _: UserID, now _: Date) async throws {
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

    func deleteInvite(id _: UUID, party _: UserID) async throws -> Bool {
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

extension UntouchedStore {
    func createStremioLink(code _: String, userID _: UserID, expiresAt _: Date, now _: Date) async throws {
        throw Touched()
    }

    func stremioLinkExpiry(code _: String, userID _: UserID) async throws -> Date? {
        throw Touched()
    }

    func consumeStremioLink(code _: String, userID _: UserID) async throws -> Bool {
        throw Touched()
    }
}

extension UntouchedStore: PlanStore {
    func create(_: AgentPlan, userID _: UserID) async throws {
        throw Touched()
    }

    func plans(userID _: UserID, pendingOnly _: Bool, now _: Date, limit _: Int) async throws -> [AgentPlan] {
        throw Touched()
    }

    func plan(id _: UUID, userID _: UserID) async throws -> AgentPlan? {
        throw Touched()
    }

    func pendingCount(agentTokenID _: UUID, now _: Date) async throws -> Int {
        throw Touched()
    }

    func itemVersions(_: [LibraryItemID], userID _: UserID) async throws -> [String: Int64] {
        throw Touched()
    }

    func approve(id _: UUID, userID _: UserID, now _: Date) async throws -> PlanDecision? {
        throw Touched()
    }

    func deny(id _: UUID, userID _: UserID, now _: Date) async throws -> PlanDecision? {
        throw Touched()
    }
}

extension UntouchedStore: OAuthStore {
    func register(_: OAuthClient) async throws {
        throw Touched()
    }

    func client(id _: String) async throws -> OAuthClient? {
        throw Touched()
    }

    func createRequest(_: OAuthRequest) async throws {
        throw Touched()
    }

    func request(id _: UUID, now _: Date) async throws -> OAuthRequest? {
        throw Touched()
    }

    func consumeRequest(id _: UUID, now _: Date) async throws -> OAuthRequest? {
        throw Touched()
    }

    func createCode(_: OAuthCode, hash _: String) async throws {
        throw Touched()
    }

    func redeemCode(hash _: String, now _: Date) async throws -> CodeRedemption? {
        throw Touched()
    }

    // swiftlint:disable:next function_parameter_count
    func issue(
        _: AgentToken, userID _: UserID, clientID _: String, codeHash _: String, accessHash _: String,
        accessExpiresAt _: Date, refreshHash _: String, refreshExpiresAt _: Date
    ) async throws {
        throw Touched()
    }

    // swiftlint:disable:next function_parameter_count
    func rotate(
        refreshHash _: String, clientID _: String, now _: Date, accessHash _: String, accessExpiresAt _: Date,
        newRefreshHash _: String, refreshExpiresAt _: Date
    ) async throws -> RefreshOutcome {
        throw Touched()
    }

    func revoke(tokenHash _: String, now _: Date) async throws {
        throw Touched()
    }
}
