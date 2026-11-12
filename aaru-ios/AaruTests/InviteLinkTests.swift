import Foundation
import Testing
@testable import Aaru

/// A friend invite link (SOC-002): only `https://aaruapp.com/i/{code}` on Aaru's own hosts opens
/// the invite sheet.
struct InviteLinkTests {
    @Test(arguments: ["aaruapp.com", "www.aaruapp.com", "beta.aaruapp.com"])
    func anInviteOnAaruHostsIsRead(host: String) throws {
        let url = try #require(URL(string: "https://\(host)/i/Ab3dE9"))

        #expect(InviteLink(url)?.code == "Ab3dE9")
    }

    @Test(arguments: [
        "http://aaruapp.com/i/Ab3dE9", // not https
        "https://aaruapp.com.example.org/i/Ab3dE9", // someone else's host
        "https://example.org/i/Ab3dE9",
        "https://aaruapp.com/s/Ab3dE9", // a share link, not an invite
        "https://aaruapp.com/i", // no code
        "https://aaruapp.com/i/Ab3dE9/extra",
        "https://aaruapp.com/i/has-dash",
        "https://aaruapp.com/i/abcdefghijklmnopqrstuvwxyz0123456", // 33 characters
        "aaru://i/Ab3dE9",
    ])
    func anythingElseIsNotAnInvite(link: String) throws {
        let url = try #require(URL(string: link))

        #expect(InviteLink(url) == nil)
    }

    @Test func aQueryOrFragmentDoesNotChangeTheCode() throws {
        let url = try #require(URL(string: "https://aaruapp.com/i/Ab3dE9?utm=x#top"))

        #expect(InviteLink(url)?.code == "Ab3dE9")
    }

    @Test func anInviteIsKnownByItsCode() throws {
        let url = try #require(URL(string: "https://aaruapp.com/i/Ab3dE9"))
        let other = try #require(URL(string: "https://beta.aaruapp.com/i/Ab3dE9"))

        #expect(InviteLink(url)?.id == "Ab3dE9")
        #expect(InviteLink(url) == InviteLink(other))
    }
}
