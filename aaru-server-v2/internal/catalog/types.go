// Package catalog is Aaru's catalog layer (Sources/App/Catalog): the provider
// adapters (TMDB, AniList, Open Library, TVmaze, MusicBrainz, ListenBrainz), the
// titles store, search and title detail with lazy hydration (Service), MediaRef →
// Title resolution (Resolver), Discover rows, seasons and the on-air guide
// (DiscoverService), and the episode/genre/page-count refresher.
//
// Catalog metadata is never a user's library row: nothing here reads or writes a
// library item except the Discover "in library" mark.
package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Hit is one search result: a catalog projection, never a library row.
type Hit struct {
	Type          core.MediaType
	Title         string
	OriginalTitle *string
	Year          *int
	PosterURL     *string
	Overview      *string
	// Byline is authors for books and manga, the artist credit for albums; nil otherwise.
	Byline      *string
	IDs         core.ExternalIDs
	IsAnime     bool
	BackdropURL *string
	Network     *string
	// ReleaseDate is the first release (films) or first air date (shows), `YYYY-MM-DD`;
	// nil when the provider gives no full date.
	ReleaseDate *string
	// PageCount is a book's pages, the median across editions (Open Library).
	PageCount *int
	// ChapterCount and VolumeCount are a manga's, once AniList knows them (MNG-001).
	ChapterCount *int
	VolumeCount  *int
}

// MediaRef is the hit as a ref to resolve.
func (h Hit) MediaRef() core.MediaRef {
	title := h.Title
	return core.MediaRef{Type: h.Type, IDs: h.IDs, Title: &title, Year: h.Year}
}

// TitleStatus is the lifecycle of a show as its catalog reports it. Drives PROG-003's
// auto-finish and the hydration staleness window.
type TitleStatus string

// The show lifecycles.
const (
	StatusUpcoming  TitleStatus = "upcoming"
	StatusReturning TitleStatus = "returning"
	StatusEnded     TitleStatus = "ended"
	StatusCanceled  TitleStatus = "canceled"
)

// Record is a full catalog record, ready to become a `titles` row.
type Record struct {
	Hit            Hit
	Status         *TitleStatus
	RuntimeMinutes *int
	// Genres are the provider's genre names, in its order (CAT-018). Empty for books.
	Genres []string
}

// Episode is one episode as a catalog lists it.
type Episode struct {
	Season         int
	Episode        int
	Name           *string
	AirsAt         *time.Time
	RuntimeMinutes *int
	TMDBEpisodeID  *string
	// AirTimeKnown is true when AirsAt is the exact broadcast time (AniList, TVmaze);
	// false when the provider gives only a date (TMDB), stored as midnight UTC.
	AirTimeKnown bool
	Overview     *string
	StillURL     *string
}

// Episodes is what a show's episode source returns: the show's status plus every
// known episode.
type Episodes struct {
	Status   *TitleStatus
	Episodes []Episode
	// BackdropURL and Network are the show's wide art and network as the episode source
	// reports them now, saved with the episodes so older titles fill in on refresh.
	BackdropURL *string
	Network     *string
}

// Searcher is a provider's search and hydration.
type Searcher interface {
	Search(ctx context.Context, query string, mediaType core.MediaType) ([]Hit, error)
	// Hydrate is the provider's record for these ids, or nil when it has none.
	Hydrate(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error)
}

// MALBatchHydrator hydrates many anime or manga by MyAnimeList id in few requests
// (IMP-017, AniList's `idMal_in`).
type MALBatchHydrator interface {
	// HydrateMAL is keyed by MAL id; an id the provider does not know is missing.
	// mediaType is manga for MAL's manga list and anything else for its anime list.
	HydrateMAL(ctx context.Context, malIDs []string, mediaType core.MediaType) (map[string]Record, error)
}

// MultiSearcher is one query across films and shows at once (CAT-019's All scope).
type MultiSearcher interface {
	// SearchMulti is films and shows, best first; people and adult titles are never returned.
	SearchMulti(ctx context.Context, query string) ([]Hit, error)
}

// EpisodeLister lists a show's episodes.
type EpisodeLister interface {
	// Episodes is every episode the provider knows for a show it can identify from ids;
	// nil when it cannot.
	Episodes(ctx context.Context, ids core.ExternalIDs) (*Episodes, error)
}

// VideoCatalog is TMDB's role: films and shows.
type VideoCatalog interface {
	Searcher
	EpisodeLister
	MultiSearcher
}

// AnimeCatalog is AniList's role: anime and manga.
type AnimeCatalog interface {
	Searcher
	EpisodeLister
}

// MusicCatalog is MusicBrainz's role for albums.
type MusicCatalog interface {
	Searcher
	TrackLister
}

// Providers are the adapters, by role. Search scopes anime and manga go to AniList;
// movie/show to TMDB; book to Open Library; album to MusicBrainz; all to TMDB's
// multi search and AniList together.
type Providers struct {
	TMDB        VideoCatalog
	AniList     AnimeCatalog
	OpenLibrary Searcher
	// AirTimes refines TMDB's date-only episodes with exact times (TVmaze, CAT-011).
	// Optional: without it the calendar shows dates.
	AirTimes AirTimeRefiner
	// Music is albums (MUS-001, MusicBrainz). Optional: without it music finds nothing.
	Music MusicCatalog
	// Releases are Discover's album rows (MUS-002, ListenBrainz). Optional.
	Releases DiscoverLister
	// Recordings identifies scrobbled tracks (MUS-006): the same MusicBrainz client as
	// Music, so both share one pacer. Optional.
	Recordings RecordingMatcher
}

// nilIfBlank is the trimmed string, or nil when it is blank.
func nilIfBlank(s *string) *string {
	if s == nil {
		return nil
	}
	return blankToNil(*s)
}

func strPtr(s string) *string { return &s }

func blankToNil(s string) *string {
	trimmed := strings.TrimSpace(s)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func intPtr(n int) *int { return &n }

// ParseDay is "2025-03-14" → that day at 00:00 UTC. Providers give dates, not
// instants. A day that does not exist (2025-02-30) is no date.
func ParseDay(s *string) *time.Time {
	if s == nil || len(*s) < 10 {
		return nil
	}
	head := []rune(*s)
	if len(head) < 10 {
		return nil
	}
	var parts []int
	for p := range strings.SplitSeq(string(head[:10]), "-") {
		if p == "" {
			continue
		}
		if n, err := strconv.Atoi(p); err == nil {
			parts = append(parts, n)
		}
	}
	if len(parts) != 3 {
		return nil
	}
	t := time.Date(parts[0], time.Month(parts[1]), parts[2], 0, 0, 0, 0, time.UTC)
	if t.Year() != parts[0] || int(t.Month()) != parts[1] || t.Day() != parts[2] {
		return nil
	}
	return &t
}

var (
	datePrefix = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}`)
	fourDigits = regexp.MustCompile(`\d{4}`)
)

// ParseDate is a provider date string as `YYYY-MM-DD`, or nil when it is not a full date.
func ParseDate(s *string) *string {
	if s == nil {
		return nil
	}
	if m := datePrefix.FindString(*s); m != "" {
		return &m
	}
	return nil
}

// ParseYear is the leading four-digit year of a provider date string, if any.
func ParseYear(s *string) *int {
	if s == nil {
		return nil
	}
	m := fourDigits.FindString(*s)
	if m == "" {
		return nil
	}
	n, _ := strconv.Atoi(m)
	return &n
}

// dayString is `YYYY-MM-DD` in UTC.
func dayString(t time.Time) string {
	return t.UTC().Format("2006-01-02")
}
