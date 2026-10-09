import AaruCore

// The data layer boundary (SRV-003). Request handlers see only these protocols;
// Fluent and SQL stay behind them. Methods arrive with the ticket that needs them —
// these are what the M1 migrations must prove, nothing speculative.

/// A write broke a uniqueness rule the database enforces.
struct StoreConflict: Error, Sendable {
    let message: String
}

/// How a user signed in. One user may have several.
struct AuthIdentity: Sendable, Hashable {
    enum Provider: String, Sendable {
        case apple
        case email
    }

    var provider: Provider
    var subject: String
    var email: String?
}

protocol DatabaseHealth: Sendable {
    /// True when the database answers a trivial query. Never throws, never leaks detail.
    func isReachable() async -> Bool
}

protocol UserStore: Sendable {
    /// Creates a user with its first identity, or throws `StoreConflict` if the identity exists.
    func createUser(with identity: AuthIdentity) async throws -> UserID
    func user(for provider: AuthIdentity.Provider, subject: String) async throws -> UserID?
}

protocol TitleStore: Sendable {
    /// Throws `StoreConflict` when another title already holds one of its external ids.
    func insert(_ title: Title) async throws
    func title(id: TitleID) async throws -> Title?
}

protocol LibraryStore: Sendable {
    /// Throws `StoreConflict` when the user already has an item for the title.
    func insert(_ item: LibraryItem) async throws
    func item(id: LibraryItemID, userID: UserID) async throws -> LibraryItem?
}

protocol ListStore: Sendable {
    func create(_ list: AaruList) async throws
    func lists(userID: UserID) async throws -> [AaruList]
}

protocol ImportJobStore: Sendable {
    func insert(_ job: ImportJob) async throws
    func update(_ job: ImportJob) async throws
    func job(id: ImportJobID, userID: UserID) async throws -> ImportJob?
}

/// Everything handlers may touch, injected once at boot.
struct Stores: Sendable {
    var health: any DatabaseHealth
    var users: any UserStore
    var titles: any TitleStore
    var library: any LibraryStore
    var lists: any ListStore
    var importJobs: any ImportJobStore
}
