import AaruCore
import Foundation

/// What a share link is asked to point at, before the title is resolved.
enum ShareRequest: Sendable {
    case title(MediaRef)
    case sportEvent(String)
    case concert(String)
}

/// What a share link shows. The content is public; `from` is there only for the sender and
/// their friends.
struct SharePreview: Sendable {
    var share: Share
    var title: TitleDetail?
    var sportEvent: SportEvent?
    var concert: Concert?
    /// The provider could not give the event right now; the content is then nil.
    var unavailable: Bool
    var from: (sender: SocialUser, note: String?)?
    /// The signed-in viewer's own item for a shared title.
    var viewerItem: LibraryItem?
}

/// Share links (SHR-002): a public, reusable link to one title, sport event or concert. Anyone
/// can open it; only the sender and their friends see who sent it and the note, never across a
/// block. Titles are resolved when the link is made, so opening one reads the catalog row; events
/// go through the shared sports and concert caches. Nothing about an event is stored.
struct ShareService: Sendable {
    let stores: Stores
    /// Its resolver turns a shared ref into a catalog title; its catalog reads the title back.
    let library: LibraryService
    let sports: SportsService
    let concerts: ConcertService
    /// The web origin a link opens on; the apps claim the same paths as universal links.
    var webBaseURL = URL(string: "https://aaruapp.com")!
    var now: @Sendable () -> Date = { Date() }

    static let codeLength = InviteService.codeLength
    static let maxNote = 140
    static let createsPerHour = 60
    /// High enough for one link opened by a whole group chat; the caches carry the provider cost.
    static let previewsPerHour = 600

    let createLimiter = FixedWindowRateLimiter(limit: createsPerHour, window: 60 * 60)
    /// Public, so limited per client address (best effort: the address is only a rate-limit key).
    let previewLimiter = FixedWindowRateLimiter(limit: previewsPerHour, window: 60 * 60)

    static let noSuchShare = AppError.notFound("This link doesn't work anymore.")

    var social: SocialService {
        SocialService(stores: stores, now: now)
    }

    func url(_ share: Share) -> URL {
        webBaseURL.appending(path: "s/\(share.code)")
    }

    // MARK: Sender

    /// Makes a link, or gives back the sender's link to the same target with the same note.
    func create(_ viewer: UserID, _ request: ShareRequest, note: String?) async throws -> Share {
        guard await createLimiter.allow(viewer.description, now: now()) else { throw Self.rateLimited }
        let note = try Self.validNote(note)
        let target: ShareTarget = switch request {
        case let .title(ref): try await .title(library.resolver.resolve(ref).id)
        case let .sportEvent(id): try await .sportEvent(knownSportEvent(id))
        case let .concert(id): try await .concert(knownConcert(id))
        }
        if let existing = try await stores.shares.existingShare(sender: viewer, target: target, note: note) {
            return existing
        }
        for _ in 0 ..< 3 {
            let share = Share(
                code: InviteService.newCode(), senderID: viewer, target: target, note: note, createdAt: now()
            )
            do {
                try await stores.shares.createShare(share)
                ProductEvents.capture(.shareCreated, userID: viewer, ["kind": target.kind])
                return share
            } catch is StoreConflict {
                continue
            }
        }
        throw AppError(status: .internalServerError, code: "internal", message: "Couldn't make a link. Try again.")
    }

    // MARK: Opener

    /// What the link shows. `viewer` is nil when the person opening it is signed out.
    func preview(code: String, viewer: UserID?, clientAddress: String) async throws -> SharePreview {
        guard await previewLimiter.allow(clientAddress, now: now()) else { throw Self.rateLimited }
        guard let share = try await stores.shares.share(code: code) else { throw Self.noSuchShare }
        var preview = SharePreview(share: share, unavailable: false)
        switch share.target {
        case let .title(id):
            // The catalog row only: a public page never hydrates episodes or tracks (SHR-002), so
            // a provider outage or a burst of opens costs nothing and fails nothing.
            guard let title = try await stores.titles.title(id: id),
                  let state = try await stores.titles.catalogState(id)
            else { throw Self.noSuchShare }
            preview.title = TitleDetail(
                title: title, status: state.status, runtimeMinutes: state.runtimeMinutes, episodes: nil
            )
            if let viewer {
                preview.viewerItem = try await stores.library.item(userID: viewer, titleID: id)
            }
        case let .sportEvent(id):
            preview.sportEvent = try? await sports.publicEvent(id: id)
            preview.unavailable = preview.sportEvent == nil
        case let .concert(id):
            preview.concert = await concerts.concert(id: id)
            preview.unavailable = preview.concert == nil
        }
        if let sender = share.senderID {
            if let viewer, try await mayKnowSender(viewer, sender),
               let user = try await stores.social.socialUser(sender)
            {
                preview.from = (user, share.note)
            }
            ProductEvents.capture(.shareOpened, userID: sender, ["kind": share.target.kind])
        }
        return preview
    }

    // MARK: Rules

    /// The sender and their friends see who sent it. A block either way hides it, and only it:
    /// the content stays public.
    private func mayKnowSender(_ viewer: UserID, _ sender: UserID) async throws -> Bool {
        do {
            switch try await social.relationship(viewer, sender) {
            case .self, .friend: return true
            case .none, .incoming, .outgoing: return false
            }
        } catch is AppError {
            return false
        }
    }

    /// A match the provider knows; validating here keeps junk ids from costing calls later.
    private func knownSportEvent(_ id: String) async throws -> String {
        let id = try Self.validSportID(id)
        guard (try? await sports.publicEvent(id: id)) ?? nil != nil else {
            throw Self.invalid("That match isn't available to share.")
        }
        return id
    }

    /// A concert the provider knows, for the same reason.
    private func knownConcert(_ id: String) async throws -> String {
        let id = try Self.validConcertID(id)
        guard await concerts.concert(id: id) != nil
        else { throw Self.invalid("That concert isn't available to share.") }
        return id
    }

    static func validNote(_ note: String?) throws -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        // Unicode scalars, as Postgres's char_length counts them: an emoji with a skin tone is two.
        guard trimmed.unicodeScalars.count <= maxNote else { throw invalid("A note is at most \(maxNote) characters.") }
        return trimmed
    }

    static func validSportID(_ id: String) throws -> String {
        guard (1 ... 40).contains(id.count), id.allSatisfy(\.isASCII), id.allSatisfy(\.isNumber) else {
            throw invalid("That isn't a sports event.")
        }
        return id
    }

    static func validConcertID(_ id: String) throws -> String {
        guard id.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil else { throw invalid("That isn't a concert.") }
        return id
    }

    static func invalid(_ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message)
    }

    private static let rateLimited = AppError(
        status: .tooManyRequests, code: "rate_limited", message: "Too many links. Try again later."
    )
}
