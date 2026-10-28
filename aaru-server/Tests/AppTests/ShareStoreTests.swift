import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Share link store (SHR-002)", .serialized)
struct ShareStoreTests {
    private func share(_ sender: UserID?, _ target: ShareTarget, note: String? = nil) -> Share {
        Share(
            code: ShareStoreTests.code(), senderID: sender, target: target, note: note,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func code() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
    }

    private func title(_ stores: Stores) async throws -> TitleID {
        let title = Title(id: TitleID(), type: .movie, title: "Arrival")
        try await stores.titles.insert(title)
        return title.id
    }

    @Test("each target kind round-trips, an unknown code is nil, a taken code conflicts")
    func roundTrip() async throws {
        try await withMigratedStores { stores in
            let (sender, _) = try await signedInUser(stores)
            let titleID = try await title(stores)
            for target in [ShareTarget.title(titleID), .sportEvent("2052711"), .concert("Z7r9jZ1A7jx")] {
                let made = share(sender, target, note: "watch this")
                try await stores.shares.createShare(made)
                #expect(try await stores.shares.share(code: made.code) == made)
                await #expect(throws: StoreConflict.self) {
                    try await stores.shares.createShare(share(sender, target).with(code: made.code))
                }
            }
            #expect(try await stores.shares.share(code: "nope12345678") == nil)
        }
    }

    @Test("the same sender, target and note find the same link; another note or sender does not")
    func dedupeByNote() async throws {
        try await withMigratedStores { stores in
            let (sender, _) = try await signedInUser(stores)
            let (other, _) = try await signedInUser(stores)
            let titleID = try await title(stores)
            let withNote = share(sender, .title(titleID), note: "hi")
            let bare = share(sender, .title(titleID))
            try await stores.shares.createShare(withNote)
            try await stores.shares.createShare(bare)
            #expect(try await stores.shares.existingShare(sender: sender, target: .title(titleID), note: "hi") == withNote)
            #expect(try await stores.shares.existingShare(sender: sender, target: .title(titleID), note: nil) == bare)
            #expect(try await stores.shares.existingShare(sender: sender, target: .title(titleID), note: "yo") == nil)
            #expect(try await stores.shares.existingShare(sender: other, target: .title(titleID), note: nil) == nil)
            #expect(try await stores.shares.existingShare(sender: sender, target: .sportEvent("1"), note: nil) == nil)
        }
    }

    @Test("deleting the sender's account keeps the link and drops their name and note")
    func accountDeleteKeepsLink() async throws {
        try await withMigratedStores { stores in
            let (sender, _) = try await signedInUser(stores)
            let made = share(sender, .concert("Z7r9jZ1A7jx"), note: "secret")
            try await stores.shares.createShare(made)
            try await stores.users.deleteUser(sender)
            let kept = try #require(try await stores.shares.share(code: made.code))
            #expect(kept.senderID == nil)
            #expect(kept.note == nil)
            #expect(kept.target == .concert("Z7r9jZ1A7jx"))
        }
    }
}

private extension Share {
    func with(code: String) -> Share {
        var copy = self
        copy.code = code
        return copy
    }
}
