import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: FavoriteStore {
    func favorites(of _: UserID) async throws -> [FavoriteKind: [TitleID]] {
        throw Touched()
    }

    func replaceFavorites(_: [TitleID], kind _: FavoriteKind, for _: UserID) async throws {
        throw Touched()
    }
}
