import Testing
@testable import AaruCore

struct OnboardingTests {
    typealias Kind = Onboarding.Kind

    /// Taps from off until the cycle comes back to off.
    private func cycle(_ kind: Kind) -> [LibraryStatus?] {
        var seen: [LibraryStatus?] = []
        var status = Onboarding.nextStatus(nil, kind: kind)
        while let current = status, seen.count < 10 {
            seen.append(current)
            status = Onboarding.nextStatus(current, kind: kind)
        }
        return seen + [status]
    }

    @Test(arguments: [Kind.show, .anime, .book, .manga])
    func kindsYouCanBeInTheMiddleOfCycleThroughInProgress(kind: Kind) {
        #expect(cycle(kind) == [.finished, .inProgress, .wishlist, nil])
    }

    @Test(arguments: [Kind.film, .album])
    func filmsAndAlbumsSkipInProgress(kind: Kind) {
        #expect(cycle(kind) == [.finished, .wishlist, nil])
    }

    @Test func aStatusFromTheMenuStartsTheCycleOver() {
        #expect(Onboarding.nextStatus(.onHold, kind: .show) == .finished)
        #expect(Onboarding.nextStatus(.dropped, kind: .film) == .finished)
        // In progress picked from the menu on a film still moves on.
        #expect(Onboarding.nextStatus(.inProgress, kind: .film) == .finished)
    }

    @Test func noKindsIsJustTheFirstScreen() {
        let steps = Onboarding.steps(kinds: [Kind](), picks: [], hasRelated: false, pushSupported: true)
        #expect(steps == [.kinds])
    }

    @Test func pickersFollowLibraryOrderNotTapOrder() {
        let steps = Onboarding.steps(
            kinds: [Kind.album, .book, .film, .anime], picks: [], hasRelated: false, pushSupported: true
        )
        #expect(steps == [.kinds, .pick(.film), .pick(.anime), .pick(.book), .pick(.album)])
        #expect(steps.compactMap(\.kind) == [.film, .anime, .book, .album])
    }

    @Test func favoritesNeedAFinishedPick() {
        let planned = [Onboarding.Pick(kind: .film, status: .wishlist)]
        #expect(!Onboarding.steps(kinds: [Kind.film], picks: planned, hasRelated: false, pushSupported: false)
            .contains(.favorites))
        let watched = planned + [Onboarding.Pick(kind: .film, status: .finished)]
        #expect(Onboarding.steps(kinds: [Kind.film], picks: watched, hasRelated: false, pushSupported: false)
            == [.kinds, .pick(.film), .favorites])
    }

    @Test func relatedOnlyWhenThereIsSome() {
        #expect(Onboarding.steps(kinds: [Kind.book], picks: [], hasRelated: true, pushSupported: false)
            == [.kinds, .pick(.book), .related])
    }

    @Test func alertsNeedAShowOrAnimeInProgressAndPush() {
        let watching = [Onboarding.Pick(kind: .anime, status: .inProgress)]
        #expect(Onboarding.steps(kinds: [Kind.anime], picks: watching, hasRelated: false, pushSupported: true)
            == [.kinds, .pick(.anime), .notifications])
        #expect(!Onboarding.steps(kinds: [Kind.anime], picks: watching, hasRelated: false, pushSupported: false)
            .contains(.notifications))
        // A book in progress airs nothing; a show only planned or watched neither.
        let other = [
            Onboarding.Pick(kind: .book, status: .inProgress),
            Onboarding.Pick(kind: .show, status: .wishlist),
            Onboarding.Pick(kind: .show, status: .finished),
        ]
        #expect(!Onboarding.steps(kinds: [Kind.show, .book], picks: other, hasRelated: false, pushSupported: true)
            .contains(.notifications))
    }

    @Test func everyStepInItsPlace() {
        let picks = [
            Onboarding.Pick(kind: .show, status: .inProgress),
            Onboarding.Pick(kind: .film, status: .finished),
        ]
        #expect(Onboarding.steps(kinds: [Kind.show, .film], picks: picks, hasRelated: true, pushSupported: true)
            == [.kinds, .pick(.film), .pick(.show), .favorites, .related, .notifications])
    }
}
