import Foundation

/// Everything handlers may touch, injected once at boot. A class: nearly every service keeps
/// it, and copied by value (30-odd existentials each time) it made `Services` large enough to
/// overflow a debug test thread's stack.
final class Stores: Sendable {
    let health: any DatabaseHealth
    let users: any UserStore
    let sessions: any SessionStore
    let magicLinks: any MagicLinkStore
    let titles: any TitleStore
    let animeMappings: any AnimeMappingStore
    let library: any LibraryStore
    let lists: any ListStore
    let shelves: any ShelfStore
    let schedule: any ScheduleStore
    let stats: any StatsStore
    let importJobs: any ImportJobStore
    let trakt: any TraktStore
    let mal: any MALStore
    let push: any PushStore
    let agentTokens: any AgentTokenStore
    let watchEvents: any WatchEventStore
    let listens: any ListenStore
    let plans: any PlanStore
    let oauth: any OAuthStore
    let social: any SocialStore
    let friendViews: any FriendViewStore
    let interactions: any InteractionStore
    let groups: any GroupStore
    let groupKinds: any GroupKindStore
    let agent: any AgentStore
    let concerts: any ConcertStore
    let gamification: any GamificationStore
    let tonight: any TonightStore
    let capture: any CaptureStore
    let entitlements: any EntitlementStore
    let boards: any BoardStore
    let favorites: any FavoriteStore

    init(
        health: any DatabaseHealth,
        users: any UserStore,
        sessions: any SessionStore,
        magicLinks: any MagicLinkStore,
        titles: any TitleStore,
        animeMappings: any AnimeMappingStore,
        library: any LibraryStore,
        lists: any ListStore,
        shelves: any ShelfStore,
        schedule: any ScheduleStore,
        stats: any StatsStore,
        importJobs: any ImportJobStore,
        trakt: any TraktStore,
        mal: any MALStore,
        push: any PushStore,
        agentTokens: any AgentTokenStore,
        watchEvents: any WatchEventStore,
        listens: any ListenStore,
        plans: any PlanStore,
        oauth: any OAuthStore,
        social: any SocialStore,
        friendViews: any FriendViewStore,
        interactions: any InteractionStore,
        groups: any GroupStore,
        groupKinds: any GroupKindStore,
        agent: any AgentStore,
        concerts: any ConcertStore,
        gamification: any GamificationStore,
        tonight: any TonightStore,
        capture: any CaptureStore,
        entitlements: any EntitlementStore,
        boards: any BoardStore,
        favorites: any FavoriteStore
    ) {
        self.health = health
        self.users = users
        self.sessions = sessions
        self.magicLinks = magicLinks
        self.titles = titles
        self.animeMappings = animeMappings
        self.library = library
        self.lists = lists
        self.shelves = shelves
        self.schedule = schedule
        self.stats = stats
        self.importJobs = importJobs
        self.trakt = trakt
        self.mal = mal
        self.push = push
        self.agentTokens = agentTokens
        self.watchEvents = watchEvents
        self.listens = listens
        self.plans = plans
        self.oauth = oauth
        self.social = social
        self.friendViews = friendViews
        self.interactions = interactions
        self.groups = groups
        self.groupKinds = groupKinds
        self.agent = agent
        self.concerts = concerts
        self.gamification = gamification
        self.tonight = tonight
        self.capture = capture
        self.entitlements = entitlements
        self.boards = boards
        self.favorites = favorites
    }
}
