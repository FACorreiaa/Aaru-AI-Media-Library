/// How one title stands to another in the catalog (GRAPH-001), read "B is A's relation".
///
/// Catalog data, never a library write and never a recommendation. The raw values are a wire
/// contract shared with the server's `core.Relation`; the two must not diverge in meaning.
public enum Relation: String, Codable, Hashable, Sendable, CaseIterable {
    case prequel
    case sequel
    case sideStory = "side_story"
    case spinOff = "spin_off"
    case adaptation
    case source
    case alternative
    case summary
    case parent
    case other

    /// Prequels and sequels: the line a graph draws first and "Start here" walks.
    public var isMainChain: Bool {
        self == .prequel || self == .sequel
    }

    /// The same fact written forward, so each pair is stored once: a prequel is the other title's
    /// sequel, a source the other title's adaptation, a parent the other title's side story.
    /// `flipped` is true when the two ends swap.
    public var canonical: (relation: Relation, flipped: Bool) {
        switch self {
        case .prequel: (.sequel, true)
        case .source: (.adaptation, true)
        case .parent: (.sideStory, true)
        default: (self, false)
        }
    }
}
