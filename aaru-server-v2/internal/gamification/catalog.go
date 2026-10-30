package gamification

import (
	"strconv"
	"strings"
)

// Facts is everything the badge rules read, gathered for one user in one pass (AchievementFacts,
// GAM-004).
//
// Milestone facts come from the library and the other tables a user owns, so imported history
// counts. Activity facts come from the points ledger and streak days, which only live writes
// fill (owner decision 2026-10-22).
type Facts struct {
	// Library (imports count)
	FilmsFinished      int
	FilmsBefore1960    int
	EpisodesTicked     int
	ShowsFinished      int
	SeasonsComplete    int
	EndedShowsComplete int
	LongShowsComplete  int
	AnimeFinished      int
	AnimeEpisodes      int
	BooksFinished      int
	PagesRead          int
	LongBooksFinished  int
	AlbumsFinished     int
	Ratings            int
	PerfectTens        int
	RatingMean         *float64
	Notes              int
	Lists              int
	Shelves            int
	Owned              int
	Genres             int
	Decades            int
	Networks           int
	// Music
	Listens int
	Artists int
	// Imports
	ImportsApplied int
	ImportSources  map[string]bool
	// Social
	Friends              int
	InvitesRedeemed      int
	RecommendationsSent  int
	RecommendationsAdded int
	Reactions            int
	// Ledger and streak days (live only)
	DoubleFeatureDays int
	MarathonDays      int
	BingedSeasons     int
	DayOneEpisodes    int
	FinaleNights      int
	NightOwlWrites    int
	LongestBookRun    int
	WatchParties      int
	LongestStreak     int
	Comeback          bool
}

// KindsFinished is the kinds with at least one finish: film, show, anime, book, album.
func (f Facts) KindsFinished() int {
	n := 0
	for _, v := range []int{f.FilmsFinished, f.ShowsFinished, f.AnimeFinished, f.BooksFinished, f.AlbumsFinished} {
		if v > 0 {
			n++
		}
	}
	return n
}

// Family groups badges for display.
type Family string

// The badge families.
const (
	FamilyFilms     Family = "films"
	FamilyShows     Family = "shows"
	FamilyAnime     Family = "anime"
	FamilyBooks     Family = "books"
	FamilyMusic     Family = "music"
	FamilyRatings   Family = "ratings"
	FamilyLists     Family = "lists"
	FamilyImports   Family = "imports"
	FamilyDiscovery Family = "discovery"
	FamilyStreaks   Family = "streaks"
	FamilySocial    Family = "social"
)

// Definition is one badge (BadgeDefinition). Tiers are 1…len(Thresholds); tier i is earned when
// Value(facts) reaches Thresholds[i-1]. Copy for hidden badges never leaves the server until earned.
type Definition struct {
	ID         string
	Family     Family
	Name       string
	Thresholds []int
	Hidden     bool
	// Private badges are never shown to friends: notes and owned items (friends never see either).
	Private  bool
	Describe func(int) string
	Value    func(Facts) int
}

// MaxTier is the number of tiers.
func (d Definition) MaxTier() int {
	return len(d.Thresholds)
}

// Tier is the highest tier the facts reach, 0 for none.
func (d Definition) Tier(facts Facts) int {
	reached := d.Value(facts)
	for i := len(d.Thresholds) - 1; i >= 0; i-- {
		if reached >= d.Thresholds[i] {
			return i + 1
		}
	}
	return 0
}

type option func(*Definition)

func tiers(t ...int) option { return func(d *Definition) { d.Thresholds = t } }
func hidden() option        { return func(d *Definition) { d.Hidden = true } }
func private() option       { return func(d *Definition) { d.Private = true } }

func badge(id string, family Family, name string, describe func(int) string, value func(Facts) int, opts ...option) Definition {
	d := Definition{ID: id, Family: family, Name: name, Thresholds: []int{1}, Describe: describe, Value: value}
	for _, o := range opts {
		o(&d)
	}
	return d
}

func fixed(text string) func(int) string { return func(int) string { return text } }

// grouped is Swift's `Int.formatted()`: thousands grouped with commas.
func grouped(n int) string {
	s := strconv.Itoa(n)
	neg := strings.HasPrefix(s, "-")
	s = strings.TrimPrefix(s, "-")
	var b strings.Builder
	for i, r := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(r)
	}
	if neg {
		return "-" + b.String()
	}
	return b.String()
}

// Plural is "1 film" / "1,000 films".
func Plural(count int, one, many string) string {
	if count == 1 {
		return grouped(count) + " " + one
	}
	return grouped(count) + " " + many
}

// Stamp is one import source's stamp badge. CAT's list and ICS share one stamp.
type Stamp struct {
	ID      string
	Label   string
	Sources []string
}

func (s Stamp) reached(sources map[string]bool) bool {
	for _, src := range s.Sources {
		if sources[src] {
			return true
		}
	}
	return false
}

// Stamps are the import sources by stamp, in CLAUDE.md's import order.
var Stamps = []Stamp{
	{ID: "trakt", Label: "Trakt", Sources: []string{"trakt"}},
	{ID: "stremio", Label: "Stremio", Sources: []string{"stremio"}},
	{ID: "imdb", Label: "IMDb", Sources: []string{"imdb_csv"}},
	{ID: "letterboxd", Label: "Letterboxd", Sources: []string{"letterboxd_csv"}},
	{ID: "goodreads", Label: "Goodreads", Sources: []string{"goodreads_csv"}},
	{ID: "cat", Label: "Pogdesign CAT", Sources: []string{"cat_list", "cat_ics"}},
	{ID: "netflix", Label: "Netflix", Sources: []string{"netflix_csv"}},
	{ID: "tvtime", Label: "TV Time", Sources: []string{"tvtime_csv"}},
	{ID: "mal", Label: "MyAnimeList", Sources: []string{"mal_xml"}},
	{ID: "anilist", Label: "AniList", Sources: []string{"anilist"}},
	{ID: "csv", Label: "Any CSV", Sources: []string{"csv"}},
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// Catalog is every badge, in display order within each family. Names are plain with a little wit
// (owner, 2026-10-22).
var Catalog = buildCatalog()

// ByID is the catalog by badge id.
var ByID = func() map[string]Definition {
	m := make(map[string]Definition, len(Catalog))
	for _, d := range Catalog {
		m[d.ID] = d
	}
	return m
}()

func buildCatalog() []Definition {
	var all []Definition
	for _, family := range [][]Definition{
		filmBadges(), showBadges(), animeBadges(), bookBadges(), musicBadges(), ratingBadges(), listBadges(),
		importBadges(), discoveryBadges(), streakBadges(), socialBadges(),
	} {
		all = append(all, family...)
	}
	return all
}

func filmBadges() []Definition {
	return []Definition{
		badge("first_film", FamilyFilms, "Opening Night", fixed("Finish a film"), func(f Facts) int { return f.FilmsFinished }),
		badge("films", FamilyFilms, "Cinephile", func(n int) string { return "Finish " + Plural(n, "film", "films") },
			func(f Facts) int { return f.FilmsFinished }, tiers(10, 100, 250, 1000)),
		badge("silver_screen", FamilyFilms, "Silver Screen", fixed("Finish a film released before 1960"),
			func(f Facts) int { return f.FilmsBefore1960 }, hidden()),
		badge("double_feature", FamilyFilms, "Double Feature", fixed("Finish two films in one day"),
			func(f Facts) int { return f.DoubleFeatureDays }),
	}
}

func showBadges() []Definition {
	return []Definition{
		badge("first_episode", FamilyShows, "Pilot", fixed("Tick an episode"), func(f Facts) int { return f.EpisodesTicked }),
		badge("episodes", FamilyShows, "Box Set", func(n int) string { return "Watch " + Plural(n, "episode", "episodes") },
			func(f Facts) int { return f.EpisodesTicked }, tiers(100, 1000, 5000, 10000)),
		badge("shows", FamilyShows, "Credits Roll", func(n int) string { return "Finish " + Plural(n, "show", "shows") },
			func(f Facts) int { return f.ShowsFinished }, tiers(5, 25, 100)),
		badge("seasons", FamilyShows, "Season Pass",
			func(n int) string { return "Watch every episode of " + Plural(n, "season", "seasons") },
			func(f Facts) int { return f.SeasonsComplete }, tiers(10, 50, 200)),
		badge("completionist", FamilyShows, "Completionist",
			func(n int) string { return "Watch every episode of " + Plural(n, "ended show", "ended shows") },
			func(f Facts) int { return f.EndedShowsComplete }, tiers(1, 10, 25)),
		badge("long_haul", FamilyShows, "Long Haul", fixed("Watch every episode of a show with 100 or more"),
			func(f Facts) int { return f.LongShowsComplete }, hidden()),
		badge("binge", FamilyShows, "One More Episode", fixed("Watch a whole season of six or more episodes in one day"),
			func(f Facts) int { return f.BingedSeasons }, hidden()),
		badge("marathon", FamilyShows, "Marathon", fixed("Watch 10 episodes in one day"),
			func(f Facts) int { return f.MarathonDays }),
		badge("day_one", FamilyShows, "Day One",
			func(n int) string { return "Watch " + Plural(n, "episode", "episodes") + " within a day of airing" },
			func(f Facts) int { return f.DayOneEpisodes }, tiers(1, 10, 50)),
		badge("finale_night", FamilyShows, "Finale Night", fixed("Watch a season finale the day it airs"),
			func(f Facts) int { return f.FinaleNights }, hidden()),
	}
}

func animeBadges() []Definition {
	return []Definition{
		badge("first_anime", FamilyAnime, "Opening Theme", fixed("Finish an anime"), func(f Facts) int { return f.AnimeFinished }),
		badge("anime", FamilyAnime, "Simulcast", func(n int) string { return "Finish " + Plural(n, "anime", "anime") },
			func(f Facts) int { return f.AnimeFinished }, tiers(5, 25, 100)),
		badge("anime_episodes", FamilyAnime, "Filler Arc",
			func(n int) string { return "Watch " + Plural(n, "anime episode", "anime episodes") },
			func(f Facts) int { return f.AnimeEpisodes }, tiers(100, 500, 2000)),
	}
}

func bookBadges() []Definition {
	return []Definition{
		badge("first_book", FamilyBooks, "Bookmark", fixed("Finish a book"), func(f Facts) int { return f.BooksFinished }),
		badge("books", FamilyBooks, "Bookworm", func(n int) string { return "Finish " + Plural(n, "book", "books") },
			func(f Facts) int { return f.BooksFinished }, tiers(10, 50, 100, 250)),
		badge("pages", FamilyBooks, "Page Turner", func(n int) string { return "Read " + Plural(n, "page", "pages") },
			func(f Facts) int { return f.PagesRead }, tiers(1000, 10000, 50000, 100_000)),
		badge("doorstopper", FamilyBooks, "Doorstopper", fixed("Finish a book of 800 pages or more"),
			func(f Facts) int { return f.LongBooksFinished }, hidden()),
		badge("chapter_a_day", FamilyBooks, "Chapter a Day", fixed("Read on seven days in a row"),
			func(f Facts) int { return f.LongestBookRun }, tiers(7)),
	}
}

func musicBadges() []Definition {
	return []Definition{
		badge("first_listen", FamilyMusic, "Needle Drop", fixed("Log a listen"), func(f Facts) int { return f.Listens }),
		badge("listens", FamilyMusic, "Heavy Rotation", func(n int) string { return "Log " + Plural(n, "listen", "listens") },
			func(f Facts) int { return f.Listens }, tiers(100, 1000, 10000, 50000)),
		badge("artists", FamilyMusic, "Crate Digger", func(n int) string { return "Listen to " + Plural(n, "artist", "artists") },
			func(f Facts) int { return f.Artists }, tiers(25, 100, 500)),
		badge("albums", FamilyMusic, "Liner Notes", func(n int) string { return "Mark " + Plural(n, "album", "albums") + " listened" },
			func(f Facts) int { return f.AlbumsFinished }, tiers(5, 25, 100)),
	}
}

func ratingBadges() []Definition {
	return []Definition{
		badge("first_rating", FamilyRatings, "First Verdict", fixed("Rate a title"), func(f Facts) int { return f.Ratings }),
		badge("ratings", FamilyRatings, "Critic", func(n int) string { return "Rate " + Plural(n, "title", "titles") },
			func(f Facts) int { return f.Ratings }, tiers(25, 100, 500, 1000)),
		badge("perfect_ten", FamilyRatings, "Ten Out of Ten", fixed("Give ten titles a 10"),
			func(f Facts) int { return f.PerfectTens }, tiers(10), hidden()),
		badge("tough_crowd", FamilyRatings, "Tough Crowd", fixed("Rate 25 titles with an average below 5"),
			func(f Facts) int {
				mean := 10.0
				if f.RatingMean != nil {
					mean = *f.RatingMean
				}
				return boolInt(f.Ratings >= 25 && mean < 5)
			}, hidden()),
		badge("notes", FamilyRatings, "Margin Notes", func(n int) string { return "Write notes on " + Plural(n, "title", "titles") },
			func(f Facts) int { return f.Notes }, tiers(10, 50, 200), private()),
	}
}

func listBadges() []Definition {
	return []Definition{
		badge("first_list", FamilyLists, "Curator", fixed("Make a list"), func(f Facts) int { return f.Lists }),
		badge("lists", FamilyLists, "Archivist", func(n int) string { return "Make " + Plural(n, "list", "lists") },
			func(f Facts) int { return f.Lists }, tiers(3, 10, 25)),
		badge("first_shelf", FamilyLists, "Shelf Life", fixed("Save a shelf"), func(f Facts) int { return f.Shelves }),
		badge("collector", FamilyLists, "Collector", func(n int) string { return "Mark " + Plural(n, "title", "titles") + " as owned" },
			func(f Facts) int { return f.Owned }, tiers(25, 100, 500), private()),
	}
}

func importBadges() []Definition {
	defs := []Definition{
		badge("first_import", FamilyImports, "Moving In", fixed("Bring your history in"),
			func(f Facts) int { return f.ImportsApplied }),
		badge("sources", FamilyImports, "Well Travelled", func(n int) string { return "Import from " + Plural(n, "source", "sources") },
			func(f Facts) int {
				n := 0
				for _, s := range Stamps {
					if s.reached(f.ImportSources) {
						n++
					}
				}
				return n
			}, tiers(2, 4, 6)),
	}
	for _, stamp := range Stamps {
		defs = append(defs, badge("stamp_"+stamp.ID, FamilyImports, stamp.Label+" stamp", fixed("Import from "+stamp.Label),
			func(f Facts) int { return boolInt(stamp.reached(f.ImportSources)) }))
	}
	return defs
}

func discoveryBadges() []Definition {
	return []Definition{
		badge("genres", FamilyDiscovery, "Genre Hopper", func(n int) string { return "Finish titles in " + Plural(n, "genre", "genres") },
			func(f Facts) int { return f.Genres }, tiers(5, 10, 15)),
		badge("decades", FamilyDiscovery, "Time Traveller",
			func(n int) string { return "Finish titles from " + Plural(n, "decade", "decades") },
			func(f Facts) int { return f.Decades }, tiers(4, 6, 8)),
		badge("networks", FamilyDiscovery, "Channel Surfer",
			func(n int) string { return "Watch shows from " + Plural(n, "network", "networks") },
			func(f Facts) int { return f.Networks }, tiers(5, 15, 30)),
		badge("all_rounder", FamilyDiscovery, "All-Rounder", fixed("Finish a film, a show, an anime, a book and an album"),
			func(f Facts) int { return boolInt(f.KindsFinished() == 5) }),
	}
}

func streakBadges() []Definition {
	return []Definition{
		badge("streak", FamilyStreaks, "Unbroken", func(n int) string { return "Keep a " + Plural(n, "day", "day") + " streak" },
			func(f Facts) int { return f.LongestStreak }, tiers(7, 30, 100, 365)),
		badge("comeback", FamilyStreaks, "Comeback", fixed("Lose a week-long streak, then build another"),
			func(f Facts) int { return boolInt(f.Comeback) }, hidden()),
		badge("night_owl", FamilyStreaks, "Night Owl",
			func(n int) string { return "Log progress after midnight " + Plural(n, "time", "times") },
			func(f Facts) int { return f.NightOwlWrites }, tiers(10, 50, 200)),
	}
}

func socialBadges() []Definition {
	return []Definition{
		badge("first_friend", FamilySocial, "Plus One", fixed("Make a friend"), func(f Facts) int { return f.Friends }),
		badge("friends", FamilySocial, "Inner Circle", func(n int) string { return "Have " + Plural(n, "friend", "friends") },
			func(f Facts) int { return f.Friends }, tiers(5, 10, 25)),
		badge("ambassador", FamilySocial, "Ambassador",
			func(n int) string { return "Bring " + Plural(n, "friend", "friends") + " in with an invite" },
			func(f Facts) int { return f.InvitesRedeemed }, tiers(1, 5, 10)),
		badge("tastemaker", FamilySocial, "Tastemaker",
			func(n int) string { return "Recommend " + Plural(n, "title", "titles") + " to friends" },
			func(f Facts) int { return f.RecommendationsSent }, tiers(1, 10, 50)),
		badge("good_call", FamilySocial, "Good Call", fixed("Have five recommendations added by friends"),
			func(f Facts) int { return f.RecommendationsAdded }, tiers(5), hidden()),
		badge("applause", FamilySocial, "Applause", func(n int) string { return "React to friends " + Plural(n, "time", "times") },
			func(f Facts) int { return f.Reactions }, tiers(10, 100)),
		badge("watch_party", FamilySocial, "Watch Party",
			func(n int) string { return "Join " + Plural(n, "watch party", "watch parties") },
			func(f Facts) int { return f.WatchParties }, tiers(1, 5, 25)),
	}
}
