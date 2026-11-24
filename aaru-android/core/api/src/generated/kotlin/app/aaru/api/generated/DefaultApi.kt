package app.aaru.api.generated

import app.aaru.api.infrastructure.CollectionFormats.*
import retrofit2.http.*
import retrofit2.Response
import okhttp3.RequestBody
import okhttp3.ResponseBody
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

import app.aaru.api.generated.models.AISharing
import app.aaru.api.generated.models.AISharingUpdate
import app.aaru.api.generated.models.AccountExport
import app.aaru.api.generated.models.Action
import app.aaru.api.generated.models.ActionList
import app.aaru.api.generated.models.ActivityPage
import app.aaru.api.generated.models.AddLibraryItem
import app.aaru.api.generated.models.AddListItem
import app.aaru.api.generated.models.AgentMCPKind
import app.aaru.api.generated.models.AgentPlan
import app.aaru.api.generated.models.AgentSetup
import app.aaru.api.generated.models.AgentTokenCreate
import app.aaru.api.generated.models.AgentTokenCreated
import app.aaru.api.generated.models.AppleSignInRequest
import app.aaru.api.generated.models.ApproveOAuthRequestRequest
import app.aaru.api.generated.models.ApprovePlan200Response
import app.aaru.api.generated.models.ArtistConcerts
import app.aaru.api.generated.models.BadgeList
import app.aaru.api.generated.models.BoardComment
import app.aaru.api.generated.models.BoardCommentCreate
import app.aaru.api.generated.models.BoardCommentPage
import app.aaru.api.generated.models.BoardPost
import app.aaru.api.generated.models.BoardPostCreate
import app.aaru.api.generated.models.BoardPostEdit
import app.aaru.api.generated.models.BoardPostPage
import app.aaru.api.generated.models.Calendar
import app.aaru.api.generated.models.Channel
import app.aaru.api.generated.models.ChannelCreate
import app.aaru.api.generated.models.ChannelItemCreate
import app.aaru.api.generated.models.ChannelItemList
import app.aaru.api.generated.models.ChannelProgress
import app.aaru.api.generated.models.ChannelUpdate
import app.aaru.api.generated.models.Chat
import app.aaru.api.generated.models.ChatAttachment
import app.aaru.api.generated.models.ChatCreated
import app.aaru.api.generated.models.ChatList
import app.aaru.api.generated.models.ChatStatus
import app.aaru.api.generated.models.ChatTranscript
import app.aaru.api.generated.models.ChatTurnRequest
import app.aaru.api.generated.models.ConcertPage
import app.aaru.api.generated.models.ConcertPerformerList
import app.aaru.api.generated.models.ConcertPerformerRequest
import app.aaru.api.generated.models.ConcertPlace
import app.aaru.api.generated.models.ConcertPlaceList
import app.aaru.api.generated.models.ConcertPlaceSetting
import app.aaru.api.generated.models.ConcertSearchPage
import app.aaru.api.generated.models.ConcertSearchRequest
import app.aaru.api.generated.models.ConcertsNearRequest
import app.aaru.api.generated.models.CreateAniListImportRequest
import app.aaru.api.generated.models.CreateCATFeedImportRequest
import app.aaru.api.generated.models.CreateCaptureImportRequest

import app.aaru.api.generated.models.CreateList
import app.aaru.api.generated.models.CreateShelf
import app.aaru.api.generated.models.DenyOAuthRequestRequest
import app.aaru.api.generated.models.DeviceRegistration
import app.aaru.api.generated.models.DiscoverOnAir
import app.aaru.api.generated.models.DiscoverRowKind
import app.aaru.api.generated.models.DiscoverRows
import app.aaru.api.generated.models.Entitlement
import app.aaru.api.generated.models.EpisodeWatched
import app.aaru.api.generated.models.ErrorResponse
import app.aaru.api.generated.models.FavoriteKind
import app.aaru.api.generated.models.Favorites
import app.aaru.api.generated.models.FavoritesUpdate
import app.aaru.api.generated.models.FriendInvite
import app.aaru.api.generated.models.FriendInviteCreate
import app.aaru.api.generated.models.FriendInviteList
import app.aaru.api.generated.models.FriendProfile
import app.aaru.api.generated.models.FriendRequestCreate
import app.aaru.api.generated.models.FriendRequests
import app.aaru.api.generated.models.GoogleSignInRequest
import app.aaru.api.generated.models.GroupCreate
import app.aaru.api.generated.models.GroupDetail
import app.aaru.api.generated.models.GroupInviteList
import app.aaru.api.generated.models.GroupList
import app.aaru.api.generated.models.GroupMemberUpdate
import app.aaru.api.generated.models.GroupMessage
import app.aaru.api.generated.models.GroupMessagePage
import app.aaru.api.generated.models.GroupSummary
import app.aaru.api.generated.models.Health
import app.aaru.api.generated.models.ImportDetail
import app.aaru.api.generated.models.ImportJob
import app.aaru.api.generated.models.ImportList
import app.aaru.api.generated.models.InvitePreview
import app.aaru.api.generated.models.InviteRedeem
import app.aaru.api.generated.models.InviteRedemption
import app.aaru.api.generated.models.Leaderboard
import app.aaru.api.generated.models.LeaveOutImportRow200Response
import app.aaru.api.generated.models.LeaveOutImportRowRequest
import app.aaru.api.generated.models.LibraryEntry
import app.aaru.api.generated.models.LibraryItemPatch
import app.aaru.api.generated.models.LibraryPage
import app.aaru.api.generated.models.LibraryStatus
import app.aaru.api.generated.models.LibrarySync
import app.aaru.api.generated.models.ListAgentTokens200Response
import app.aaru.api.generated.models.ListDetail
import app.aaru.api.generated.models.ListList
import app.aaru.api.generated.models.ListOrder
import app.aaru.api.generated.models.ListPlans200Response
import app.aaru.api.generated.models.ListenAccount
import app.aaru.api.generated.models.ListenPage
import app.aaru.api.generated.models.ListenTop
import app.aaru.api.generated.models.LiveActivityRegistration
import app.aaru.api.generated.models.MALConnectRequest
import app.aaru.api.generated.models.MALConnectStart
import app.aaru.api.generated.models.MALConnection
import app.aaru.api.generated.models.MagicLinkRequest
import app.aaru.api.generated.models.MagicLinkVerifyRequest
import app.aaru.api.generated.models.MarkBadgesSeenRequest
import app.aaru.api.generated.models.MatchAllImportRows200Response
import app.aaru.api.generated.models.Me
import app.aaru.api.generated.models.MediaRef
import app.aaru.api.generated.models.MediaType
import app.aaru.api.generated.models.MembershipUpdate
import app.aaru.api.generated.models.MessageCreate
import app.aaru.api.generated.models.MessageUpdate
import app.aaru.api.generated.models.MyWorlds
import app.aaru.api.generated.models.NotificationSettings
import app.aaru.api.generated.models.NotificationSettingsUpdate
import app.aaru.api.generated.models.NowPlayingReply
import app.aaru.api.generated.models.OAuthConsentRequest
import app.aaru.api.generated.models.OAuthRedirect
import app.aaru.api.generated.models.OnboardingFinish
import app.aaru.api.generated.models.OnboardingPicked
import app.aaru.api.generated.models.OnboardingPicks
import app.aaru.api.generated.models.OnboardingRelated
import app.aaru.api.generated.models.OnboardingRelatedRequest
import app.aaru.api.generated.models.PointsPage
import app.aaru.api.generated.models.ProfileStats
import app.aaru.api.generated.models.ProfileUpdate
import app.aaru.api.generated.models.Progress
import app.aaru.api.generated.models.ReactionSet
import app.aaru.api.generated.models.ReadMark
import app.aaru.api.generated.models.RealtimeTicket
import app.aaru.api.generated.models.ReceiveAppleNotificationRequest
import app.aaru.api.generated.models.RecommendationCreate
import app.aaru.api.generated.models.RecommendationList
import app.aaru.api.generated.models.RecordAppleTransactionRequest
import app.aaru.api.generated.models.RelationGraph
import app.aaru.api.generated.models.RelationOrder
import app.aaru.api.generated.models.RenameList
import app.aaru.api.generated.models.ReportCreate
import app.aaru.api.generated.models.ResolveImportRowRequest
import app.aaru.api.generated.models.SearchResults
import app.aaru.api.generated.models.SeasonPage
import app.aaru.api.generated.models.Session
import app.aaru.api.generated.models.ShareCreate
import app.aaru.api.generated.models.ShareLink
import app.aaru.api.generated.models.SharePreview
import app.aaru.api.generated.models.Shelf
import app.aaru.api.generated.models.ShelfList
import app.aaru.api.generated.models.ShowWatched
import app.aaru.api.generated.models.SocialSettings
import app.aaru.api.generated.models.SocialUser
import app.aaru.api.generated.models.SocialUserList
import app.aaru.api.generated.models.SocialUserView
import app.aaru.api.generated.models.SportEntity
import app.aaru.api.generated.models.SportEntityKind
import app.aaru.api.generated.models.SportEntityList
import app.aaru.api.generated.models.SportEventDetail
import app.aaru.api.generated.models.SportFavorites
import app.aaru.api.generated.models.SportFollowList
import app.aaru.api.generated.models.SportSchedule
import app.aaru.api.generated.models.SportSettings
import app.aaru.api.generated.models.SportSettingsInput
import app.aaru.api.generated.models.Stats
import app.aaru.api.generated.models.StremioLink
import app.aaru.api.generated.models.TitleDetail
import app.aaru.api.generated.models.TitlePreview
import app.aaru.api.generated.models.TitleTree
import app.aaru.api.generated.models.TitleWatch
import app.aaru.api.generated.models.Tonight
import app.aaru.api.generated.models.TonightFeedback
import app.aaru.api.generated.models.TraktConnectRequest
import app.aaru.api.generated.models.TraktConnectStart
import app.aaru.api.generated.models.TraktConnection
import app.aaru.api.generated.models.UpNext
import app.aaru.api.generated.models.UpdateShelf
import app.aaru.api.generated.models.UserRef
import app.aaru.api.generated.models.WatchPartyCreate
import app.aaru.api.generated.models.WatchPartyReady
import app.aaru.api.generated.models.WatchPartyStart
import app.aaru.api.generated.models.WatchPartyView
import app.aaru.api.generated.models.Watching
import app.aaru.api.generated.models.WebPushKey
import app.aaru.api.generated.models.WebPushSubscription
import app.aaru.api.generated.models.World

import okhttp3.MultipartBody

public interface DefaultApi {
    /**
     * POST v1/social/friend-requests/{id}/accept
     * 
     * 
     * Responses:
     *  - 200: The new friend.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [SocialUser]
     */
    @POST("v1/social/friend-requests/{id}/accept")
    public suspend fun acceptFriendRequest(@Path("id") id: java.util.UUID): Response<SocialUser>

    /**
     * POST v1/group-invites/{id}/accept
     * Join the group.
     * 
     * Responses:
     *  - 200: The group you joined.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [GroupSummary]
     */
    @POST("v1/group-invites/{id}/accept")
    public suspend fun acceptGroupInvite(@Path("id") id: java.util.UUID): Response<GroupSummary>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/items
     * Add a title to a shelf channel. Any member can; adding one already there changes nothing.
     * 
     * Responses:
     *  - 200: The shelf.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param channelItemCreate 
     * @return [ChannelItemList]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/items")
    public suspend fun addChannelItem(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body channelItemCreate: ChannelItemCreate): Response<ChannelItemList>

    /**
     * POST v1/library/items
     * Add a title to the library. Adding the same title again returns the existing item.
     * 
     * Responses:
     *  - 200: The item.
     *  - 0: Any error, in the shared shape.
     *
     * @param addLibraryItem 
     * @return [LibraryEntry]
     */
    @POST("v1/library/items")
    public suspend fun addLibraryItem(@Body addLibraryItem: AddLibraryItem): Response<LibraryEntry>

    /**
     * POST v1/lists/{id}/items
     * Add a title to a list. It need not be in the library.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param addListItem 
     * @return [ListDetail]
     */
    @POST("v1/lists/{id}/items")
    public suspend fun addListItem(@Path("id") id: java.util.UUID, @Body addListItem: AddListItem): Response<ListDetail>

    /**
     * POST v1/onboarding/picks
     * Add the titles picked in one step of the first-run flow, each with its status (ONB-001).
     * One journaled action (one undo), journal kind `onboarding`: the picks were watched, read or heard before, so their ticks carry no date, they earn no points and no streak day, and the Recap leaves them out. A status other than `wishlist` counts as set by hand, so a later import never moves it back. A title already in the library is returned unchanged. A ref that resolves to no title is left out of `items` and counted in `missed`. 1 to 60 items, else 422.
     * Responses:
     *  - 200: The library items, in the order sent.
     *  - 0: Any error, in the shared shape.
     *
     * @param onboardingPicks 
     * @return [OnboardingPicked]
     */
    @POST("v1/onboarding/picks")
    public suspend fun addOnboardingPicks(@Body onboardingPicks: OnboardingPicks): Response<OnboardingPicked>

    /**
     * POST v1/me/recommendations/{id}/add
     * Put the title on your Plan to watch, as a tap would. A title you already have keeps its status. Either way it leaves your recommendations.
     * 
     * Responses:
     *  - 204: Added.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @POST("v1/me/recommendations/{id}/add")
    public suspend fun addRecommendation(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * POST v1/imports/{id}/apply
     * Approve the plan. Writes it as one undoable action.
     * 
     * Responses:
     *  - 200: Applied.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [ImportJob]
     */
    @POST("v1/imports/{id}/apply")
    public suspend fun applyImport(@Path("id") id: java.util.UUID): Response<ImportJob>

    /**
     * POST v1/oauth/requests/{id}/approve
     * Allow the app. Only the browser that started the request holds its binding (the `aaru_oauth` cookie the API set); the answer is where to send the browser next.
     * 
     * Responses:
     *  - 200: Send the browser here.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param approveOAuthRequestRequest 
     * @return [OAuthRedirect]
     */
    @POST("v1/oauth/requests/{id}/approve")
    public suspend fun approveOAuthRequest(@Path("id") id: java.util.UUID, @Body approveOAuthRequestRequest: ApproveOAuthRequestRequest): Response<OAuthRedirect>

    /**
     * POST v1/plans/{id}/approve
     * Apply the plan as one undoable action named after its agent. 409 `plan_stale` when the library changed since it was made (nothing is written), `plan_expired`, or `plan_decided`.
     * 
     * Responses:
     *  - 200: Applied.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [ApprovePlan200Response]
     */
    @POST("v1/plans/{id}/approve")
    public suspend fun approvePlan(@Path("id") id: java.util.UUID): Response<ApprovePlan200Response>

    /**
     * PUT v1/social/blocks/{userId}
     * Block. Ends any friendship and pending requests both ways; from then on each of you is a 404 to the other.
     * 
     * Responses:
     *  - 204: Blocked.
     *  - 0: Any error, in the shared shape.
     *
     * @param userId 
     * @return [Unit]
     */
    @PUT("v1/social/blocks/{userId}")
    public suspend fun blockUser(@Path("userId") userId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/activity/{id}/reaction
     * 
     * 
     * Responses:
     *  - 204: Removed.
     *  - 0: Any error, in the shared shape.
     *
     * @param id An ActivityItem id.
     * @return [Unit]
     */
    @DELETE("v1/activity/{id}/reaction")
    public suspend fun clearActivityReaction(@Path("id") id: kotlin.String): Response<Unit>

    /**
     * DELETE v1/tonight/{id}/feedback
     * Takes back today&#39;s \&quot;Not tonight\&quot; or \&quot;Not for me\&quot; on the item (the Undo after either). Nothing to take back is still 204.
     * 
     * Responses:
     *  - 204: Cleared.
     *  - 0: Any error, in the shared shape.
     *
     * @param id The library item.
     * @param tz IANA time zone for the local day. Absent means UTC. (optional)
     * @return [Unit]
     */
    @DELETE("v1/tonight/{id}/feedback")
    public suspend fun clearTonightFeedback(@Path("id") id: java.util.UUID, @Query("tz") tz: kotlin.String? = null): Response<Unit>

    /**
     * POST v1/connections/mal/connect
     * Start connecting MyAnimeList (PKCE, `plain`, the only method MAL accepts). Open the returned address in a browser. MAL then redirects to GET /v1/connections/mal/callback (a plain redirect route outside this spec), which sends the browser on to `returnTo` with `mal&#x3D;connected|denied|failed`. Once connected, anime progress written from then on is pushed to the MAL list (SCR-005).
     * 
     * Responses:
     *  - 200: Where to send the browser.
     *  - 0: Any error, in the shared shape.
     *
     * @param maLConnectRequest 
     * @return [MALConnectStart]
     */
    @POST("v1/connections/mal/connect")
    public suspend fun connectMAL(@Body maLConnectRequest: MALConnectRequest): Response<MALConnectStart>

    /**
     * POST v1/imports/trakt/connect
     * Start connecting Trakt (PKCE). Open the returned address in a browser. Trakt then redirects to GET /v1/imports/trakt/callback (a plain redirect route outside this spec: its Location must not be percent-encoded), which sends the browser on to `returnTo` with `trakt&#x3D;connected|denied|failed`.
     * 
     * Responses:
     *  - 200: Where to send the browser.
     *  - 0: Any error, in the shared shape.
     *
     * @param traktConnectRequest 
     * @return [TraktConnectStart]
     */
    @POST("v1/imports/trakt/connect")
    public suspend fun connectTrakt(@Body traktConnectRequest: TraktConnectRequest): Response<TraktConnectStart>

    /**
     * POST v1/agent/tokens
     * Mint a token for an outside caller. A Stremio token&#39;s answer carries the addon&#39;s install links; an MCP client&#39;s carries its setup, with the secret filled in. The secret is shown once.
     * 
     * Responses:
     *  - 201: Minted.
     *  - 0: Any error, in the shared shape.
     *
     * @param agentTokenCreate 
     * @return [AgentTokenCreated]
     */
    @POST("v1/agent/tokens")
    public suspend fun createAgentToken(@Body agentTokenCreate: AgentTokenCreate): Response<AgentTokenCreated>

    /**
     * POST v1/imports/anilist
     * Import a public AniList anime and manga list by username. Read and matched in the background, written only after approval.
     * 
     * Responses:
     *  - 202: Queued.
     *  - 0: Any error, in the shared shape.
     *
     * @param createAniListImportRequest 
     * @return [ImportJob]
     */
    @POST("v1/imports/anilist")
    public suspend fun createAniListImport(@Body createAniListImportRequest: CreateAniListImportRequest): Response<ImportJob>

    /**
     * POST v1/board/posts/{postId}/comments
     * Comment on a post. A reply to a reply hangs off the top-level comment. 404 unless the post is yours or a friend&#39;s.
     * 
     * Responses:
     *  - 201: The comment.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @param boardCommentCreate 
     * @return [BoardComment]
     */
    @POST("v1/board/posts/{postId}/comments")
    public suspend fun createBoardComment(@Path("postId") postId: java.util.UUID, @Body boardCommentCreate: BoardCommentCreate): Response<BoardComment>

    /**
     * POST v1/board/posts
     * Post to the Board. Needs a handle.
     * 
     * Responses:
     *  - 201: The post.
     *  - 0: Any error, in the shared shape.
     *
     * @param boardPostCreate 
     * @return [BoardPost]
     */
    @POST("v1/board/posts")
    public suspend fun createBoardPost(@Body boardPostCreate: BoardPostCreate): Response<BoardPost>

    /**
     * POST v1/imports/cat/feed
     * Import shows from the user&#39;s CAT iCal link (https://www.pogdesign.co.uk/cat/download_ics/… or generate_ics/…). The calendar is read once, now; the link holds the user&#39;s CAT key and is not kept.
     * 
     * Responses:
     *  - 202: Queued for matching.
     *  - 0: Any error, in the shared shape.
     *
     * @param createCATFeedImportRequest 
     * @return [ImportJob]
     */
    @POST("v1/imports/cat/feed")
    public suspend fun createCATFeedImport(@Body createCATFeedImportRequest: CreateCATFeedImportRequest): Response<ImportJob>

    /**
     * POST v1/imports/cat
     * Import shows from Pogdesign CAT: a pasted list (one show per line, `Name` or `Name (2026)`) or the exported iCal file. Parsed now, matched in the background, written only after approval. Every show is planned as wishlist; CAT&#39;s watched episodes do not come across.
     * 
     * Responses:
     *  - 202: Queued for matching.
     *  - 0: Any error, in the shared shape.
     *
     * @param body 
     * @return [ImportJob]
     */
    @POST("v1/imports/cat")
    public suspend fun createCATImport(@Body body: java.io.File): Response<ImportJob>


    /**
    * enum for parameter source
    */
    public enum class SourceCreateCSVImport(public val value: kotlin.String) {
        @SerialName(value = "auto") auto("auto"),
        @SerialName(value = "imdb") imdb("imdb"),
        @SerialName(value = "letterboxd") letterboxd("letterboxd"),
        @SerialName(value = "netflix") netflix("netflix"),
        @SerialName(value = "tvtime") tvtime("tvtime"),
        @SerialName(value = "goodreads") goodreads("goodreads"),
        @SerialName(value = "mal") mal("mal"),
        @SerialName(value = "csv") csv("csv"),
        @SerialName(value = "spotify") spotify("spotify"),
        @SerialName(value = "youtube") youtube("youtube")
    }

    /**
     * POST v1/imports/csv
     * Upload an export file. It is parsed now, matched in the background, and written only after approval.
     * 
     * Responses:
     *  - 202: Queued for matching.
     *  - 0: Any error, in the shared shape.
     *
     * @param source `auto` detects the format: MyAnimeList-format XML, anime or manga (also exported by Kitsu and AniList), an IMDb, Letterboxd, Netflix viewing activity, TV Time or Goodreads CSV, or any other CSV read by its column names (`csv`); for an `application/octet-stream` body, Spotify&#39;s extended streaming history or Google Takeout&#39;s YouTube watch history. `spotify` and `youtube` are listening history (MUS-004): their plays go to the listening log, never the library, and the job&#39;s stats count new listens (`created`), listens already in the log (`skipped`) and plays left out (`ignored`). `tvtime` takes one CSV from TV Time&#39;s export at a time: `tvtime-series-episodes.csv`, `tvtime-series.csv` or `tvtime-movies.csv` (Export my data), or `tracking-prod-records-v2.csv`, `tracking-prod-records.csv`, `followed_tv_show.csv` or `seen_episode.csv` (GDPR export).
     * @param body 
     * @param filename The file&#39;s name. Letterboxd&#39;s watchlist export is told apart by it. (optional)
     * @return [ImportJob]
     */
    @POST("v1/imports/csv")
    public suspend fun createCSVImport(@Query("source") source: SourceCreateCSVImport, @Body body: java.io.File, @Query("filename") filename: kotlin.String? = null): Response<ImportJob>


    /**
    * enum for parameter kind
    */
    public enum class KindCreateCaptureImport(public val value: kotlin.String) {
        @SerialName(value = "book") book("book")
    }

    /**
     * POST v1/imports/capture
     * Capture (AG-006): pasted text, up to five images, or a link to a title on TMDB, AniList or Open Library, planned like any import and written only after approval. Links are read from the URL alone, never fetched. Text and images are read by Aaru&#39;s model in the background and deleted once read. An account starts 30 captures a UTC day; the next is refused with 429 `capture_fair_use`. Letterboxd and IMDb links are refused with `capture_use_csv`, other links with `capture_unsupported_url`; more than five images with `capture_too_many_images`; `capture_unavailable` (503) means no model is configured.
     * 
     * Responses:
     *  - 202: Queued for reading and matching.
     *  - 0: Any error, in the shared shape.
     *
     * @param createCaptureImportRequest 
     * @param kind Read this kind only (BOOK-001). A link names its own kind. (optional)
     * @return [ImportJob]
     */
    @POST("v1/imports/capture")
    public suspend fun createCaptureImport(@Body createCaptureImportRequest: CreateCaptureImportRequest, @Query("kind") kind: KindCreateCaptureImport? = null): Response<ImportJob>

    /**
     * POST v1/groups/{groupId}/channels
     * Add a text channel. Owner and admins.
     * 
     * Responses:
     *  - 200: The channel.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelCreate 
     * @return [Channel]
     */
    @POST("v1/groups/{groupId}/channels")
    public suspend fun createChannel(@Path("groupId") groupId: java.util.UUID, @Body channelCreate: ChannelCreate): Response<Channel>

    /**
     * POST v1/chats
     * Start a Chat with Aaru (ASK-009), a one-to-one thread only its user can read.
     * 
     * Responses:
     *  - 201: The new chat.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ChatCreated]
     */
    @POST("v1/chats")
    public suspend fun createChat(): Response<ChatCreated>

    /**
     * POST v1/chats/{id}/attachments
     * Attach one file to a chat (ASK-010), for the next turn to carry by id. The body is the file itself, sent with its own Content-Type (application/octet-stream when unknown); the server reads its bytes, not its name or type, to decide what it is. Pictures (JPEG, PNG, GIF, WebP, 5 MB), PDFs (10 MB, 100 pages, no encryption or active content), text and Markdown, the import exports (CSV, MAL XML or .xml.gz, iCal; 5 MB) and listening histories (JSON, 24 MB). Anything else, a program, an archive, or a file whose name disagrees with its bytes, is 422 `validation_failed` with the reason. 413 `file_too_large`, 404 for a chat that is not the caller&#39;s, 409 `chat_attachments_full` past 20 files in a chat, 429 `rate_limited` past 40 files an hour. A file is kept for an hour, then deleted.
     * 
     * Responses:
     *  - 201: The file, as the chat will use it.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param body 
     * @param filename The file&#39;s name, shown on its chip and checked against its bytes. Empty for pasted text. (optional)
     * @return [ChatAttachment]
     */
    @POST("v1/chats/{id}/attachments")
    public suspend fun createChatAttachment(@Path("id") id: java.util.UUID, @Body body: java.io.File, @Query("filename") filename: kotlin.String? = null): Response<ChatAttachment>

    /**
     * POST v1/chats/{id}/turns
     * Ask Aaru (ASK-009). The answer is a stream of server-sent events, each frame an `event:` line with its type and a `data:` line with JSON: `status` and `delta` carry ChatTextFrame, `components` ChatComponentsFrame, `done` ChatDoneFrame, `error` ChatErrorFrame. Lines starting with `:` are heartbeats. Once the stream has begun, a failure can only be an `error` frame: a send past the daily cap is a 200 with one `error` frame, code `resting`. Before it begins: 404 for a chat that is not the caller&#39;s, 409 `chat_busy` while the chat is still answering, 422 for a body that is over 4000 characters or blank with no attachments, 422 `attachment_gone` when an attachment is no longer kept, 503 `agent_unavailable` when Aaru is off. Hanging up stops the turn and keeps what was written.
     * 
     * Responses:
     *  - 200: The answer, as it is written.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param chatTurnRequest 
     * @return [ResponseBody]
     */
    @POST("v1/chats/{id}/turns")
    public suspend fun createChatTurn(@Path("id") id: java.util.UUID, @Body chatTurnRequest: ChatTurnRequest): Response<ResponseBody>

    /**
     * POST v1/social/invites
     * Make a one-use invite link, live for 14 days, optionally carrying a title to watch together. Needs your own handle; at most 20 open at once.
     * 
     * Responses:
     *  - 200: The new link.
     *  - 0: Any error, in the shared shape.
     *
     * @param friendInviteCreate 
     * @return [FriendInvite]
     */
    @POST("v1/social/invites")
    public suspend fun createFriendInvite(@Body friendInviteCreate: FriendInviteCreate): Response<FriendInvite>

    /**
     * POST v1/groups
     * Create a group you own, with a
     * 
     * Responses:
     *  - 200: The new group.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupCreate 
     * @return [GroupDetail]
     */
    @POST("v1/groups")
    public suspend fun createGroup(@Body groupCreate: GroupCreate): Response<GroupDetail>

    /**
     * POST v1/imports/lastfm
     * Import a Last.fm account&#39;s scrobbles by username (MUS-004). Read in the background into the listening log, written only after approval. A second import of the same account reads only what came after the last one. 503 `lastfm_unavailable` when the server has no Last.fm key.
     * 
     * Responses:
     *  - 202: Queued.
     *  - 0: Any error, in the shared shape.
     *
     * @param listenAccount 
     * @return [ImportJob]
     */
    @POST("v1/imports/lastfm")
    public suspend fun createLastFMImport(@Body listenAccount: ListenAccount): Response<ImportJob>

    /**
     * POST v1/lists
     * 
     * 
     * Responses:
     *  - 200: The new list.
     *  - 0: Any error, in the shared shape.
     *
     * @param createList 
     * @return [ListDetail]
     */
    @POST("v1/lists")
    public suspend fun createList(@Body createList: CreateList): Response<ListDetail>

    /**
     * POST v1/imports/listenbrainz
     * Import a ListenBrainz account&#39;s listens by username (MUS-004). Read in the background into the listening log, written only after approval. A second import of the same account reads only what came after the last one.
     * 
     * Responses:
     *  - 202: Queued.
     *  - 0: Any error, in the shared shape.
     *
     * @param listenAccount 
     * @return [ImportJob]
     */
    @POST("v1/imports/listenbrainz")
    public suspend fun createListenBrainzImport(@Body listenAccount: ListenAccount): Response<ImportJob>

    /**
     * POST v1/realtime/ticket
     * A single-use ticket, valid 60 seconds, for opening the realtime socket from a browser, which cannot send an Authorization header on a WebSocket. Apps send their bearer token on the upgrade instead.
     * 
     * Responses:
     *  - 200: The ticket and the socket URL to open with it.
     *  - 0: Any error, in the shared shape.
     *
     * @return [RealtimeTicket]
     */
    @POST("v1/realtime/ticket")
    public suspend fun createRealtimeTicket(): Response<RealtimeTicket>

    /**
     * POST v1/shares
     * Make a share link to one title, sport event or concert (SHR-002). Public and reusable, it never expires. The same target with the same note gives back the same link; a different note makes a new one. At most 60 an hour.
     * 
     * Responses:
     *  - 200: The link.
     *  - 0: Any error, in the shared shape.
     *
     * @param shareCreate 
     * @return [ShareLink]
     */
    @POST("v1/shares")
    public suspend fun createShare(@Body shareCreate: ShareCreate): Response<ShareLink>

    /**
     * POST v1/shelves
     * 
     * 
     * Responses:
     *  - 200: The new shelf.
     *  - 0: Any error, in the shared shape.
     *
     * @param createShelf 
     * @return [Shelf]
     */
    @POST("v1/shelves")
    public suspend fun createShelf(@Body createShelf: CreateShelf): Response<Shelf>

    /**
     * POST v1/imports/trakt
     * Import the connected Trakt account. Read and matched in the background, written only after approval.
     * 
     * Responses:
     *  - 202: Queued.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ImportJob]
     */
    @POST("v1/imports/trakt")
    public suspend fun createTraktImport(): Response<ImportJob>

    /**
     * DELETE v1/group-invites/{id}
     * Decline an invite to you, or cancel one you sent.
     * 
     * Responses:
     *  - 204: Gone.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/group-invites/{id}")
    public suspend fun declineGroupInvite(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/me
     * Delete the account and everything that belongs to it. Only a session created in the last 10 minutes may do it; an older one gets 403 `reauth_required` and the user signs in again first.
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 403: The session is older than 10 minutes (`reauth_required`). Nothing was deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/me")
    public suspend fun deleteAccount(): Response<Unit>

    /**
     * DELETE v1/me/avatar
     * Remove your avatar. Your monogram shows again everywhere.
     * 
     * Responses:
     *  - 200: Your account, without `avatarUrl`.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Me]
     */
    @DELETE("v1/me/avatar")
    public suspend fun deleteAvatar(): Response<Me>

    /**
     * DELETE v1/board/posts/{postId}/comments/{commentId}
     * Delete a comment. Its author or the post&#39;s author can.
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @param commentId 
     * @return [Unit]
     */
    @DELETE("v1/board/posts/{postId}/comments/{commentId}")
    public suspend fun deleteBoardComment(@Path("postId") postId: java.util.UUID, @Path("commentId") commentId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/board/posts/{postId}
     * Delete your own post.
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @return [Unit]
     */
    @DELETE("v1/board/posts/{postId}")
    public suspend fun deleteBoardPost(@Path("postId") postId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/groups/{groupId}/channels/{channelId}
     * Delete a channel and its messages. The first channel stays. Owner and admins.
     * 
     * Responses:
     *  - 204: Gone.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @return [Unit]
     */
    @DELETE("v1/groups/{groupId}/channels/{channelId}")
    public suspend fun deleteChannel(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/chats/{id}
     * Delete one of the caller&#39;s chats, its turns and files with it (ASK-011).
     * 
     * Responses:
     *  - 204: Deleted, or already gone.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/chats/{id}")
    public suspend fun deleteChat(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/chats/{id}/attachments/{attachmentId}
     * Remove a file from a chat before it is sent, or after (ASK-010).
     * 
     * Responses:
     *  - 204: Removed, or already gone.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param attachmentId 
     * @return [Unit]
     */
    @DELETE("v1/chats/{id}/attachments/{attachmentId}")
    public suspend fun deleteChatAttachment(@Path("id") id: java.util.UUID, @Path("attachmentId") attachmentId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/chats
     * Delete all of the caller&#39;s chats with Aaru, their turns with them.
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/chats")
    public suspend fun deleteChats(): Response<Unit>

    /**
     * DELETE v1/me/concert-place
     * Forgets the \&quot;Concerts near\&quot; city.
     * 
     * Responses:
     *  - 204: Removed, or there was none.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/me/concert-place")
    public suspend fun deleteConcertPlace(): Response<Unit>

    /**
     * DELETE v1/groups/{groupId}
     * Delete the group, its channels and every message. Owner only.
     * 
     * Responses:
     *  - 204: Gone.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @return [Unit]
     */
    @DELETE("v1/groups/{groupId}")
    public suspend fun deleteGroup(@Path("groupId") groupId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/imports/{id}
     * Discard an import. Library items it already created stay; undo the import action for those.
     * 
     * Responses:
     *  - 204: Discarded.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/imports/{id}")
    public suspend fun deleteImport(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/library/items/{id}
     * 
     * 
     * Responses:
     *  - 204: Removed.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/library/items/{id}")
    public suspend fun deleteLibraryItem(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/lists/{id}
     * 
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/lists/{id}")
    public suspend fun deleteList(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/groups/{groupId}/channels/{channelId}/messages/{messageId}
     * Delete your message, or any message as owner or admin. The row stays, empty.
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param messageId 
     * @return [Unit]
     */
    @DELETE("v1/groups/{groupId}/channels/{channelId}/messages/{messageId}")
    public suspend fun deleteMessage(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Path("messageId") messageId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/shelves/{id}
     * 
     * 
     * Responses:
     *  - 204: Deleted.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/shelves/{id}")
    public suspend fun deleteShelf(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/web-push/subscriptions
     * 
     * 
     * Responses:
     *  - 204: Forgotten.
     *  - 0: Any error, in the shared shape.
     *
     * @param endpoint 
     * @return [Unit]
     */
    @DELETE("v1/web-push/subscriptions")
    public suspend fun deleteWebPushSubscription(@Query("endpoint") endpoint: kotlin.String): Response<Unit>

    /**
     * POST v1/oauth/requests/{id}/deny
     * 
     * 
     * Responses:
     *  - 200: Send the browser here.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param denyOAuthRequestRequest 
     * @return [OAuthRedirect]
     */
    @POST("v1/oauth/requests/{id}/deny")
    public suspend fun denyOAuthRequest(@Path("id") id: java.util.UUID, @Body denyOAuthRequestRequest: DenyOAuthRequestRequest): Response<OAuthRedirect>

    /**
     * POST v1/plans/{id}/deny
     * Refuse the plan. Nothing is written; the plan stays as the record of what was asked.
     * 
     * Responses:
     *  - 200: Denied.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [AgentPlan]
     */
    @POST("v1/plans/{id}/deny")
    public suspend fun denyPlan(@Path("id") id: java.util.UUID): Response<AgentPlan>

    /**
     * DELETE v1/connections/mal
     * Forget the MyAnimeList tokens. Nothing more is pushed; the MAL list and the library stay as they are.
     * 
     * Responses:
     *  - 204: Disconnected.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/connections/mal")
    public suspend fun disconnectMAL(): Response<Unit>

    /**
     * DELETE v1/imports/trakt/connection
     * Revoke the Trakt tokens on Trakt, then forget them. Imported items stay.
     * 
     * Responses:
     *  - 204: Disconnected.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/imports/trakt/connection")
    public suspend fun disconnectTrakt(): Response<Unit>

    /**
     * DELETE v1/me/recommendations/{id}
     * 
     * 
     * Responses:
     *  - 204: Dismissed.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/me/recommendations/{id}")
    public suspend fun dismissRecommendation(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * PATCH v1/board/posts/{postId}
     * Edit your own post.
     * 
     * Responses:
     *  - 200: The post.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @param boardPostEdit 
     * @return [BoardPost]
     */
    @PATCH("v1/board/posts/{postId}")
    public suspend fun editBoardPost(@Path("postId") postId: java.util.UUID, @Body boardPostEdit: BoardPostEdit): Response<BoardPost>

    /**
     * PATCH v1/groups/{groupId}/channels/{channelId}/messages/{messageId}
     * Edit your own message.
     * 
     * Responses:
     *  - 200: The message.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param messageId 
     * @param messageUpdate 
     * @return [GroupMessage]
     */
    @PATCH("v1/groups/{groupId}/channels/{channelId}/messages/{messageId}")
    public suspend fun editMessage(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Path("messageId") messageId: java.util.UUID, @Body messageUpdate: MessageUpdate): Response<GroupMessage>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/party/end
     * End the party. The host or an admin. If the countdown had started, the title is marked for every member who joined and left autoMark on, as their own undoable action.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @return [WatchPartyView]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/party/end")
    public suspend fun endWatchParty(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID): Response<WatchPartyView>


    /**
    * enum for parameter format
    */
    public enum class FormatExportAccount(public val value: kotlin.String) {
        @SerialName(value = "json") json("json"),
        @SerialName(value = "csv") csv("csv")
    }

    /**
     * GET v1/me/export
     * Everything Aaru holds for the caller, to keep or move elsewhere (GDPR portability).
     * `json` (default) is complete: account, every library item with ratings, notes and every watched episode, lists and shelves. `csv` is one row per library item in the column layout Aaru&#39;s own \&quot;Any site\&quot; import reads, so it can be re-imported here or opened in a spreadsheet.
     * Responses:
     *  - 200: The export, as a download.
     *  - 0: Any error, in the shared shape.
     *
     * @param format  (optional, default to json)
     * @return [AccountExport]
     */
    @GET("v1/me/export")
    public suspend fun exportAccount(@Query("format") format: FormatExportAccount? = FormatExportAccount.json): Response<AccountExport>

    /**
     * PUT v1/me/onboarding
     * End the first-run flow (ONB-001), finished or skipped. The first call wins; later calls change nothing. What the flow already saved stays.
     * 
     * Responses:
     *  - 204: Onboarding is over for this account.
     *  - 0: Any error, in the shared shape.
     *
     * @param onboardingFinish 
     * @return [Unit]
     */
    @PUT("v1/me/onboarding")
    public suspend fun finishOnboarding(@Body onboardingFinish: OnboardingFinish): Response<Unit>

    /**
     * PUT v1/me/sport-follows/{kind}/{providerId}
     * Follows a league, team or player by the sports provider&#39;s id. Idempotent.
     * Sports only: never a library write, never journaled, never shown to friends. 404 when the provider does not know the id, 409 `too_many_follows` past 100, 503 when Sports are off.
     * Responses:
     *  - 200: Followed.
     *  - 0: Any error, in the shared shape.
     *
     * @param kind 
     * @param providerId 
     * @return [SportEntity]
     */
    @PUT("v1/me/sport-follows/{kind}/{providerId}")
    public suspend fun followSport(@Path("kind") kind: SportEntityKind, @Path("providerId") providerId: kotlin.String): Response<SportEntity>

    /**
     * GET v1/agent/setup/{kind}
     * How to connect one MCP client (OUT-004), with a placeholder where the secret goes, so Settings can show the steps before a token exists.
     * 
     * Responses:
     *  - 200: The client's setup.
     *  - 0: Any error, in the shared shape.
     *
     * @param kind 
     * @return [AgentSetup]
     */
    @GET("v1/agent/setup/{kind}")
    public suspend fun getAgentSetup(@Path("kind") kind: AgentMCPKind): Response<AgentSetup>

    /**
     * GET v1/concerts/artists
     * Upcoming concerts by the artists of the user&#39;s albums (MUS-003).
     * Derived from the user&#39;s own library, like the calendar; dropped albums aside. An artist counts only when Ticketmaster lists them with the same MusicBrainz id. Artists added in the last hour may still be `pending`.
     * Responses:
     *  - 200: The concerts.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ArtistConcerts]
     */
    @GET("v1/concerts/artists")
    public suspend fun getArtistConcerts(): Response<ArtistConcerts>

    /**
     * GET v1/board/posts/{postId}
     * One post. 404 unless it is yours or a friend&#39;s.
     * 
     * Responses:
     *  - 200: The post.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @return [BoardPost]
     */
    @GET("v1/board/posts/{postId}")
    public suspend fun getBoardPost(@Path("postId") postId: java.util.UUID): Response<BoardPost>

    /**
     * GET v1/calendar
     * Episodes of tracked shows airing in [from, to), at most 42 days (a month grid). Times are UTC.
     * 
     * Responses:
     *  - 200: Episodes, by air time.
     *  - 0: Any error, in the shared shape.
     *
     * @param from 
     * @param to 
     * @return [Calendar]
     */
    @GET("v1/calendar")
    public suspend fun getCalendar(@Query("from") from: java.time.OffsetDateTime, @Query("to") to: java.time.OffsetDateTime): Response<Calendar>

    /**
     * GET v1/groups/{groupId}/channels/{channelId}/progress
     * A title channel&#39;s title, your progress, and the progress of members who share theirs in this group.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @return [ChannelProgress]
     */
    @GET("v1/groups/{groupId}/channels/{channelId}/progress")
    public suspend fun getChannelProgress(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID): Response<ChannelProgress>

    /**
     * GET v1/chats/{id}
     * One chat with its turns, oldest first, so it can be read again and continued (ASK-011). The latest 200 turns. 404 for a chat that is not the caller&#39;s.
     * 
     * Responses:
     *  - 200: The chat.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Chat]
     */
    @GET("v1/chats/{id}")
    public suspend fun getChat(@Path("id") id: java.util.UUID): Response<Chat>

    /**
     * GET v1/chats/status
     * Whether Aaru and voice are on, so clients hide the owl and the mic when the server has them off.
     * 
     * Responses:
     *  - 200: What is on.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ChatStatus]
     */
    @GET("v1/chats/status")
    public suspend fun getChatStatus(): Response<ChatStatus>

    /**
     * GET v1/me/concert-place
     * The saved \&quot;Concerts near\&quot; city, and whether concerts are on at all.
     * 
     * Responses:
     *  - 200: The setting.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ConcertPlaceSetting]
     */
    @GET("v1/me/concert-place")
    public suspend fun getConcertPlace(): Response<ConcertPlaceSetting>

    /**
     * POST v1/concerts/near
     * Music events around a point or the saved \&quot;Concerts near\&quot; city (MUS-003), soonest first.
     * POST so a position never sits in a URL. Coordinates are rounded to two decimals (about a kilometre) and used for this request only: never stored, never logged. With no coordinates the saved city is the centre; with neither, 409 `no_place`. The same list for everyone in the same area, cached by the server and linked out to Ticketmaster for tickets.
     * Responses:
     *  - 200: The page. `unavailable` when concerts are off or the provider is down.
     *  - 0: Any error, in the shared shape.
     *
     * @param concertsNearRequest 
     * @return [ConcertPage]
     */
    @POST("v1/concerts/near")
    public suspend fun getConcertsNear(@Body concertsNearRequest: ConcertsNearRequest): Response<ConcertPage>

    /**
     * GET v1/discover
     * Provider-curated public rows for Home (trending, airing, this season).
     * The same lists for every user, cached by the server. Items the caller already has carry `libraryItemId`. A row whose provider is down is left out.
     * Responses:
     *  - 200: Rows in display order. Empty rows are left out.
     *  - 0: Any error, in the shared shape.
     *
     * @return [DiscoverRows]
     */
    @GET("v1/discover")
    public suspend fun getDiscover(): Response<DiscoverRows>

    /**
     * GET v1/discover/on-air
     * Shows airing this week, grouped by channel or streamer (DISC-003).
     * TMDB&#39;s on-the-air shows, the same for every user and cached by the server, each with its next episode and the channel it premieres on. `airsAt` is the exact instant when `airTimeKnown` (from TVmaze), else the UTC day: show the date only. Channels with the most shows come first, \&quot;Other\&quot; (no known channel) last. With `region`, each show also lists the services it streams on there (JustWatch data through TMDB; credit JustWatch where shown). Items the caller has carry `libraryItemId`. Empty `channels` when the provider is down and nothing is cached.
     * Responses:
     *  - 200: The guide.
     *  - 0: Any error, in the shared shape.
     *
     * @param region ISO 3166-1 alpha-2, e.g. `US`, `PT`, from the device&#39;s language settings. Used for this request only and never stored. Anything but two letters is 422 `validation_failed`. (optional)
     * @return [DiscoverOnAir]
     */
    @GET("v1/discover/on-air")
    public suspend fun getDiscoverOnAir(@Query("region") region: kotlin.String? = null): Response<DiscoverOnAir>


    /**
    * enum for parameter kind
    */
    public enum class KindGetDiscoverSeason(public val value: kotlin.String) {
        @SerialName(value = "anime") anime("anime"),
        @SerialName(value = "shows_new") showsNew("shows_new"),
        @SerialName(value = "shows_returning") showsReturning("shows_returning"),
        @SerialName(value = "movies") movies("movies")
    }


    /**
    * enum for parameter season
    */
    public enum class SeasonGetDiscoverSeason(public val value: kotlin.String) {
        @SerialName(value = "winter") winter("winter"),
        @SerialName(value = "spring") spring("spring"),
        @SerialName(value = "summer") summer("summer"),
        @SerialName(value = "fall") fall("fall")
    }

    /**
     * GET v1/discover/season
     * One season&#39;s titles for the Seasons view (DISC-002), a page at a time.
     * A season is a calendar quarter in UTC: winter Jan–Mar, spring Apr–Jun, summer Jul–Sep, fall Oct–Dec. Anime by AniList&#39;s broadcast season, new shows by first air date, returning shows by an episode airing that season, films by first release. The same lists for every user, cached by the server; items the caller has carry `libraryItemId`.
     * Responses:
     *  - 200: The page. `unavailable` when the provider is down and nothing is cached.
     *  - 0: Any error, in the shared shape.
     *
     * @param kind 
     * @param season 
     * @param year 1970 to next year; anything else is 422 `validation_failed`.
     * @param page 1-based, at most 20. (optional, default to 1)
     * @return [SeasonPage]
     */
    @GET("v1/discover/season")
    public suspend fun getDiscoverSeason(@Query("kind") kind: KindGetDiscoverSeason, @Query("season") season: SeasonGetDiscoverSeason, @Query("year") year: kotlin.Int, @Query("page") page: kotlin.Int? = 1): Response<SeasonPage>

    /**
     * GET v1/me/entitlement
     * Aaru Plus and this month&#39;s captures (BIL-001). The same on every client; Plus is bought in the Apple apps only.
     * 
     * Responses:
     *  - 200: The account's entitlement.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Entitlement]
     */
    @GET("v1/me/entitlement")
    public suspend fun getEntitlement(): Response<Entitlement>

    /**
     * GET v1/social/friends/{userId}/profile
     * A friend&#39;s shelves and what you share. 404 for anyone who is not your friend. A friend who hides their library shows only their name (`sharing` false).
     * 
     * Responses:
     *  - 200: The profile.
     *  - 0: Any error, in the shared shape.
     *
     * @param userId 
     * @return [FriendProfile]
     */
    @GET("v1/social/friends/{userId}/profile")
    public suspend fun getFriendProfile(@Path("userId") userId: java.util.UUID): Response<FriendProfile>

    /**
     * GET v1/groups/{groupId}
     * A group you are in, with its channels, members and pending invites. 404 to anyone else.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @return [GroupDetail]
     */
    @GET("v1/groups/{groupId}")
    public suspend fun getGroup(@Path("groupId") groupId: java.util.UUID): Response<GroupDetail>

    /**
     * GET v1/health
     * Liveness and database reachability. Unauthenticated.
     * 
     * Responses:
     *  - 200: The server is up and can reach its database.
     *  - 503: The server is up but a dependency is not reachable.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Health]
     */
    @GET("v1/health")
    public suspend fun getHealth(): Response<Health>

    /**
     * GET v1/imports/{id}
     * One import with every row and what its plan does with it.
     * 
     * Responses:
     *  - 200: The import.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [ImportDetail]
     */
    @GET("v1/imports/{id}")
    public suspend fun getImport(@Path("id") id: java.util.UUID): Response<ImportDetail>

    /**
     * GET v1/invites/{code}
     * What an invite link shows, signed in or not. Unauthenticated. 404 for any code that is unknown, spent, revoked, expired, or from someone who blocked you or whom you blocked.
     * 
     * Responses:
     *  - 200: Who sent it and the title it carries.
     *  - 0: Any error, in the shared shape.
     *
     * @param code 
     * @return [InvitePreview]
     */
    @GET("v1/invites/{code}")
    public suspend fun getInvitePreview(@Path("code") code: kotlin.String): Response<InvitePreview>

    /**
     * GET v1/social/leaderboard
     * The weekly friends board (GAM-005): you and friends who joined it, by points earned that week on each person&#39;s own local dates. Making friends and a first import do not count. Until you join (`leaderboardOptIn`), `optedIn` is false and nobody is listed. Never global.
     * 
     * Responses:
     *  - 200: The board.
     *  - 0: Any error, in the shared shape.
     *
     * @param week An ISO week such as `2026-W43`. Absent means this week in your zone. (optional)
     * @return [Leaderboard]
     */
    @GET("v1/social/leaderboard")
    public suspend fun getLeaderboard(@Query("week") week: kotlin.String? = null): Response<Leaderboard>

    /**
     * GET v1/library/items/{id}
     * 
     * 
     * Responses:
     *  - 200: The item.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [LibraryEntry]
     */
    @GET("v1/library/items/{id}")
    public suspend fun getLibraryItem(@Path("id") id: java.util.UUID): Response<LibraryEntry>

    /**
     * GET v1/lists/{id}
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [ListDetail]
     */
    @GET("v1/lists/{id}")
    public suspend fun getList(@Path("id") id: java.util.UUID): Response<ListDetail>

    /**
     * GET v1/lists/{id}/graph
     * The list drawn as a graph (GRAPH-004), in the relation graph&#39;s shape: its steps left to right (a column per title), titles read side by side in one column, optional titles hanging under the title before them off the main chain, and \&quot;Start here\&quot; on the first main-chain title not finished or dropped. A plain list is its titles in order.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [RelationGraph]
     */
    @GET("v1/lists/{id}/graph")
    public suspend fun getListGraph(@Path("id") id: java.util.UUID): Response<RelationGraph>

    /**
     * GET v1/connections/mal
     * 
     * 
     * Responses:
     *  - 200: Whether MyAnimeList is connected, and whether it must be connected again.
     *  - 0: Any error, in the shared shape.
     *
     * @return [MALConnection]
     */
    @GET("v1/connections/mal")
    public suspend fun getMALConnection(): Response<MALConnection>

    /**
     * GET v1/me
     * The signed-in account.
     * 
     * Responses:
     *  - 200: The account.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Me]
     */
    @GET("v1/me")
    public suspend fun getMe(): Response<Me>

    /**
     * GET v1/me/favorites
     * Your favorites, an ordered top 10 per kind (FAV-001). Profile data, not your library.
     * 
     * Responses:
     *  - 200: Every kind, each in your order; an empty list for a kind with none.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Favorites]
     */
    @GET("v1/me/favorites")
    public suspend fun getMyFavorites(): Response<Favorites>

    /**
     * GET v1/me/notifications
     * 
     * 
     * Responses:
     *  - 200: The user's notification choices.
     *  - 0: Any error, in the shared shape.
     *
     * @return [NotificationSettings]
     */
    @GET("v1/me/notifications")
    public suspend fun getNotificationSettings(): Response<NotificationSettings>

    /**
     * GET v1/me/now-playing
     * What players are playing for you now: Stremio and streaming sites through the browser extension (SCR-008), a music scrobbler&#39;s `playing_now` and YouTube videos (SCR-009). `positionMs` is where a player was at `updatedAt`; a client adds the time since while `state` is `playing`. A report too old to believe no longer counts.
     * 
     * Responses:
     *  - 200: What plays, if anything.
     *  - 0: Any error, in the shared shape.
     *
     * @return [NowPlayingReply]
     */
    @GET("v1/me/now-playing")
    public suspend fun getNowPlaying(): Response<NowPlayingReply>

    /**
     * GET v1/oauth/requests/{id}
     * A connection an app asked for over OAuth (Claude&#39;s custom connector), for the consent page. Expires ten minutes after the app asked.
     * 
     * Responses:
     *  - 200: The request.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [OAuthConsentRequest]
     */
    @GET("v1/oauth/requests/{id}")
    public suspend fun getOAuthRequest(@Path("id") id: java.util.UUID): Response<OAuthConsentRequest>

    /**
     * POST v1/onboarding/related
     * Titles related to the ones picked (ONB-001): prequels, sequels, side stories, spin-offs, adaptations and sources from each title&#39;s relation graph (GRAPH-001).
     * Catalog data joined by id, never a recommendation: nothing is read from other users and nothing is ranked by taste. Titles already in the caller&#39;s library are left out, each title once under the first pick it relates to, at most 30 shared across the picks in turn so one long franchise cannot fill them, grouped by pick in the order the picks were sent. Graphs not cached yet get a few seconds; `partial` says some were cut short (they keep loading for the next call).
     * Responses:
     *  - 200: The related titles.
     *  - 0: Any error, in the shared shape.
     *
     * @param onboardingRelatedRequest 
     * @return [OnboardingRelated]
     */
    @POST("v1/onboarding/related")
    public suspend fun getOnboardingRelated(@Body onboardingRelatedRequest: OnboardingRelatedRequest): Response<OnboardingRelated>

    /**
     * GET v1/onboarding/rows
     * Rows of well-known titles of one kind to pick from in the first-run flow (ONB-001).
     * Popular first, then rows by genre (by subject for books). Catalog data, the same for every user and cached by the server; items the caller has carry `libraryItemId`. A row whose provider is down is left out; manga has none while AniList is down, and anime comes from TMDB&#39;s Japanese animation then, with a `note`.
     * Responses:
     *  - 200: Rows in display order. Empty rows are left out.
     *  - 0: Any error, in the shared shape.
     *
     * @param kind 
     * @return [DiscoverRows]
     */
    @GET("v1/onboarding/rows")
    public suspend fun getOnboardingRows(@Query("kind") kind: DiscoverRowKind): Response<DiscoverRows>

    /**
     * GET v1/plans/{id}
     * 
     * 
     * Responses:
     *  - 200: The plan.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [AgentPlan]
     */
    @GET("v1/plans/{id}")
    public suspend fun getPlan(@Path("id") id: java.util.UUID): Response<AgentPlan>

    /**
     * GET v1/me/profile/stats
     * All-time numbers for the profile (GAM-006b), from the library as it is: every ticked episode counts, imported and undated ones too, so these can exceed `/v1/me/stats?span&#x3D;all`, which counts dated activity only.
     * 
     * Responses:
     *  - 200: The profile's stats.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ProfileStats]
     */
    @GET("v1/me/profile/stats")
    public suspend fun getProfileStats(): Response<ProfileStats>

    /**
     * GET v1/me/progress
     * Your points, level, streak and the badges you have not seen yet (GAM-001…004). Days are counted in the zone from `X-Timezone`, else the zone you last sent, else UTC. Clients read this after a write to show what was earned: one toast for a live unlock, one summary when `unseen.origin` is `batch` (an import or approved plan) or `backfill` (the first run).
     * 
     * Responses:
     *  - 200: Your progress.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Progress]
     */
    @GET("v1/me/progress")
    public suspend fun getProgress(): Response<Progress>

    /**
     * GET v1/shares/{code}
     * What a share link shows, signed in or not. Unauthenticated. The content shows to anyone; who sent it and the note show only to the sender and their friends, never across a block. 404 for an unknown code.
     * 
     * Responses:
     *  - 200: The shared content.
     *  - 0: Any error, in the shared shape.
     *
     * @param code 
     * @return [SharePreview]
     */
    @GET("v1/shares/{code}")
    public suspend fun getSharePreview(@Path("code") code: kotlin.String): Response<SharePreview>

    /**
     * GET v1/me/social-settings
     * What your friends may see. Strangers never see anything, whatever is set here.
     * 
     * Responses:
     *  - 200: Your settings.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SocialSettings]
     */
    @GET("v1/me/social-settings")
    public suspend fun getSocialSettings(): Response<SocialSettings>

    /**
     * GET v1/social/users/{handle}
     * The user with exactly this handle and where they stand with you. 404 when nobody holds it or either of you blocked the other. A friend or yourself is free; anyone else, misses included, at most 60 a user per hour (429).
     * 
     * Responses:
     *  - 200: The user.
     *  - 0: Any error, in the shared shape.
     *
     * @param handle 
     * @return [SocialUserView]
     */
    @GET("v1/social/users/{handle}")
    public suspend fun getSocialUser(@Path("handle") handle: kotlin.String): Response<SocialUserView>

    /**
     * GET v1/sports/events/{id}
     * One event with its live line and where to watch it (SPT-002, SPT-005).
     * 
     * Responses:
     *  - 200: The event.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [SportEventDetail]
     */
    @GET("v1/sports/events/{id}")
    public suspend fun getSportEvent(@Path("id") id: kotlin.String): Response<SportEventDetail>

    /**
     * GET v1/sports/favorites
     * Each followed league, team and player with what is live, next and last (SPT-002).
     * Near-live: scores refresh about every two minutes for football, NFL, NBA, MLB and NHL. UFC and WWE cards have results, not live scores. Entries still being fetched come back `pending`; ask again in a few seconds.
     * Responses:
     *  - 200: The favorites, in follow order.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SportFavorites]
     */
    @GET("v1/sports/favorites")
    public suspend fun getSportFavorites(): Response<SportFavorites>

    /**
     * GET v1/sports/schedule
     * One day of events for the leagues the user follows, favorites highlighted (SPT-002).
     * 
     * Responses:
     *  - 200: The day, grouped by league.
     *  - 0: Any error, in the shared shape.
     *
     * @param date The local day, YYYY-MM-DD.
     * @param tz The IANA time zone the day is in. Default UTC. (optional)
     * @return [SportSchedule]
     */
    @GET("v1/sports/schedule")
    public suspend fun getSportSchedule(@Query("date") date: kotlin.String, @Query("tz") tz: kotlin.String? = null): Response<SportSchedule>

    /**
     * GET v1/me/sport-settings
     * The country \&quot;Where to watch\&quot; looks at, and whether Sports are on at all.
     * 
     * Responses:
     *  - 200: The settings.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SportSettings]
     */
    @GET("v1/me/sport-settings")
    public suspend fun getSportSettings(): Response<SportSettings>

    /**
     * GET v1/sports/suggested
     * The first-run picks for Sports (SPT-002).
     * A fixed list of leagues and promotions (Premier League, La Liga, NBA, NFL, UFC, WWE…) with their badges once known. The same for everyone; never a recommendation.
     * Responses:
     *  - 200: The picks.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SportEntityList]
     */
    @GET("v1/sports/suggested")
    public suspend fun getSportSuggestions(): Response<SportEntityList>


    /**
    * enum for parameter span
    */
    public enum class SpanGetStats(public val value: kotlin.String) {
        @SerialName(value = "all") all("all"),
        @SerialName(value = "last7") last7("last7"),
        @SerialName(value = "last30") last30("last30")
    }

    /**
     * GET v1/me/stats
     * What the user watched and read in one calendar year or month of their time zone (GAM-006a), in all time (GAM-006c), or in the last 7 or 30 days (GAM-006d). Derived only from their own library. Imported history counts only where it carries a real date.
     * 
     * Responses:
     *  - 200: The period's stats.
     *  - 0: Any error, in the shared shape.
     *
     * @param year Required unless `span` is sent. (optional)
     * @param span `all` is all time: every year from the first active one through the current year, one bucket per year, so its totals equal the years&#39; summed. `last7` and `last30` are the 7 or 30 days ending today, one bucket per day, with `prior` holding the window just before. A span takes no `year` or `month` (422 otherwise). (optional)
     * @param month 1–12. Absent means the whole year. (optional)
     * @param tz IANA time zone for day and month boundaries. Absent means UTC. (optional)
     * @return [Stats]
     */
    @GET("v1/me/stats")
    public suspend fun getStats(@Query("year") year: kotlin.Int? = null, @Query("span") span: SpanGetStats? = null, @Query("month") month: kotlin.Int? = null, @Query("tz") tz: kotlin.String? = null): Response<Stats>

    /**
     * GET v1/titles/{id}
     * A title from the catalog. Shows include their seasons and episodes.
     * 
     * Responses:
     *  - 200: The title.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [TitleDetail]
     */
    @GET("v1/titles/{id}")
    public suspend fun getTitle(@Path("id") id: java.util.UUID): Response<TitleDetail>

    /**
     * GET v1/titles/{id}/relations
     * The title&#39;s relation graph (GRAPH-001): prequels, sequels, side stories and adaptations across kinds, from AniList, TMDB collections and Wikidata, placed for drawing and marked with the caller&#39;s library. Catalog data: reading it writes nothing. A graph that is missing titles because a source failed or ran out of time says `partial`.
     * 
     * Responses:
     *  - 200: The graph.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param order `release` (default) or `story`. Story order needs numbered series in the data; when `storyOrderAvailable` is false the graph comes back in release order. (optional)
     * @return [RelationGraph]
     */
    @GET("v1/titles/{id}/relations")
    public suspend fun getTitleRelations(@Path("id") id: java.util.UUID, @Query("order") order: RelationOrder? = null): Response<RelationGraph>

    /**
     * GET v1/titles/{id}/tree
     * The title tree (GRAPH-005), \&quot;From here\&quot;: the title as the root and branches of up to five titles, the person who made it (a film&#39;s director, a show&#39;s creator, an anime&#39;s main studio, a manga&#39;s or book&#39;s author, an album&#39;s artist), its series and its adaptations, each marked with the caller&#39;s library. With `cast&#x3D;true` a film or show also has a branch for each of its first two billed actors (GRAPH-006). Catalog data, the same for every user: reading it writes nothing, and nothing in it is personal. A tree that is missing titles because a source failed or ran out of time says `partial`.
     * 
     * Responses:
     *  - 200: The tree.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param cast True to add the `lead_actor` and `second_actor` branches of a film or show. Without it the tree never holds those kinds, so a client that does not know them is safe. (optional)
     * @return [TitleTree]
     */
    @GET("v1/titles/{id}/tree")
    public suspend fun getTitleTree(@Path("id") id: java.util.UUID, @Query("cast") cast: kotlin.Boolean? = null): Response<TitleTree>

    /**
     * GET v1/titles/{id}/watch
     * Where to watch a film or show in one country (CAT-014).
     * The services that stream, rent or sell the title in `region`, in the provider&#39;s order (JustWatch data through TMDB; credit JustWatch where shown), and TMDB&#39;s page listing every way to watch it there. Aaru links out and plays nothing: there is one link per title, not one per service. Catalog data, the same for every user, cached by the server and never stored. The three lists are empty for a kind that is not a film or show, a region with no data, or a provider that did not answer: show nothing then.
     * Responses:
     *  - 200: Where to watch.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param region ISO 3166-1 alpha-2, e.g. `US`, `PT`, from the device&#39;s language settings. Used for this request only and never stored. Anything but two letters is 422 `validation_failed`.
     * @return [TitleWatch]
     */
    @GET("v1/titles/{id}/watch")
    public suspend fun getTitleWatch(@Path("id") id: java.util.UUID, @Query("region") region: kotlin.String): Response<TitleWatch>

    /**
     * GET v1/titles/{id}/world
     * The World a title belongs to (GRAPH-007): one story universe across every kind, the titles the relation graph joins through sequels, side stories, spin-offs and adaptations, with a lane per kind, marked with the caller&#39;s library. Catalog data, the same for every user: nothing in it is a recommendation, and reading it writes nothing to the library. Read from the server&#39;s store only. `state` is `building` while the World is queued (ask again in a few seconds) and `none` when the title relates to nothing or sits outside a cut universe; both come without lanes.
     * 
     * Responses:
     *  - 200: The World, or why there is none yet.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [World]
     */
    @GET("v1/titles/{id}/world")
    public suspend fun getTitleWorld(@Path("id") id: java.util.UUID): Response<World>

    /**
     * GET v1/tonight
     * One to three things to start tonight (AG-005), ranked from the user&#39;s own library: the next episode of shows in progress, today&#39;s airings, books in progress, wishlist films. Reasons are templates; no model is called.
     * 
     * Responses:
     *  - 200: The strip for the local day.
     *  - 0: Any error, in the shared shape.
     *
     * @param tz IANA time zone for \&quot;today\&quot; and air times. Absent means UTC. (optional)
     * @return [Tonight]
     */
    @GET("v1/tonight")
    public suspend fun getTonight(@Query("tz") tz: kotlin.String? = null): Response<Tonight>


    /**
    * enum for parameter by
    */
    public enum class ByGetTopListens(public val value: kotlin.String) {
        @SerialName(value = "artist") artist("artist"),
        @SerialName(value = "track") track("track"),
        @SerialName(value = "album") album("album")
    }


    /**
    * enum for parameter span
    */
    public enum class SpanGetTopListens(public val value: kotlin.String) {
        @SerialName(value = "all") all("all"),
        @SerialName(value = "last7") last7("last7"),
        @SerialName(value = "last30") last30("last30")
    }

    /**
     * GET v1/me/listens/top
     * Your most played artists, tracks or albums over a period (MUS-005). The period is chosen as for `/v1/me/stats`: a year, a month of it, or a span.
     * 
     * Responses:
     *  - 200: The period's top list.
     *  - 0: Any error, in the shared shape.
     *
     * @param by 
     * @param year Required unless `span` is sent. (optional)
     * @param span  (optional)
     * @param month 1–12. Absent means the whole year. (optional)
     * @param tz IANA time zone for day and month boundaries. Absent means UTC. (optional)
     * @param limit 1–50, default 10. (optional)
     * @param artist Only this artist&#39;s listens, compared case- and space-folded (MUS-008). (optional)
     * @return [ListenTop]
     */
    @GET("v1/me/listens/top")
    public suspend fun getTopListens(@Query("by") by: ByGetTopListens, @Query("year") year: kotlin.Int? = null, @Query("span") span: SpanGetTopListens? = null, @Query("month") month: kotlin.Int? = null, @Query("tz") tz: kotlin.String? = null, @Query("limit") limit: kotlin.Int? = null, @Query("artist") artist: kotlin.String? = null): Response<ListenTop>

    /**
     * GET v1/imports/trakt/connection
     * 
     * 
     * Responses:
     *  - 200: Whether Trakt is connected.
     *  - 0: Any error, in the shared shape.
     *
     * @return [TraktConnection]
     */
    @GET("v1/imports/trakt/connection")
    public suspend fun getTraktConnection(): Response<TraktConnection>

    /**
     * GET v1/up-next
     * Continue Watching, Start Watching, status counts and Unfinished business for the home screen, in one call.
     * 
     * Responses:
     *  - 200: The home rows.
     *  - 0: Any error, in the shared shape.
     *
     * @return [UpNext]
     */
    @GET("v1/up-next")
    public suspend fun getUpNext(): Response<UpNext>

    /**
     * GET v1/users/{userId}/avatar
     * Someone&#39;s avatar (SOC-001b), for any signed-in account. A block either way, an unknown user and no avatar are the same 404. Use the `avatarUrl` a response gave you: its `v` changes with every upload, so a cached image is never stale.
     * 
     * Responses:
     *  - 200: The JPEG, with `Cache-Control` for a week in a private cache.
     *  - 0: Any error, in the shared shape.
     *
     * @param userId 
     * @param v The avatar&#39;s version, for caches only. (optional)
     * @return [ResponseBody]
     */
    @GET("v1/users/{userId}/avatar")
    public suspend fun getUserAvatar(@Path("userId") userId: java.util.UUID, @Query("v") v: kotlin.Long? = null): Response<ResponseBody>

    /**
     * GET v1/groups/{groupId}/channels/{channelId}/party
     * A watch channel&#39;s newest party, ended or not, and the server&#39;s clock for the countdown.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @return [WatchPartyView]
     */
    @GET("v1/groups/{groupId}/channels/{channelId}/party")
    public suspend fun getWatchParty(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID): Response<WatchPartyView>

    /**
     * GET v1/web-push/key
     * The VAPID public key a browser subscribes with. 503 `push_unavailable` when web push is off.
     * 
     * Responses:
     *  - 200: The key.
     *  - 0: Any error, in the shared shape.
     *
     * @return [WebPushKey]
     */
    @GET("v1/web-push/key")
    public suspend fun getWebPushKey(): Response<WebPushKey>

    /**
     * POST v1/groups/{groupId}/invites
     * Invite a friend. Inviting again, or someone already in, changes nothing.
     * 
     * Responses:
     *  - 204: Invited.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param userRef 
     * @return [Unit]
     */
    @POST("v1/groups/{groupId}/invites")
    public suspend fun inviteToGroup(@Path("groupId") groupId: java.util.UUID, @Body userRef: UserRef): Response<Unit>

    /**
     * POST v1/imports/{id}/rows/{index}/left-out
     * Untick one row of a plan before approving it, or tick it again (BOOK-001). Only a row the plan would write, and only while the plan waits. The job&#39;s counts follow. Approving with every row unticked is refused with `import_nothing_chosen`.
     * 
     * Responses:
     *  - 200: Saved. The job's counts and the row as it now stands.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param index 
     * @param leaveOutImportRowRequest 
     * @return [LeaveOutImportRow200Response]
     */
    @POST("v1/imports/{id}/rows/{index}/left-out")
    public suspend fun leaveOutImportRow(@Path("id") id: java.util.UUID, @Path("index") index: kotlin.Int, @Body leaveOutImportRowRequest: LeaveOutImportRowRequest): Response<LeaveOutImportRow200Response>

    /**
     * POST v1/me/identities/google
     * Link a Google account to the signed-in account. Refused if it belongs to another account.
     * 
     * Responses:
     *  - 200: Linked.
     *  - 0: Any error, in the shared shape.
     *
     * @param googleSignInRequest 
     * @return [Me]
     */
    @POST("v1/me/identities/google")
    public suspend fun linkGoogle(@Body googleSignInRequest: GoogleSignInRequest): Response<Me>

    /**
     * GET v1/actions
     * The action journal, newest first. Backs the undo ribbon.
     * 
     * Responses:
     *  - 200: Actions.
     *  - 0: Any error, in the shared shape.
     *
     * @param limit  (optional, default to 50)
     * @return [ActionList]
     */
    @GET("v1/actions")
    public suspend fun listActions(@Query("limit") limit: kotlin.Int? = 50): Response<ActionList>


    /**
    * enum for parameter purpose
    */
    public enum class ForListAgentTokens(public val value: kotlin.String) {
        @SerialName(value = "stremio") stremio("stremio"),
        @SerialName(value = "mcp") mcp("mcp"),
        @SerialName(value = "scrobble") scrobble("scrobble"),
        @SerialName(value = "music") music("music")
    }

    /**
     * GET v1/agent/tokens
     * The user&#39;s live agent tokens (OUT-001), newest first. Secrets are never returned.
     * 
     * Responses:
     *  - 200: Live tokens.
     *  - 0: Any error, in the shared shape.
     *
     * @param purpose Which surface&#39;s tokens: the Stremio addon, MCP clients, the browser extension (`scrobble`), or music scrobblers (`music`). Defaults to `stremio`, so Apple builds that only know the Stremio kind never see another kind. (optional, default to stremio)
     * @return [ListAgentTokens200Response]
     */
    @GET("v1/agent/tokens")
    public suspend fun listAgentTokens(@Query("for") purpose: ForListAgentTokens? = ForListAgentTokens.stremio): Response<ListAgentTokens200Response>

    /**
     * GET v1/me/badges
     * Every badge in the catalog with what you have of it. A hidden badge you have not earned comes back with only its id, family and `hidden`: no name, rule or progress.
     * 
     * Responses:
     *  - 200: The catalog.
     *  - 0: Any error, in the shared shape.
     *
     * @return [BadgeList]
     */
    @GET("v1/me/badges")
    public suspend fun listBadges(): Response<BadgeList>

    /**
     * GET v1/social/blocks
     * People you blocked.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SocialUserList]
     */
    @GET("v1/social/blocks")
    public suspend fun listBlocks(): Response<SocialUserList>


    /**
    * enum for parameter sort
    */
    public enum class SortListBoard(public val value: kotlin.String) {
        @SerialName(value = "recent") recent("recent"),
        @SerialName(value = "top") top("top")
    }

    /**
     * GET v1/board
     * The Board feed. Posts by you and your friends. `top` is this week&#39;s most upvoted, at most 10.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param sort  (optional, default to recent)
     * @param before Posts older than this one. Ignored by `top`. (optional)
     * @param limit 1–50, default 20. (optional, default to 20)
     * @return [BoardPostPage]
     */
    @GET("v1/board")
    public suspend fun listBoard(@Query("sort") sort: SortListBoard? = SortListBoard.recent, @Query("before") before: java.util.UUID? = null, @Query("limit") limit: kotlin.Int? = 20): Response<BoardPostPage>

    /**
     * GET v1/board/posts/{postId}/comments
     * Comments on a post, oldest first, minus anyone blocked either way with you. A deleted comment with replies stays as an empty row; one without is dropped. A page can come back shorter than the limit.
     * 
     * Responses:
     *  - 200: The comments.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @param after The id of the last comment seen. (optional)
     * @param limit  (optional, default to 50)
     * @return [BoardCommentPage]
     */
    @GET("v1/board/posts/{postId}/comments")
    public suspend fun listBoardComments(@Path("postId") postId: java.util.UUID, @Query("after") after: java.util.UUID? = null, @Query("limit") limit: kotlin.Int? = 50): Response<BoardCommentPage>

    /**
     * GET v1/board/posts/{postId}/upvotes
     * Who upvoted a post, minus anyone blocked either way with you.
     * 
     * Responses:
     *  - 200: The upvoters.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @return [SocialUserList]
     */
    @GET("v1/board/posts/{postId}/upvotes")
    public suspend fun listBoardPostUpvoters(@Path("postId") postId: java.util.UUID): Response<SocialUserList>

    /**
     * GET v1/groups/{groupId}/channels/{channelId}/items
     * A shelf channel&#39;s titles, with your own library status for each.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @return [ChannelItemList]
     */
    @GET("v1/groups/{groupId}/channels/{channelId}/items")
    public suspend fun listChannelItems(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID): Response<ChannelItemList>

    /**
     * GET v1/chats
     * The caller&#39;s chats with Aaru, latest first, 30 a page (ASK-011). A chat nobody has asked anything in is left out.
     * 
     * Responses:
     *  - 200: One page of chats.
     *  - 0: Any error, in the shared shape.
     *
     * @param cursor Opaque cursor from a previous page&#39;s `page.nextCursor`. (optional)
     * @return [ChatList]
     */
    @GET("v1/chats")
    public suspend fun listChats(@Query("cursor") cursor: kotlin.String? = null): Response<ChatList>

    /**
     * GET v1/activity
     * Your friends&#39; last two weeks, newest first, one row per friend, title and day. Only dated episode ticks and finishes; imports never show. Friends who hide their library are left out.
     * 
     * Responses:
     *  - 200: One page.
     *  - 0: Any error, in the shared shape.
     *
     * @param before The `nextBefore` of the previous page. (optional)
     * @return [ActivityPage]
     */
    @GET("v1/activity")
    public suspend fun listFriendActivity(@Query("before") before: java.time.OffsetDateTime? = null): Response<ActivityPage>

    /**
     * GET v1/social/invites
     * Your invite links that are still open, newest first.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [FriendInviteList]
     */
    @GET("v1/social/invites")
    public suspend fun listFriendInvites(): Response<FriendInviteList>

    /**
     * GET v1/social/friend-requests
     * Pending requests to you and from you, newest first.
     * 
     * Responses:
     *  - 200: Both directions.
     *  - 0: Any error, in the shared shape.
     *
     * @return [FriendRequests]
     */
    @GET("v1/social/friend-requests")
    public suspend fun listFriendRequests(): Response<FriendRequests>

    /**
     * GET v1/social/friends
     * Your friends, by handle.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SocialUserList]
     */
    @GET("v1/social/friends")
    public suspend fun listFriends(): Response<SocialUserList>

    /**
     * GET v1/me/group-invites
     * Invites waiting for you, newest first.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [GroupInviteList]
     */
    @GET("v1/me/group-invites")
    public suspend fun listGroupInvites(): Response<GroupInviteList>

    /**
     * GET v1/groups
     * Your groups, in the order you joined them, with unread and mention counts.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [GroupList]
     */
    @GET("v1/groups")
    public suspend fun listGroups(): Response<GroupList>

    /**
     * GET v1/imports
     * The user&#39;s imports, newest first.
     * 
     * Responses:
     *  - 200: Up to 50 imports.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ImportList]
     */
    @GET("v1/imports")
    public suspend fun listImports(): Response<ImportList>

    /**
     * GET v1/library/items
     * The user&#39;s library, most recently updated first. Shelves use the same filters.
     * 
     * Responses:
     *  - 200: One page.
     *  - 0: Any error, in the shared shape.
     *
     * @param type  (optional)
     * @param anime  (optional)
     * @param status  (optional)
     * @param owned  (optional)
     * @param list  (optional)
     * @param cursor Opaque cursor from a previous page&#39;s `page.nextCursor`. (optional)
     * @param limit  (optional, default to 50)
     * @return [LibraryPage]
     */
    @GET("v1/library/items")
    public suspend fun listLibraryItems(@Query("type") type: MediaType? = null, @Query("anime") anime: kotlin.Boolean? = null, @Query("status") status: LibraryStatus? = null, @Query("owned") owned: kotlin.Boolean? = null, @Query("list") list: java.util.UUID? = null, @Query("cursor") cursor: kotlin.String? = null, @Query("limit") limit: kotlin.Int? = 50): Response<LibraryPage>

    /**
     * GET v1/me/listens
     * Your listening log, newest first (MUS-005): what music scrobblers sent with your music token over ListenBrainz&#39;s protocol at `/listenbrainz/1/submit-listens`.
     * 
     * Responses:
     *  - 200: A page of listens.
     *  - 0: Any error, in the shared shape.
     *
     * @param before Only listens that started before this time; the previous page&#39;s `next`. (optional)
     * @param limit 1–100, default 20. (optional)
     * @return [ListenPage]
     */
    @GET("v1/me/listens")
    public suspend fun listListens(@Query("before") before: java.time.OffsetDateTime? = null, @Query("limit") limit: kotlin.Int? = null): Response<ListenPage>

    /**
     * GET v1/lists
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ListList]
     */
    @GET("v1/lists")
    public suspend fun listLists(): Response<ListList>

    /**
     * GET v1/groups/{groupId}/channels/{channelId}/messages
     * Messages oldest first. Without a cursor, the latest page.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param before Messages older than this one. (optional)
     * @param after Messages newer than this one. (optional)
     * @param limit 1–100, default 50. (optional)
     * @return [GroupMessagePage]
     */
    @GET("v1/groups/{groupId}/channels/{channelId}/messages")
    public suspend fun listMessages(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Query("before") before: java.util.UUID? = null, @Query("after") after: java.util.UUID? = null, @Query("limit") limit: kotlin.Int? = null): Response<GroupMessagePage>

    /**
     * GET v1/me/worlds
     * The Worlds the caller has at least one library item in (GRAPH-007), each with how far they are: those with something left first, the furthest along leading, then the finished ones. At most 100. Only Worlds already built are listed; an import&#39;s titles appear as their Worlds are built.
     * 
     * Responses:
     *  - 200: The caller's Worlds.
     *  - 0: Any error, in the shared shape.
     *
     * @return [MyWorlds]
     */
    @GET("v1/me/worlds")
    public suspend fun listMyWorlds(): Response<MyWorlds>


    /**
    * enum for parameter status
    */
    public enum class StatusListPlans(public val value: kotlin.String) {
        @SerialName(value = "pending") pending("pending"),
        @SerialName(value = "all") all("all")
    }

    /**
     * GET v1/plans
     * Changes outside agents asked for that wait for the user (OUT-004), newest first. Only a signed-in session reaches the plan routes; an agent token never does.
     * 
     * Responses:
     *  - 200: Plans.
     *  - 0: Any error, in the shared shape.
     *
     * @param status `pending` (default) leaves out decided and expired plans. (optional, default to pending)
     * @return [ListPlans200Response]
     */
    @GET("v1/plans")
    public suspend fun listPlans(@Query("status") status: StatusListPlans? = StatusListPlans.pending): Response<ListPlans200Response>

    /**
     * GET v1/me/points
     * The points ledger, newest first, a page at a time (\&quot;How you earned it\&quot;).
     * 
     * Responses:
     *  - 200: A page of the ledger.
     *  - 0: Any error, in the shared shape.
     *
     * @param before  (optional)
     * @param limit 1–100, 50 unless asked. (optional)
     * @return [PointsPage]
     */
    @GET("v1/me/points")
    public suspend fun listPoints(@Query("before") before: java.time.OffsetDateTime? = null, @Query("limit") limit: kotlin.Int? = null): Response<PointsPage>

    /**
     * GET v1/me/recommendations
     * Titles friends sent you that you have not added or dismissed, newest first. Only from people who are still your friends.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [RecommendationList]
     */
    @GET("v1/me/recommendations")
    public suspend fun listRecommendations(): Response<RecommendationList>

    /**
     * GET v1/shelves/{id}/items
     * The shelf&#39;s query, resolved now. Same DTO as GET /v1/library/items.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param cursor Opaque cursor from a previous page&#39;s `page.nextCursor`. (optional)
     * @param limit  (optional, default to 50)
     * @return [LibraryPage]
     */
    @GET("v1/shelves/{id}/items")
    public suspend fun listShelfItems(@Path("id") id: java.util.UUID, @Query("cursor") cursor: kotlin.String? = null, @Query("limit") limit: kotlin.Int? = 50): Response<LibraryPage>

    /**
     * GET v1/shelves
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @return [ShelfList]
     */
    @GET("v1/shelves")
    public suspend fun listShelves(): Response<ShelfList>

    /**
     * GET v1/me/sport-follows
     * The leagues, teams and players the user follows in Sports, oldest first.
     * 
     * Responses:
     *  - 200: The follows.
     *  - 0: Any error, in the shared shape.
     *
     * @return [SportFollowList]
     */
    @GET("v1/me/sport-follows")
    public suspend fun listSportFollows(): Response<SportFollowList>

    /**
     * GET v1/titles/{id}/posts
     * Posts about this title by you and your friends, newest first.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param limit 1–50, default 20. (optional, default to 20)
     * @return [BoardPostPage]
     */
    @GET("v1/titles/{id}/posts")
    public suspend fun listTitlePosts(@Path("id") id: java.util.UUID, @Query("limit") limit: kotlin.Int? = 20): Response<BoardPostPage>

    /**
     * GET v1/library/watching
     * Films, shows and anime in progress with what Library&#39;s Watching page shows (APP-018): the next episode to watch with its name and what is left, and a show&#39;s status and next airing. Anime in the backlog are included with `entry.inBacklog`. Newest change first.
     * 
     * Responses:
     *  - 200: The titles in progress.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Watching]
     */
    @GET("v1/library/watching")
    public suspend fun listWatching(): Response<Watching>

    /**
     * POST v1/me/badges/seen
     * Marks earned badges (by award id) as seen, so they leave `unseen`.
     * 
     * Responses:
     *  - 204: Seen.
     *  - 0: Any error, in the shared shape.
     *
     * @param markBadgesSeenRequest 
     * @return [Unit]
     */
    @POST("v1/me/badges/seen")
    public suspend fun markBadgesSeen(@Body markBadgesSeenRequest: MarkBadgesSeenRequest): Response<Unit>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/read
     * Mark the channel read up to a message. The read point never moves back.
     * 
     * Responses:
     *  - 204: Marked.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param readMark 
     * @return [Unit]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/read")
    public suspend fun markChannelRead(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body readMark: ReadMark): Response<Unit>

    /**
     * POST v1/library/items/{id}/seasons/{season}/watched
     * Mark every aired episode of a season watched, as one undoable action.
     * 
     * Responses:
     *  - 200: The item with updated progress.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param season 
     * @return [LibraryEntry]
     */
    @POST("v1/library/items/{id}/seasons/{season}/watched")
    public suspend fun markSeasonWatched(@Path("id") id: java.util.UUID, @Path("season") season: kotlin.Int): Response<LibraryEntry>

    /**
     * POST v1/library/items/{id}/watched
     * Mark a whole show watched (PROG-005): every aired regular episode, as one undoable action with the watch dates unknown, so the Recap and Insights do not count them as today. The show becomes finished; a running one moves back to in progress when an episode it has not ticked airs. 422 for anything but a show.
     * 
     * Responses:
     *  - 200: The item, the action to undo it with, and how many episodes it ticked.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [ShowWatched]
     */
    @POST("v1/library/items/{id}/watched")
    public suspend fun markShowWatched(@Path("id") id: java.util.UUID): Response<ShowWatched>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/party/watched
     * Mark the party&#39;s episode, chapter, page, film or book in your own library. For a member who switched autoMark off or did not join.
     * 
     * Responses:
     *  - 204: Marked.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @return [Unit]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/party/watched")
    public suspend fun markWatchPartyWatched(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID): Response<Unit>

    /**
     * POST v1/imports/{id}/match-all
     * Find a best guess for the plan&#39;s unmatched rows (IMP-021): the \&quot;Match all\&quot; button. A guess joins the plan like a pick and shows what it found, so the person checks it before approving; nothing is written here. One call does what fits in a few seconds, so a client calls again while `remaining` goes down, and stops when it does not. Only while the plan waits.
     * 
     * Responses:
     *  - 200: Saved. The job's counts, the rows this call changed, and how many are left to try.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [MatchAllImportRows200Response]
     */
    @POST("v1/imports/{id}/match-all")
    public suspend fun matchAllImportRows(@Path("id") id: java.util.UUID): Response<MatchAllImportRows200Response>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/party
     * Open a party in the lobby. A show needs the episode; a manga can carry a chapter and volume, a book a page. One open party per channel (409).
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param watchPartyCreate 
     * @return [WatchPartyView]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/party")
    public suspend fun openWatchParty(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body watchPartyCreate: WatchPartyCreate): Response<WatchPartyView>

    /**
     * POST v1/titles/{id}/relations/chain
     * \&quot;Add the chain\&quot; (GRAPH-003): the main chain of the title&#39;s relation graph, in the graph&#39;s order, as a capture to review, with exact ids. Approving adds what is not in the library to Plan to watch or read and makes a list in that order. Spends one capture, as any capture does; writes nothing to the library by itself.
     * 
     * Responses:
     *  - 202: Queued for review.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param order  (optional)
     * @return [ImportJob]
     */
    @POST("v1/titles/{id}/relations/chain")
    public suspend fun planRelationChain(@Path("id") id: java.util.UUID, @Query("order") order: RelationOrder? = null): Response<ImportJob>

    /**
     * POST v1/titles/{id}/world/plan
     * \&quot;Add the rest\&quot; (GRAPH-007): the titles of the title&#39;s World that are not in the caller&#39;s library, in the World&#39;s order, as a capture to review, with exact ids. Approving adds them to Plan to watch or read. Spends one capture, as any capture does; writes nothing to the library by itself. 422 when there is no World yet or nothing is left to add.
     * 
     * Responses:
     *  - 202: Queued for review.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [ImportJob]
     */
    @POST("v1/titles/{id}/world/plan")
    public suspend fun planWorldRest(@Path("id") id: java.util.UUID): Response<ImportJob>

    /**
     * POST v1/imports/stremio/link/{code}
     * Ask whether the code was approved. 204 while pending (ask again in a few seconds); 202 with the queued import once approved; 410 `stremio_link_expired` when the code ran out.
     * 
     * Responses:
     *  - 202: Approved. The library was read and its import queued.
     *  - 204: Not approved yet.
     *  - 0: Any error, in the shared shape.
     *
     * @param code 
     * @return [ImportJob]
     */
    @POST("v1/imports/stremio/link/{code}")
    public suspend fun pollStremioLink(@Path("code") code: kotlin.String): Response<ImportJob>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/messages
     * Post a message. A retry with the same clientNonce returns the first message.
     * 
     * Responses:
     *  - 200: The message.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param messageCreate 
     * @return [GroupMessage]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/messages")
    public suspend fun postMessage(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body messageCreate: MessageCreate): Response<GroupMessage>

    /**
     * POST v1/billing/apple/notifications
     * App Store Server Notifications v2 (BIL-003): renewals, expiries, refunds. Unauthenticated; the payload is verified up to Apple&#39;s root certificate.
     * 
     * Responses:
     *  - 200: Received.
     *  - 0: Any error, in the shared shape.
     *
     * @param receiveAppleNotificationRequest 
     * @return [Unit]
     */
    @POST("v1/billing/apple/notifications")
    public suspend fun receiveAppleNotification(@Body receiveAppleNotificationRequest: ReceiveAppleNotificationRequest): Response<Unit>

    /**
     * POST v1/social/recommendations
     * Send a title to up to 10 friends, with an optional note of up to 140 characters. Anyone who is not your friend makes the whole request a 404. Needs your own handle.
     * 
     * Responses:
     *  - 204: Sent. A title already waiting for the same friend is not sent twice.
     *  - 0: Any error, in the shared shape.
     *
     * @param recommendationCreate 
     * @return [Unit]
     */
    @POST("v1/social/recommendations")
    public suspend fun recommendTitle(@Body recommendationCreate: RecommendationCreate): Response<Unit>

    /**
     * POST v1/billing/apple/transactions
     * A purchase or a restore, from the Apple app that made it (BIL-002). The signed transaction must carry this account&#39;s `appAccountToken`; 409 `plus_other_account` when it names another, 409 `sandbox_refused` for a Sandbox (TestFlight) purchase while the server does not accept them, 422 `invalid_transaction` when it does not verify.
     * 
     * Responses:
     *  - 200: The entitlement after it.
     *  - 0: Any error, in the shared shape.
     *
     * @param recordAppleTransactionRequest 
     * @return [Entitlement]
     */
    @POST("v1/billing/apple/transactions")
    public suspend fun recordAppleTransaction(@Body recordAppleTransactionRequest: RecordAppleTransactionRequest): Response<Entitlement>

    /**
     * POST v1/social/invites/{code}/redeem
     * Accept an invite. You and the inviter become friends and the link is spent; already friends leaves it unspent. Needs your own handle.
     * 
     * Responses:
     *  - 200: The new friend.
     *  - 0: Any error, in the shared shape.
     *
     * @param code 
     * @param inviteRedeem 
     * @return [InviteRedemption]
     */
    @POST("v1/social/invites/{code}/redeem")
    public suspend fun redeemFriendInvite(@Path("code") code: kotlin.String, @Body inviteRedeem: InviteRedeem): Response<InviteRedemption>

    /**
     * PUT v1/devices
     * Register this device for pushes. A token registered again moves to this user.
     * 
     * Responses:
     *  - 204: Registered.
     *  - 0: Any error, in the shared shape.
     *
     * @param deviceRegistration 
     * @return [Unit]
     */
    @PUT("v1/devices")
    public suspend fun registerDevice(@Body deviceRegistration: DeviceRegistration): Response<Unit>

    /**
     * PUT v1/devices/live-activity
     * Hand over an ActivityKit push token (SCR-008, SCR-009): the device&#39;s push-to-start token for `NowPlayingActivityAttributes` (`start`), or the running \&quot;Now playing\&quot; activity&#39;s own token (`update`). The server then starts, updates and ends the activity from what plays.
     * 
     * Responses:
     *  - 204: Registered.
     *  - 0: Any error, in the shared shape.
     *
     * @param liveActivityRegistration 
     * @return [Unit]
     */
    @PUT("v1/devices/live-activity")
    public suspend fun registerLiveActivityToken(@Body liveActivityRegistration: LiveActivityRegistration): Response<Unit>

    /**
     * DELETE v1/board/posts/{postId}/upvote
     * Take your upvote back. Fine if you never gave one.
     * 
     * Responses:
     *  - 204: Removed.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @return [Unit]
     */
    @DELETE("v1/board/posts/{postId}/upvote")
    public suspend fun removeBoardPostUpvote(@Path("postId") postId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/groups/{groupId}/channels/{channelId}/items/{titleId}
     * Take a title off a shelf channel. Any member can.
     * 
     * Responses:
     *  - 204: Removed.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param titleId 
     * @return [Unit]
     */
    @DELETE("v1/groups/{groupId}/channels/{channelId}/items/{titleId}")
    public suspend fun removeChannelItem(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Path("titleId") titleId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/social/friends/{userId}
     * Unfriend. Silent; the other side is not told.
     * 
     * Responses:
     *  - 204: No longer friends.
     *  - 0: Any error, in the shared shape.
     *
     * @param userId 
     * @return [Unit]
     */
    @DELETE("v1/social/friends/{userId}")
    public suspend fun removeFriend(@Path("userId") userId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/groups/{groupId}/members/{userId}
     * Remove a member, or yourself to leave. Admins remove members; the owner removes anyone and cannot leave.
     * 
     * Responses:
     *  - 204: Removed.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param userId 
     * @return [Unit]
     */
    @DELETE("v1/groups/{groupId}/members/{userId}")
    public suspend fun removeGroupMember(@Path("groupId") groupId: java.util.UUID, @Path("userId") userId: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/lists/{id}/items/{titleId}
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param titleId 
     * @return [ListDetail]
     */
    @DELETE("v1/lists/{id}/items/{titleId}")
    public suspend fun removeListItem(@Path("id") id: java.util.UUID, @Path("titleId") titleId: java.util.UUID): Response<ListDetail>

    /**
     * PATCH v1/lists/{id}
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param renameList 
     * @return [ListDetail]
     */
    @PATCH("v1/lists/{id}")
    public suspend fun renameList(@Path("id") id: java.util.UUID, @Body renameList: RenameList): Response<ListDetail>

    /**
     * PUT v1/lists/{id}/order
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param listOrder 
     * @return [ListDetail]
     */
    @PUT("v1/lists/{id}/order")
    public suspend fun reorderList(@Path("id") id: java.util.UUID, @Body listOrder: ListOrder): Response<ListDetail>

    /**
     * POST v1/social/reports
     * Report a user to Aaru. The user is not told.
     * 
     * Responses:
     *  - 204: Received.
     *  - 0: Any error, in the shared shape.
     *
     * @param reportCreate 
     * @return [Unit]
     */
    @POST("v1/social/reports")
    public suspend fun reportUser(@Body reportCreate: ReportCreate): Response<Unit>

    /**
     * POST v1/connections/mal/pull
     * A client opened Aaru: read the MyAnimeList list back on the next pass (SCR-010). Ignored when MAL is not connected or was read in the last 10 minutes, so clients call it on every open.
     * 
     * Responses:
     *  - 204: Asked, or not needed.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @POST("v1/connections/mal/pull")
    public suspend fun requestMALPull(): Response<Unit>

    /**
     * POST v1/auth/email/link
     * Email a one-time sign-in link. Same answer whether or not an account exists.
     * 
     * Responses:
     *  - 202: The link was sent (or would have been).
     *  - 0: Any error, in the shared shape.
     *
     * @param magicLinkRequest 
     * @return [Unit]
     */
    @POST("v1/auth/email/link")
    public suspend fun requestMagicLink(@Body magicLinkRequest: MagicLinkRequest): Response<Unit>

    /**
     * POST v1/imports/{id}/rows/{index}/resolve
     * Match one unmatched row by hand (IMP-011), with a title the person picked from a search. Before the plan is approved the pick joins the plan; after it, the row is written at once as its own undoable action. The source&#39;s status, rating and ticks come with it, merged like any import row.
     * 
     * Responses:
     *  - 200: Matched. The job's counts and the row as it now stands.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param index 
     * @param resolveImportRowRequest 
     * @return [LeaveOutImportRow200Response]
     */
    @POST("v1/imports/{id}/rows/{index}/resolve")
    public suspend fun resolveImportRow(@Path("id") id: java.util.UUID, @Path("index") index: kotlin.Int, @Body resolveImportRowRequest: ResolveImportRowRequest): Response<LeaveOutImportRow200Response>

    /**
     * POST v1/titles/resolve
     * The page for a catalog ref, in the library or not (LIB-006). Resolving may add the title to the catalog; it never adds it to the library.
     * 
     * Responses:
     *  - 200: The title, and the caller's library item when they have it.
     *  - 0: Any error, in the shared shape.
     *
     * @param mediaRef 
     * @return [TitlePreview]
     */
    @POST("v1/titles/resolve")
    public suspend fun resolveTitle(@Body mediaRef: MediaRef): Response<TitlePreview>

    /**
     * DELETE v1/agent/tokens/{id}
     * Revoke a token. Its addon stops answering at once.
     * 
     * Responses:
     *  - 204: Revoked.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/agent/tokens/{id}")
    public suspend fun revokeAgentToken(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/social/invites/{code}
     * Revoke one of your open invite links. Anyone opening it afterwards sees an invalid invite.
     * 
     * Responses:
     *  - 204: Revoked.
     *  - 0: Any error, in the shared shape.
     *
     * @param code 
     * @return [Unit]
     */
    @DELETE("v1/social/invites/{code}")
    public suspend fun revokeFriendInvite(@Path("code") code: kotlin.String): Response<Unit>

    /**
     * PUT v1/me/concert-place
     * Saves the \&quot;Concerts near\&quot; city, rounded to two decimals.
     * 
     * Responses:
     *  - 200: Saved.
     *  - 0: Any error, in the shared shape.
     *
     * @param concertPlace 
     * @return [ConcertPlaceSetting]
     */
    @PUT("v1/me/concert-place")
    public suspend fun saveConcertPlace(@Body concertPlace: ConcertPlace): Response<ConcertPlaceSetting>

    /**
     * PUT v1/me/sport-settings
     * Saves the \&quot;Where to watch\&quot; country; absent or null clears it.
     * 
     * Responses:
     *  - 200: Saved.
     *  - 0: Any error, in the shared shape.
     *
     * @param sportSettingsInput 
     * @return [SportSettings]
     */
    @PUT("v1/me/sport-settings")
    public suspend fun saveSportSettings(@Body sportSettingsInput: SportSettingsInput): Response<SportSettings>

    /**
     * PUT v1/web-push/subscriptions
     * Save this browser&#39;s push subscription. Saved again, it moves to this user.
     * 
     * Responses:
     *  - 204: Saved.
     *  - 0: Any error, in the shared shape.
     *
     * @param webPushSubscription 
     * @return [Unit]
     */
    @PUT("v1/web-push/subscriptions")
    public suspend fun saveWebPushSubscription(@Body webPushSubscription: WebPushSubscription): Response<Unit>


    /**
    * enum for parameter type
    */
    public enum class TypeSearchCatalog(public val value: kotlin.String) {
        @SerialName(value = "all") all("all"),
        @SerialName(value = "movie") movie("movie"),
        @SerialName(value = "show") show("show"),
        @SerialName(value = "anime") anime("anime"),
        @SerialName(value = "book") book("book"),
        @SerialName(value = "album") album("album"),
        @SerialName(value = "manga") manga("manga")
    }

    /**
     * GET v1/search
     * Search the catalog. Results are catalog projections, never library rows.
     * 
     * Responses:
     *  - 200: Matches, best first. With `all`, exact title matches lead, then TMDB and AniList hits alternate, at most 40; a TMDB show is left out only when an AniList hit in the same results is mapped to it, and that hit then carries `ids.tmdb`.
     *  - 0: Any error, in the shared shape.
     *
     * @param q 
     * @param type `all` searches films, shows and anime together (TMDB and AniList in parallel, merged; books and albums are never included); `anime` searches AniList; `movie`/`show` TMDB; `book` Open Library; `album` MusicBrainz (albums and EPs, MUS-001); `manga` AniList (MNG-001; empty and incomplete while AniList is down).
     * @return [SearchResults]
     */
    @GET("v1/search")
    public suspend fun searchCatalog(@Query("q") q: kotlin.String, @Query("type") type: TypeSearchCatalog): Response<SearchResults>

    /**
     * POST v1/concerts/performers
     * Performers whose name matches what the user typed, to pick one before a search (MUS-010).
     * Ticketmaster&#39;s own performer list for the name, best first, up to eight. Picking one and sending its `id` as `performerId` to `/v1/concerts/search` lists only that performer&#39;s concerts. POST so the name never sits in a URL; not logged, cached by the server.
     * Responses:
     *  - 200: The performers. `unavailable` when concerts are off or the provider is down.
     *  - 0: Any error, in the shared shape.
     *
     * @param concertPerformerRequest 
     * @return [ConcertPerformerList]
     */
    @POST("v1/concerts/performers")
    public suspend fun searchConcertPerformers(@Body concertPerformerRequest: ConcertPerformerRequest): Response<ConcertPerformerList>

    /**
     * GET v1/concerts/places
     * Cities matching what the user typed, for the \&quot;Concerts near\&quot; picker (MUS-003).
     * 
     * Responses:
     *  - 200: Up to eight places, best first.
     *  - 0: Any error, in the shared shape.
     *
     * @param q 2 to 100 characters. Not logged.
     * @return [ConcertPlaceList]
     */
    @GET("v1/concerts/places")
    public suspend fun searchConcertPlaces(@Query("q") q: kotlin.String): Response<ConcertPlaceList>

    /**
     * POST v1/concerts/search
     * Music events matching an artist&#39;s name, near a place or anywhere (MUS-010), soonest first.
     * POST so neither the name nor a position sits in a URL. The name goes to Ticketmaster as free text, so other acts whose events carry the word can match. `near` searches around a one-off point or the saved city like `/v1/concerts/near` (with neither, 409 `no_place`); `anywhere` sends the name alone, and each concert&#39;s `distanceKm` is worked out by the server from the point or saved city when there is one. Neither name nor position is logged; the same list for everyone, cached by the server.
     * Responses:
     *  - 200: The page. `unavailable` when concerts are off or the provider is down.
     *  - 0: Any error, in the shared shape.
     *
     * @param concertSearchRequest 
     * @return [ConcertSearchPage]
     */
    @POST("v1/concerts/search")
    public suspend fun searchConcerts(@Body concertSearchRequest: ConcertSearchRequest): Response<ConcertSearchPage>

    /**
     * GET v1/sports/search
     * Leagues, teams and players by name, from the sports provider (SPT-002).
     * 
     * Responses:
     *  - 200: Up to ten of each kind, leagues first.
     *  - 0: Any error, in the shared shape.
     *
     * @param q 2 to 100 characters.
     * @param kind Absent searches all three. (optional)
     * @return [SportEntityList]
     */
    @GET("v1/sports/search")
    public suspend fun searchSports(@Query("q") q: kotlin.String, @Query("kind") kind: SportEntityKind? = null): Response<SportEntityList>

    /**
     * POST v1/social/friend-requests
     * Ask someone to be friends, by handle. If they already asked you, you become friends. Needs your own handle. At most 30 a user per hour (429).
     * 
     * Responses:
     *  - 200: The user and where you now stand (outgoing or friend).
     *  - 0: Any error, in the shared shape.
     *
     * @param friendRequestCreate 
     * @return [SocialUserView]
     */
    @POST("v1/social/friend-requests")
    public suspend fun sendFriendRequest(@Body friendRequestCreate: FriendRequestCreate): Response<SocialUserView>

    /**
     * POST v1/tonight/{id}/feedback
     * \&quot;Not tonight\&quot; hides the item until the local day ends; \&quot;rejected\&quot; (not for me) weighs against it for 14 days.
     * 
     * Responses:
     *  - 204: Recorded.
     *  - 0: Any error, in the shared shape.
     *
     * @param id The library item.
     * @param tonightFeedback 
     * @param tz IANA time zone for the local day. Absent means UTC. (optional)
     * @return [Unit]
     */
    @POST("v1/tonight/{id}/feedback")
    public suspend fun sendTonightFeedback(@Path("id") id: java.util.UUID, @Body tonightFeedback: TonightFeedback, @Query("tz") tz: kotlin.String? = null): Response<Unit>

    /**
     * PUT v1/me/ai-sharing
     * Answer AI sharing (PRV-002): may Aaru send this user&#39;s data to its AI provider. The answer can change at any time; the latest one holds. Until it is `allowed`, every route that would send the user&#39;s data to the AI provider answers 403 `ai_sharing_required` and sends nothing.
     * 
     * Responses:
     *  - 200: The answer as stored.
     *  - 0: Any error, in the shared shape.
     *
     * @param aiSharingUpdate 
     * @return [AISharing]
     */
    @PUT("v1/me/ai-sharing")
    public suspend fun setAISharing(@Body aiSharingUpdate: AISharingUpdate): Response<AISharing>

    /**
     * PUT v1/activity/{id}/reaction
     * React to a friend&#39;s activity row with one of six emoji; reacting again replaces it. Your own rows take none. 404 unless you can see the row.
     * 
     * Responses:
     *  - 204: Saved.
     *  - 0: Any error, in the shared shape.
     *
     * @param id An ActivityItem id.
     * @param reactionSet 
     * @return [Unit]
     */
    @PUT("v1/activity/{id}/reaction")
    public suspend fun setActivityReaction(@Path("id") id: kotlin.String, @Body reactionSet: ReactionSet): Response<Unit>

    /**
     * PUT v1/library/items/{id}/episodes/{season}/{episode}
     * 
     * 
     * Responses:
     *  - 200: The item with updated progress.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param season 
     * @param episode 
     * @param episodeWatched 
     * @return [LibraryEntry]
     */
    @PUT("v1/library/items/{id}/episodes/{season}/{episode}")
    public suspend fun setEpisodeWatched(@Path("id") id: java.util.UUID, @Path("season") season: kotlin.Int, @Path("episode") episode: kotlin.Int, @Body episodeWatched: EpisodeWatched): Response<LibraryEntry>

    /**
     * PUT v1/me/favorites/{kind}
     * Replace one kind&#39;s favorites with these titles, in this order: add, remove and reorder are all this call. Any catalog title, at most 10, each once, each of this kind; else 422. Not journaled.
     * 
     * Responses:
     *  - 200: All your favorites after the change.
     *  - 0: Any error, in the shared shape.
     *
     * @param kind 
     * @param favoritesUpdate 
     * @return [Favorites]
     */
    @PUT("v1/me/favorites/{kind}")
    public suspend fun setMyFavorites(@Path("kind") kind: FavoriteKind, @Body favoritesUpdate: FavoritesUpdate): Response<Favorites>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/party/ready
     * Say you are ready, or not. Being ready is joining; autoMark is whether the end of the party marks the title for you.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param watchPartyReady 
     * @return [WatchPartyView]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/party/ready")
    public suspend fun setWatchPartyReady(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body watchPartyReady: WatchPartyReady): Response<WatchPartyView>

    /**
     * POST v1/auth/apple
     * Exchange a Sign in with Apple identity token for a session.
     * 
     * Responses:
     *  - 200: Signed in. The token is shown once.
     *  - 0: Any error, in the shared shape.
     *
     * @param appleSignInRequest 
     * @return [Session]
     */
    @POST("v1/auth/apple")
    public suspend fun signInWithApple(@Body appleSignInRequest: AppleSignInRequest): Response<Session>

    /**
     * POST v1/auth/google
     * Exchange a Google ID token for a session. Creates the account on first use.
     * 
     * Responses:
     *  - 200: Signed in. The token is shown once.
     *  - 0: Any error, in the shared shape.
     *
     * @param googleSignInRequest 
     * @return [Session]
     */
    @POST("v1/auth/google")
    public suspend fun signInWithGoogle(@Body googleSignInRequest: GoogleSignInRequest): Response<Session>

    /**
     * DELETE v1/auth/session
     * End the current session.
     * 
     * Responses:
     *  - 204: Signed out.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/auth/session")
    public suspend fun signOut(): Response<Unit>

    /**
     * DELETE v1/auth/sessions
     * Sign out of other devices: end every session of this account except the one that asks. The caller stays signed in.
     * 
     * Responses:
     *  - 204: Every other session is ended.
     *  - 401: Any error, in the shared shape.
     *  - 0: Any error, in the shared shape.
     *
     * @return [Unit]
     */
    @DELETE("v1/auth/sessions")
    public suspend fun signOutOtherDevices(): Response<Unit>

    /**
     * POST v1/imports/stremio/link
     * Start a Stremio history import. Show the user `link` (or `qrcode`) to approve on stremio.com, then poll POST /v1/imports/stremio/link/{code}. No password reaches Aaru; the session the code opens is used for one library read, then logged out.
     * 
     * Responses:
     *  - 200: A code to approve.
     *  - 0: Any error, in the shared shape.
     *
     * @return [StremioLink]
     */
    @POST("v1/imports/stremio/link")
    public suspend fun startStremioLink(): Response<StremioLink>

    /**
     * POST v1/groups/{groupId}/channels/{channelId}/party/start
     * Start the countdown. The host or an admin.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param watchPartyStart  (optional)
     * @return [WatchPartyView]
     */
    @POST("v1/groups/{groupId}/channels/{channelId}/party/start")
    public suspend fun startWatchParty(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body watchPartyStart: WatchPartyStart? = null): Response<WatchPartyView>

    /**
     * GET v1/library/sync
     * Items changed and ids deleted since a previous sync token (all items when absent).
     * 
     * Responses:
     *  - 200: The changes and the token for next time.
     *  - 0: Any error, in the shared shape.
     *
     * @param since  (optional)
     * @return [LibrarySync]
     */
    @GET("v1/library/sync")
    public suspend fun syncLibrary(@Query("since") since: kotlin.String? = null): Response<LibrarySync>

    /**
     * POST v1/chats/transcribe
     * Turn a spoken question into text (ASK-009). The audio is held in memory while it is read and never stored. 413 `file_too_large` over 8 MB, 413 `audio_too_long` when `X-Audio-Seconds` says over 60, 422 `transcription_empty` when no words were heard, 429 `rate_limited` past 40 an hour, 503 `transcription_unavailable` when voice is off.
     * 
     * Responses:
     *  - 200: What was said.
     *  - 0: Any error, in the shared shape.
     *
     * @param body 
     * @param xAudioSeconds How long the recording is, as the client measured it. (optional)
     * @return [ChatTranscript]
     */
    @POST("v1/chats/transcribe")
    public suspend fun transcribeChatAudio(@Body body: java.io.File, @Header("X-Audio-Seconds") xAudioSeconds: java.math.BigDecimal? = null): Response<ChatTranscript>

    /**
     * POST v1/groups/{groupId}/transfer
     * Make another member the owner. You become an admin.
     * 
     * Responses:
     *  - 204: Transferred.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param userRef 
     * @return [Unit]
     */
    @POST("v1/groups/{groupId}/transfer")
    public suspend fun transferGroup(@Path("groupId") groupId: java.util.UUID, @Body userRef: UserRef): Response<Unit>

    /**
     * DELETE v1/social/blocks/{userId}
     * 
     * 
     * Responses:
     *  - 204: Unblocked. Friendship does not come back.
     *  - 0: Any error, in the shared shape.
     *
     * @param userId 
     * @return [Unit]
     */
    @DELETE("v1/social/blocks/{userId}")
    public suspend fun unblockUser(@Path("userId") userId: java.util.UUID): Response<Unit>

    /**
     * POST v1/actions/{id}/undo
     * Apply an action&#39;s inverse. Journaled as its own action; undoing twice is 409.
     * 
     * Responses:
     *  - 200: The undo, as an action.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Action]
     */
    @POST("v1/actions/{id}/undo")
    public suspend fun undoAction(@Path("id") id: java.util.UUID): Response<Action>

    /**
     * POST v1/imports/{id}/undo
     * Undo an applied listening-history import (MUS-004): deletes the listens it wrote and the import. 409 `import_not_listens` for a library import (undo its action instead), 409 `import_not_applied` before it is applied (delete it instead).
     * 
     * Responses:
     *  - 204: Undone.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @POST("v1/imports/{id}/undo")
    public suspend fun undoListenImport(@Path("id") id: java.util.UUID): Response<Unit>

    /**
     * DELETE v1/me/sport-follows/{kind}/{providerId}
     * Stops following. Idempotent.
     * 
     * Responses:
     *  - 204: Not followed any more, or never was.
     *  - 0: Any error, in the shared shape.
     *
     * @param kind 
     * @param providerId 
     * @return [Unit]
     */
    @DELETE("v1/me/sport-follows/{kind}/{providerId}")
    public suspend fun unfollowSport(@Path("kind") kind: SportEntityKind, @Path("providerId") providerId: kotlin.String): Response<Unit>

    /**
     * DELETE v1/devices/{token}
     * 
     * 
     * Responses:
     *  - 204: Forgotten.
     *  - 0: Any error, in the shared shape.
     *
     * @param token 
     * @return [Unit]
     */
    @DELETE("v1/devices/{token}")
    public suspend fun unregisterDevice(@Path("token") token: kotlin.String): Response<Unit>

    /**
     * PATCH v1/groups/{groupId}/channels/{channelId}
     * Rename a channel or set its topic. Owner and admins.
     * 
     * Responses:
     *  - 200: The channel.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param channelId 
     * @param channelUpdate 
     * @return [Channel]
     */
    @PATCH("v1/groups/{groupId}/channels/{channelId}")
    public suspend fun updateChannel(@Path("groupId") groupId: java.util.UUID, @Path("channelId") channelId: java.util.UUID, @Body channelUpdate: ChannelUpdate): Response<Channel>

    /**
     * PATCH v1/groups/{groupId}
     * Rename the group. Owner and admins.
     * 
     * Responses:
     *  - 200: The group.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param groupCreate 
     * @return [GroupDetail]
     */
    @PATCH("v1/groups/{groupId}")
    public suspend fun updateGroup(@Path("groupId") groupId: java.util.UUID, @Body groupCreate: GroupCreate): Response<GroupDetail>

    /**
     * PATCH v1/groups/{groupId}/members/{userId}
     * Make a member an admin, or an admin a member. Owner only.
     * 
     * Responses:
     *  - 204: Changed.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param userId 
     * @param groupMemberUpdate 
     * @return [Unit]
     */
    @PATCH("v1/groups/{groupId}/members/{userId}")
    public suspend fun updateGroupMember(@Path("groupId") groupId: java.util.UUID, @Path("userId") userId: java.util.UUID, @Body groupMemberUpdate: GroupMemberUpdate): Response<Unit>

    /**
     * PATCH v1/library/items/{id}
     * 
     * 
     * Responses:
     *  - 200: The updated item.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param libraryItemPatch 
     * @return [LibraryEntry]
     */
    @PATCH("v1/library/items/{id}")
    public suspend fun updateLibraryItem(@Path("id") id: java.util.UUID, @Body libraryItemPatch: LibraryItemPatch): Response<LibraryEntry>

    /**
     * PUT v1/groups/{groupId}/me
     * Your own settings in a group. shareProgress shows your progress in its title channels; muted stops its mention alerts. Both are off by default.
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param groupId 
     * @param membershipUpdate 
     * @return [GroupSummary]
     */
    @PUT("v1/groups/{groupId}/me")
    public suspend fun updateMyMembership(@Path("groupId") groupId: java.util.UUID, @Body membershipUpdate: MembershipUpdate): Response<GroupSummary>

    /**
     * PUT v1/me/notifications
     * Changes the switches sent; any left out keep their value.
     * 
     * Responses:
     *  - 200: Saved.
     *  - 0: Any error, in the shared shape.
     *
     * @param notificationSettingsUpdate 
     * @return [NotificationSettings]
     */
    @PUT("v1/me/notifications")
    public suspend fun updateNotificationSettings(@Body notificationSettingsUpdate: NotificationSettingsUpdate): Response<NotificationSettings>

    /**
     * PUT v1/me/profile
     * Claim or change your handle, and your first and last name (SOC-001b). Handles are how friends find you; others see the two names joined. Every field is optional: one left out keeps its value. At most 10 handle changes a user per hour, a taken handle included (429).
     * 
     * Responses:
     *  - 200: Your account. It carries every field `SocialUser` did, so apps from before SOC-001b read it unchanged.
     *  - 0: Any error, in the shared shape.
     *
     * @param profileUpdate 
     * @return [Me]
     */
    @PUT("v1/me/profile")
    public suspend fun updateProfile(@Body profileUpdate: ProfileUpdate): Response<Me>

    /**
     * PATCH v1/shelves/{id}
     * 
     * 
     * Responses:
     *  - 200: OK.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @param updateShelf 
     * @return [Shelf]
     */
    @PATCH("v1/shelves/{id}")
    public suspend fun updateShelf(@Path("id") id: java.util.UUID, @Body updateShelf: UpdateShelf): Response<Shelf>

    /**
     * PUT v1/me/social-settings
     * 
     * 
     * Responses:
     *  - 200: Saved.
     *  - 0: Any error, in the shared shape.
     *
     * @param socialSettings 
     * @return [SocialSettings]
     */
    @PUT("v1/me/social-settings")
    public suspend fun updateSocialSettings(@Body socialSettings: SocialSettings): Response<SocialSettings>

    /**
     * PUT v1/me/avatar
     * Replace your avatar (SOC-001b) with one square JPEG of at most 1 MB; apps send 512px. Anything that is not a JPEG is refused with 415 `avatar_image_type`, a larger file with 413 `file_too_large`. It is seen by signed-in accounts wherever your name is, never signed out and never across a block.
     * 
     * Responses:
     *  - 200: Your account, with the new `avatarUrl`.
     *  - 0: Any error, in the shared shape.
     *
     * @param body 
     * @return [Me]
     */
    @PUT("v1/me/avatar")
    public suspend fun uploadAvatar(@Body body: java.io.File): Response<Me>

    /**
     * PUT v1/board/posts/{postId}/upvote
     * Upvote a post. Upvoting twice counts once. 404 unless the post is yours or a friend&#39;s.
     * 
     * Responses:
     *  - 204: Upvoted.
     *  - 0: Any error, in the shared shape.
     *
     * @param postId 
     * @return [Unit]
     */
    @PUT("v1/board/posts/{postId}/upvote")
    public suspend fun upvoteBoardPost(@Path("postId") postId: java.util.UUID): Response<Unit>

    /**
     * POST v1/auth/email/verify
     * Exchange a magic-link token, or the email and its 6-digit code, for a session. Creates the account on first use.
     * 
     * Responses:
     *  - 200: Signed in. The token is shown once.
     *  - 0: Any error, in the shared shape.
     *
     * @param magicLinkVerifyRequest 
     * @return [Session]
     */
    @POST("v1/auth/email/verify")
    public suspend fun verifyMagicLink(@Body magicLinkVerifyRequest: MagicLinkVerifyRequest): Response<Session>

    /**
     * DELETE v1/social/friend-requests/{id}
     * Decline a request to you, or cancel one you sent. The other side is not told.
     * 
     * Responses:
     *  - 204: Gone.
     *  - 0: Any error, in the shared shape.
     *
     * @param id 
     * @return [Unit]
     */
    @DELETE("v1/social/friend-requests/{id}")
    public suspend fun withdrawFriendRequest(@Path("id") id: java.util.UUID): Response<Unit>

}
