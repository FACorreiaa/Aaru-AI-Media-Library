/// Why a value is not acceptable as Aaru data.
///
/// Shared so the server and the clients reject the same inputs with the same words.
public enum ValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case emptyTitle
    case invalidYear(Int)
    case ratingOutOfRange(Double)
    case ratingNotInHalfSteps(Double)
    case emptyListName
    case invalidEpisodeNumber(season: Int, episode: Int)
    case invalidBookProgress
    case unresolvableMediaRef

    public var description: String {
        switch self {
        case .emptyTitle:
            "Title text must not be empty."
        case .invalidYear(let year):
            "Year \(year) is outside \(Title.validYears.lowerBound)–\(Title.validYears.upperBound)."
        case .ratingOutOfRange(let value):
            "Rating \(value) is outside \(Rating.scale.lowerBound)–\(Rating.scale.upperBound)."
        case .ratingNotInHalfSteps(let value):
            "Rating \(value) is not a multiple of \(Rating.step)."
        case .emptyListName:
            "List name must not be empty."
        case .invalidEpisodeNumber(let season, let episode):
            "Season \(season) episode \(episode) is not a valid episode reference."
        case .invalidBookProgress:
            "Book progress needs a non-negative page or a percent between 0 and 100."
        case .unresolvableMediaRef:
            "A media reference needs a title id, an external id, or a title and year."
        }
    }
}
