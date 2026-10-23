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

    func openSessions(userID _: UserID, source _: WatchSource?, limit _: Int) async throws -> [OpenSession] {
        throw Touched()
    }

    func registerLiveActivity(_: LiveActivityToken, userID _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func hasLiveActivityTokens(userID _: UserID) async throws -> Bool {
        throw Touched()
    }

    func liveActivityStartTokens(userID _: UserID) async throws -> [LiveActivityToken] {
        throw Touched()
    }

    func liveActivityUpdateTokens(userID _: UserID) async throws -> [LiveActivityToken] {
        throw Touched()
    }

    func forgetLiveActivity(token _: String) async throws {
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

    func mappings(tmdb _: [String]) async throws -> [AnimeMapping] {
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

    func titlesMissingGenres(retryAfter _: Date, limit _: Int) async throws -> [Title] {
        throw Touched()
    }

    func booksMissingPageCount(retryAfter _: Date, limit _: Int) async throws -> [Title] {
        throw Touched()
    }

    func fillPageCount(_: TitleID, _: Int?, attemptedAt _: Date) async throws {
        throw Touched()
    }

    func fillGenres(_: TitleID, _: [String], attemptedAt _: Date) async throws {
        throw Touched()
    }

    func genres(_: TitleID) async throws -> [String] {
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

    func blockers(of _: UserID) async throws -> Set<UserID> {
        throw Touched()
    }
}

extension UntouchedStore: AgentStore {
    func enqueue(_: AgentReplyJob, state _: AgentReplyState, now _: Date) async throws {
        throw Touched()
    }

    func load(tagger _: UserID, group _: UUID, dayStart _: Date, hourStart _: Date) async throws -> AgentLoad {
        throw Touched()
    }

    func claim(now _: Date, lease _: TimeInterval) async throws -> AgentReplyJob? {
        throw Touched()
    }

    func finish(_: UUID, state _: AgentReplyState, error _: String?, now _: Date) async throws {
        throw Touched()
    }

    func retry(_: UUID, error _: String, notBefore _: Date, now _: Date) async throws {
        throw Touched()
    }

    func recordUsage(_: UserID, day _: Date, inputTokens _: Int, outputTokens _: Int, costMicros _: Int) async throws {
        throw Touched()
    }

    func usage(_: UserID, day _: Date) async throws -> AgentUsage {
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

extension UntouchedStore: PushStore {
    func register(_: PushDevice, userID _: UserID) async throws {
        throw Touched()
    }

    func unregister(token _: String, userID _: UserID) async throws {
        throw Touched()
    }

    func forget(token _: String) async throws {
        throw Touched()
    }

    func devices(userID _: UserID) async throws -> [PushDevice] {
        throw Touched()
    }

    func notificationSettings(userID _: UserID) async throws -> NotificationSettings {
        throw Touched()
    }

    func saveNotificationSettings(_: NotificationSettings, userID _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func mentionRecipients(group _: UUID, users _: [UserID]) async throws -> [UserID] {
        throw Touched()
    }

    func dueAirings(now _: Date, since _: Date) async throws -> [DueAiring] {
        throw Touched()
    }

    func claim(_: DueAiring) async throws -> Bool {
        throw Touched()
    }
}
