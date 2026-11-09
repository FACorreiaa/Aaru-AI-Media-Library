import AaruAPI
import AaruCore

extension Onboarding {
    /// The app's status (the API's) as AaruCore's: the same raw values, a wire contract.
    static func coreStatus(_ status: LibraryStatus) -> AaruCore.LibraryStatus {
        AaruCore.LibraryStatus(rawValue: status.rawValue) ?? .wishlist
    }

    static func apiStatus(_ status: AaruCore.LibraryStatus) -> LibraryStatus {
        LibraryStatus(rawValue: status.rawValue) ?? .wishlist
    }
}

extension OnboardingKind: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    init(_ kind: MediaKind) {
        switch kind {
        case .film: self = .film
        case .show: self = .show
        case .anime: self = .anime
        case .manga: self = .manga
        case .book: self = .book
        case .music: self = .album
        }
    }

    var mediaKind: MediaKind {
        switch self {
        case .film: .film
        case .show: .show
        case .anime: .anime
        case .manga: .manga
        case .book: .book
        case .album: .music
        }
    }

    var rowKind: Components.Schemas.DiscoverRowKind {
        switch self {
        case .film: .film
        case .show: .show
        case .anime: .anime
        case .manga: .manga
        case .book: .book
        case .album: .album
        }
    }

    var favoriteKind: FavoriteKind {
        switch self {
        case .film: .film
        case .show: .show
        case .anime: .anime
        case .manga: .manga
        case .book: .book
        case .album: .album
        }
    }

    /// Airing alerts follow shows and anime alone.
    var airs: Bool {
        self == .show || self == .anime
    }

    /// "Films", "Shows", "Anime", "Manga", "Books", "Albums".
    var label: String {
        self == .album ? "Albums" : mediaKind.label
    }

    /// A picker screen's headline.
    var pickHeading: String {
        switch self {
        case .film: "Pick films you've watched"
        case .show: "Pick shows you watch"
        case .anime: "Pick anime you watch"
        case .manga: "Pick manga you've read"
        case .book: "Pick books you've read"
        case .album: "Pick albums you've heard"
        }
    }

    /// The pill at the bottom of a picker: "Continue (3)", or "Skip shows" with nothing picked.
    func continueLabel(count: Int) -> String {
        count > 0 ? "Continue (\(count))" : "Skip \(self == .anime || self == .manga ? rawValue : label.lowercased())"
    }
}
