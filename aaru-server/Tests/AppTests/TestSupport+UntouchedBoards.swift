import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: BoardStore {
    func createPost(_: BoardPost) async throws -> BoardPost {
        throw Touched()
    }

    func post(_: UUID, viewer _: UserID) async throws -> BoardPost? {
        throw Touched()
    }

    func feed(authors _: [UserID], before _: UUID?, limit _: Int, viewer _: UserID) async throws -> [BoardPost] {
        throw Touched()
    }

    func top(authors _: [UserID], since _: Date, limit _: Int, viewer _: UserID) async throws -> [BoardPost] {
        throw Touched()
    }

    func posts(title _: TitleID, authors _: [UserID], limit _: Int, viewer _: UserID) async throws -> [BoardPost] {
        throw Touched()
    }

    func editPost(_: UUID, body _: String, now _: Date) async throws {
        throw Touched()
    }

    func deletePost(_: UUID, now _: Date) async throws {
        throw Touched()
    }

    func setUpvote(post _: UUID, user _: UserID, on _: Bool) async throws {
        throw Touched()
    }

    func upvoters(post _: UUID) async throws -> [SocialUser] {
        throw Touched()
    }

    func addComment(_: BoardComment) async throws -> BoardComment {
        throw Touched()
    }

    func comment(_: UUID, post _: UUID) async throws -> BoardComment? {
        throw Touched()
    }

    func comments(post _: UUID, after _: UUID?, limit _: Int) async throws -> [BoardComment] {
        throw Touched()
    }

    func deleteComment(_: UUID, now _: Date) async throws {
        throw Touched()
    }
}
