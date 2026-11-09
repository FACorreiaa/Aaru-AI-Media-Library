/// A new account's first run (ONB-001, DESIGN.md §0a): the pure part. The status a tap on a
/// poster moves to, and which screens the flow shows. The web holds the same cases in
/// `aaru-client/src/lib/onboarding/model.ts`; the two must not diverge in meaning.
public enum Onboarding {
    /// The six kinds a first run asks about, in Library's order: the order of the picker screens.
    /// Anime is its own kind here although the catalog calls it a show or a film.
    public enum Kind: String, CaseIterable, Codable, Hashable, Sendable {
        case film, show, anime, manga, book, album

        /// A film or an album is seen or heard in one go, so its cycle has no Watching or
        /// Listening.
        var hasInProgress: Bool {
            self != .film && self != .album
        }

        /// Airing alerts follow shows and anime alone (`DueAirings`).
        var airs: Bool {
            self == .show || self == .anime
        }
    }

    /// One screen of the flow.
    public enum Step: Hashable, Sendable {
        /// "What do you keep?": the kinds.
        case kinds
        /// "Pick shows you watch", one per chosen kind.
        case pick(Kind)
        /// The finished picks, to star.
        case favorites
        /// "More from what you picked": relation data, never a recommendation.
        case related
        /// "Never miss a new episode".
        case notifications

        /// The kind a picker step is for; nil for every other step.
        public var kind: Kind? {
            if case let .pick(kind) = self {
                kind
            } else {
                nil
            }
        }
    }

    /// One pick as the step list reads it: its kind and the status it carries.
    public struct Pick: Hashable, Sendable {
        public var kind: Kind
        public var status: LibraryStatus

        public init(kind: Kind, status: LibraryStatus) {
            self.kind = kind
            self.status = status
        }
    }

    /// The status one tap on a poster moves to. The first tap says you have watched, read or heard
    /// it; the next go through Watching / Reading (where the kind has it) and Plan to…, then off
    /// (nil). A status the cycle does not hold (on hold or dropped, from the menu) starts it over.
    public static func nextStatus(_ current: LibraryStatus?, kind: Kind) -> LibraryStatus? {
        let cycle: [LibraryStatus?] = kind.hasInProgress
            ? [nil, .finished, .inProgress, .wishlist]
            : [nil, .finished, .wishlist]
        guard let index = cycle.firstIndex(of: current) else { return .finished }
        return cycle[(index + 1) % cycle.count]
    }

    /// The screens, in order. Pickers follow Library's kind order whatever order the kinds were
    /// chosen in; favorites need a finished pick, related titles a non-empty answer, and the alerts
    /// screen a show or anime in progress and a device that can take push.
    public static func steps(
        kinds: some Collection<Kind>,
        picks: some Collection<Pick>,
        hasRelated: Bool,
        pushSupported: Bool
    ) -> [Step] {
        var list: [Step] = [.kinds]
        list += Kind.allCases.filter(kinds.contains).map(Step.pick)
        if picks.contains(where: { $0.status == .finished }) {
            list.append(.favorites)
        }
        if hasRelated {
            list.append(.related)
        }
        if pushSupported, picks.contains(where: { $0.kind.airs && $0.status == .inProgress }) {
            list.append(.notifications)
        }
        return list
    }
}
