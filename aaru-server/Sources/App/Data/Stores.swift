import AaruCore
import Foundation

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
    func createUser(with identity: AuthIdentity, displayName: String?) async throws -> UserID
    func user(for provider: AuthIdentity.Provider, subject: String) async throws -> UserID?
    func profile(_ id: UserID) async throws -> UserProfile?
    /// Deletes the user and, by cascade, every row that belongs to them, plus the
    /// magic links sent to their email identities (AUTH-004).
    func deleteUser(_ id: UserID) async throws
}

struct UserProfile: Sendable, Equatable {
    var id: UserID
    var displayName: String?
    var providers: [AuthIdentity.Provider]
}

protocol SessionStore: Sendable {
    func create(userID: UserID, tokenHash: String, expiresAt: Date) async throws
    /// The session's user, or nil when the token is unknown or expired.
    func userID(forTokenHash tokenHash: String, now: Date) async throws -> UserID?
    func delete(tokenHash: String) async throws
}

protocol MagicLinkStore: Sendable {
    func create(email: String, tokenHash: String, expiresAt: Date) async throws
    /// Atomically marks the link used and returns its email. Nil when the link is
    /// unknown, expired, or already used — a link signs in once.
    func consume(tokenHash: String, now: Date) async throws -> String?
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
    var sessions: any SessionStore
    var magicLinks: any MagicLinkStore
    var titles: any TitleStore
    var library: any LibraryStore
    var lists: any ListStore
    var importJobs: any ImportJobStore
}
