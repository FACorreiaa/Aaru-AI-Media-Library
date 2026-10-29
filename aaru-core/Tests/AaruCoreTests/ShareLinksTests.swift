import Foundation
import Testing
@testable import AaruCore

struct ShareLinkCodeTests {
    @Test(arguments: [
        "https://aaruapp.com/s/k7Q2xPa9Lm3Z",
        "https://www.aaruapp.com/s/k7Q2xPa9Lm3Z",
        "https://beta.aaruapp.com/s/k7Q2xPa9Lm3Z/",
        "https://aaruapp.com/s/k7Q2xPa9Lm3Z?add=1",
    ])
    func readsTheCode(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ShareLinkCode.code(in: url) == "k7Q2xPa9Lm3Z")
    }

    @Test(arguments: [
        "http://aaruapp.com/s/abc",
        "https://evil.example/s/abc",
        "https://aaruapp.com/s/",
        "https://aaruapp.com/s/a/b",
        "https://aaruapp.com/i/abc",
        "https://aaruapp.com/s/ab-c",
        "https://aaruapp.com/s/" + String(repeating: "a", count: 33),
        "https://aaruapp.com/s/../x",
    ])
    func refusesAnythingElse(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ShareLinkCode.code(in: url) == nil)
    }
}

struct ShareAutoAddTests {
    @Test func addsOnReturnFromSignIn() {
        #expect(ShareAutoAdd.should(
            add: true, signedIn: true, isTitle: true, unavailable: false, alreadyInLibrary: false
        ))
    }

    struct Case: Sendable, CustomTestStringConvertible {
        var add = true
        var signedIn = true
        var isTitle = true
        var unavailable = false
        var alreadyInLibrary = false
        let testDescription: String
    }

    @Test(arguments: [
        Case(add: false, testDescription: "not asked"),
        Case(signedIn: false, testDescription: "signed out"),
        Case(isTitle: false, testDescription: "not a title"),
        Case(unavailable: true, testDescription: "unavailable"),
        Case(alreadyInLibrary: true, testDescription: "already theirs"),
    ])
    func addsNothingOtherwise(_ input: Case) {
        #expect(!ShareAutoAdd.should(
            add: input.add, signedIn: input.signedIn, isTitle: input.isTitle,
            unavailable: input.unavailable, alreadyInLibrary: input.alreadyInLibrary
        ))
    }
}

struct ShareLoadFailureTests {
    @Test func unknownCodeIsMissing() {
        #expect(ShareLoadFailure.after(status: 404, showingContent: false) == .missing)
    }

    @Test(arguments: [nil, 429, 500, 503] as [Int?])
    func anythingElseOffersARetry(_ status: Int?) {
        #expect(ShareLoadFailure.after(status: status, showingContent: false) == .retry)
    }

    @Test(arguments: [nil, 404, 429, 500] as [Int?])
    func aFailedReloadKeepsTheCard(_ status: Int?) {
        #expect(ShareLoadFailure.after(status: status, showingContent: true) == .keep)
    }
}
