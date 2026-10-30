package catalog

import (
	"aaru-go-api/internal/apperr"
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// SeasonOfYear is a season by calendar quarter in UTC (DISC-002). It is AniList's
// `MediaSeason` for anime, and the same quarter for films (by release) and shows (by
// premiere or airing).
type SeasonOfYear string

// The seasons, in calendar order.
const (
	Winter SeasonOfYear = "winter"
	Spring SeasonOfYear = "spring"
	Summer SeasonOfYear = "summer"
	Fall   SeasonOfYear = "fall"
)

// SeasonsOfYear are the seasons in calendar order.
var SeasonsOfYear = []SeasonOfYear{Winter, Spring, Summer, Fall}

func (s SeasonOfYear) index() int {
	for i, v := range SeasonsOfYear {
		if v == s {
			return i
		}
	}
	return 0
}

// AniList is AniList's name for the season ("FALL").
func (s SeasonOfYear) AniList() string { return strings.ToUpper(string(s)) }

// DisplayName is "Fall".
func (s SeasonOfYear) DisplayName() string {
	return strings.ToUpper(string(s[:1])) + string(s[1:])
}

// firstMonth is the first month of the quarter.
func (s SeasonOfYear) firstMonth() time.Month { return time.Month(s.index()*3 + 1) }

// SeasonKey is one season of one year, e.g. Fall 2026.
type SeasonKey struct {
	Season SeasonOfYear
	Year   int
}

// CurrentSeason is the season now falls in, in UTC.
func CurrentSeason(now time.Time) SeasonKey {
	now = now.UTC()
	return SeasonKey{Season: SeasonsOfYear[(int(now.Month())-1)/3], Year: now.Year()}
}

// Title is "Fall 2026".
func (k SeasonKey) Title() string { return k.Season.DisplayName() + " " + strconv.Itoa(k.Year) }

// Next is the following season.
func (k SeasonKey) Next() SeasonKey {
	if k.Season == Fall {
		return SeasonKey{Season: Winter, Year: k.Year + 1}
	}
	return SeasonKey{Season: SeasonsOfYear[k.Season.index()+1], Year: k.Year}
}

// Previous is the season before.
func (k SeasonKey) Previous() SeasonKey {
	if k.Season == Winter {
		return SeasonKey{Season: Fall, Year: k.Year - 1}
	}
	return SeasonKey{Season: SeasonsOfYear[k.Season.index()-1], Year: k.Year}
}

// Range is `[start, end)`: the first day of the quarter and the first day of the next one.
func (k SeasonKey) Range() (start, end time.Time) {
	start = time.Date(k.Year, k.Season.firstMonth(), 1, 0, 0, 0, 0, time.UTC)
	return start, start.AddDate(0, 3, 0)
}

// Days are the first and last day of the season, `YYYY-MM-DD`, as providers' date
// filters take them.
func (k SeasonKey) Days() (first, last string) {
	start, end := k.Range()
	return dayString(start), dayString(end.Add(-24 * time.Hour))
}

// SeasonKind is what the Seasons view lists for a season.
type SeasonKind string

// The season lists.
const (
	// SeasonAnime is anime airing that season (AniList).
	SeasonAnime SeasonKind = "anime"
	// SeasonShowsNew is shows whose first episode aired that season.
	SeasonShowsNew SeasonKind = "shows_new"
	// SeasonShowsReturning is shows that premiered earlier and air episodes that season.
	SeasonShowsReturning SeasonKind = "shows_returning"
	// SeasonMovies is films first released that season.
	SeasonMovies SeasonKind = "movies"
)

// SeasonPage is one page of a season as a provider lists it.
type SeasonPage struct {
	Hits    []Hit
	HasMore bool
	// Total is the provider's count for the whole season, when it gives one.
	Total *int
}

// SeasonBrowser is a provider that lists a season's titles, one page at a time.
type SeasonBrowser interface {
	SeasonKinds() []SeasonKind
	Season(ctx context.Context, key SeasonKey, kind SeasonKind, page int, now time.Time) (SeasonPage, error)
}

// SeasonResult is one season page, marked against the caller's library.
// Unavailable when the provider is down and nothing is cached: clients say so
// instead of showing an empty season.
type SeasonResult struct {
	Key         SeasonKey
	Kind        SeasonKind
	Page        int
	Items       []DiscoverItem
	HasMore     bool
	Total       *int
	Unavailable bool
}

// Season browsing limits.
const (
	// FirstSeasonYear is the oldest year the Seasons view goes back to.
	FirstSeasonYear = 1970
	MaxSeasonPage   = 20
	// SeasonCacheCapacity bounds the season pages kept, so browsing old seasons cannot
	// grow memory without end.
	SeasonCacheCapacity = 200
)

// Season is one page of a season for userID.
func (s *DiscoverService) Season(ctx context.Context, key SeasonKey, kind SeasonKind, page int, userID uuid.UUID) (SeasonResult, error) {
	now := s.Now()
	latest := CurrentSeason(now).Year + 1
	if key.Year < FirstSeasonYear || key.Year > latest {
		return SeasonResult{}, apperr.Validation("year", fmt.Sprintf("The year must be between %d and %d.", FirstSeasonYear, latest))
	}
	if page < 1 || page > MaxSeasonPage {
		return SeasonResult{}, apperr.Validation("page", fmt.Sprintf("The page must be between 1 and %d.", MaxSeasonPage))
	}
	unavailable := SeasonResult{Key: key, Kind: kind, Page: page, Items: []DiscoverItem{}, Unavailable: true}
	source, ok := s.seasonSources[kind]
	if !ok {
		return unavailable, nil
	}
	// A season that has ended changes little; the current and coming ones move daily.
	ttl := DiscoverTTL
	if _, end := key.Range(); !end.After(now) {
		ttl = PastSeasonTTL
	}
	cacheKey := fmt.Sprintf("%s:%d-%s:%d", kind, key.Year, key.Season, page)
	fetched, ok := s.seasonCache.get(ctx, cacheKey, now, func(SeasonPage) time.Duration { return ttl },
		func(ctx context.Context) (SeasonPage, error) { return source.Season(ctx, key, kind, page, now) })
	if !ok {
		return unavailable, nil
	}
	var hits []Hit
	for _, h := range fetched.Hits {
		if h.PosterURL != nil {
			hits = append(hits, h)
		}
	}
	items, err := s.Mark(ctx, hits, userID)
	if err != nil {
		return SeasonResult{}, err
	}
	return SeasonResult{Key: key, Kind: kind, Page: page, Items: items, HasMore: fetched.HasMore, Total: fetched.Total}, nil
}
