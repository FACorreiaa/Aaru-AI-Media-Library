import Testing
@testable import Aaru

/// PRV-002: when Aaru asks about AI sharing without being asked to, and what counts as tagging
/// `@aaru` in a group message.
struct AISharingAskTests {
    @Test func anAccountPastItsFirstRunWithNoAnswerIsAskedOnOpen() {
        #expect(AISharingAsk.asksOnOpen(onboardingPending: false, state: .unanswered, firstRunEndedThisLaunch: false))
    }

    @Test(arguments: [AISharingState.allowed, .declined])
    func anAnswerEndsTheAsking(state: AISharingState) {
        #expect(!AISharingAsk.asksOnOpen(onboardingPending: false, state: state, firstRunEndedThisLaunch: false))
    }

    @Test func theFirstRunAsksItself() {
        #expect(!AISharingAsk.asksOnOpen(onboardingPending: true, state: .unanswered, firstRunEndedThisLaunch: false))
    }

    @Test func aFirstRunThatJustEndedWaitsForTheNextOpen() {
        #expect(!AISharingAsk.asksOnOpen(onboardingPending: false, state: .unanswered, firstRunEndedThisLaunch: true))
    }

    @Test func nothingIsAskedOnAGuess() {
        // `Me` was not read: neither value is known.
        #expect(!AISharingAsk.asksOnOpen(onboardingPending: nil, state: nil, firstRunEndedThisLaunch: false))
        #expect(!AISharingAsk.asksOnOpen(onboardingPending: false, state: nil, firstRunEndedThisLaunch: false))
        #expect(!AISharingAsk.asksOnOpen(onboardingPending: nil, state: .unanswered, firstRunEndedThisLaunch: false))
    }

    @Test(arguments: [
        "@aaru what should I watch?",
        "hey @Aaru, what's next",
        "what about this one (@AARU)",
        "line one\n@aaru",
        "@ana and @aaru",
    ])
    func aTagOfAaruIsFound(body: String) {
        #expect(AISharingAsk.tagsAaru(body))
    }

    @Test(arguments: [
        "aaru is great",
        "mail me at owl@aaru.example",
        "@aarument",
        "@aaru_fan",
        "@@aaru",
        "@aaru@home",
        "@ aaru",
        "",
    ])
    func anythingElseIsNot(body: String) {
        #expect(!AISharingAsk.tagsAaru(body))
    }
}
