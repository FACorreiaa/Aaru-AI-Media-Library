package catalog

import (
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
)

// DiscoverList is a provider-curated public list for Home (DISC-001): trending,
// airing, this season. The same for every user; nothing here reads a library or a
// per-user signal, so it is not a recommendations engine.
type DiscoverList string

// The Discover lists, in display order (DiscoverLists).
const (
	ListTVTrending       DiscoverList = "tv_trending"
	ListAnimeSeason      DiscoverList = "anime_season"
	ListMoviesTrending   DiscoverList = "movies_trending"
	ListTVOnAir          DiscoverList = "tv_on_air"
	ListAnimeTrending    DiscoverList = "anime_trending"
	ListTVNew            DiscoverList = "tv_new"
	ListMoviesInTheaters DiscoverList = "movies_in_theaters"
	ListBooksTrending    DiscoverList = "books_trending"
	ListMangaTrending    DiscoverList = "manga_trending"
	ListMangaPublishing  DiscoverList = "manga_publishing"
	ListMusicNew         DiscoverList = "music_new"
	ListMusicUpcoming    DiscoverList = "music_upcoming"
)

// AllDiscoverLists are every list, in display order.
var AllDiscoverLists = []DiscoverList{
	ListTVTrending, ListAnimeSeason, ListMoviesTrending, ListTVOnAir, ListAnimeTrending, ListTVNew,
	ListMoviesInTheaters, ListBooksTrending, ListMangaTrending, ListMangaPublishing, ListMusicNew, ListMusicUpcoming,
}

var discoverTitles = map[DiscoverList]string{
	ListTVTrending: "Trending shows", ListMoviesTrending: "Trending movies", ListTVOnAir: "On the air",
	ListAnimeTrending: "Trending anime", ListTVNew: "New shows", ListMoviesInTheaters: "In theaters",
	ListBooksTrending: "Trending books", ListMangaTrending: "Trending manga", ListMangaPublishing: "Publishing now",
	ListMusicNew: "New albums", ListMusicUpcoming: "Coming soon",
}

// Title is the row's display title; the season's anime row names the season.
func (l DiscoverList) Title(now time.Time) string {
	if l != ListAnimeSeason {
		if t, ok := discoverTitles[l]; ok {
			return t
		}
		return string(l)
	}
	return CurrentSeason(now).Title() + " anime"
}

// RowKind is what a Discover row holds (DISC-004): Library's kinds, where anime is its own.
type RowKind string

// The row kinds.
const (
	RowFilm  RowKind = "film"
	RowShow  RowKind = "show"
	RowAnime RowKind = "anime"
	RowManga RowKind = "manga"
	RowBook  RowKind = "book"
	RowAlbum RowKind = "album"
)

// Kind is the kind of title the row holds, so each client page shows only its own rows.
func (l DiscoverList) Kind() RowKind {
	switch l {
	case ListTVTrending, ListTVOnAir, ListTVNew:
		return RowShow
	case ListMoviesTrending, ListMoviesInTheaters:
		return RowFilm
	case ListAnimeSeason, ListAnimeTrending:
		return RowAnime
	case ListBooksTrending:
		return RowBook
	case ListMangaTrending, ListMangaPublishing:
		return RowManga
	}
	return RowAlbum
}

// DiscoverLister is a provider that serves some of the Discover lists.
type DiscoverLister interface {
	DiscoverLists() []DiscoverList
	List(ctx context.Context, list DiscoverList, now time.Time) ([]Hit, error)
}

// DiscoverItem is a hit with the caller's library item for it, when they have one.
type DiscoverItem struct {
	Hit           Hit
	LibraryItemID *uuid.UUID
}

// DiscoverRow is one row for one caller.
type DiscoverRow struct {
	List  DiscoverList
	Title string
	Items []DiscoverItem
	// Note says where the row came from when it is a stand-in (AniList down, TMDB filling in).
	Note *string
}

// discoverFetch is one list as fetched: its hits, how long to keep them, and a note
// for a stand-in.
type discoverFetch struct {
	hits []Hit
	ttl  time.Duration
	note *string
}

// Discover timings and limits.
const (
	// DiscoverTTL: provider lists move daily at most; six hours keeps Home fresh and providers quiet.
	DiscoverTTL = 6 * time.Hour
	// DiscoverRetryAfter: after a failed fetch, wait this long before asking that provider again.
	DiscoverRetryAfter = 5 * time.Minute
	DiscoverRowLimit   = 20
	// PastSeasonTTL is for seasons that have ended (DISC-002).
	PastSeasonTTL = 7 * 24 * time.Hour
	// FallbackTTL: a stand-in row is kept briefly, so the provider's own row returns soon after it recovers.
	FallbackTTL = 30 * time.Minute
)

// AnimeFallbackNote marks the anime rows while TMDB stands in for AniList.
const AnimeFallbackNote = "AniList is down, so these come from TMDB for now."

// DiscoverService is Discover rows (DISC-001), Seasons (DISC-002) and the on-air
// guide (DISC-003): provider lists cached for every user, then marked against the
// caller's library in one query.
type DiscoverService struct {
	store         *Store
	sources       map[DiscoverList]DiscoverLister
	seasonSources map[SeasonKind]SeasonBrowser
	// animeFallback serves the anime lists while AniList is down (CAT-021). TMDB in production.
	animeFallback DiscoverLister
	onAirSource   OnAirLister
	// nextEpisodeTiming times the guide's next episodes (TVmaze), when configured.
	nextEpisodeTiming NextEpisodeTimer
	cache             *sharedCache[DiscoverList, discoverFetch]
	seasonCache       *sharedCache[string, SeasonPage]
	onAirCache        *onAirCache
	// Now is the clock; replaceable in tests.
	Now func() time.Time
}

// NewDiscoverService builds the service. providers are the catalog adapters, in
// priority order: the first that lists a row serves it; those that list nothing are
// skipped. animeFallback and nextEpisodeTiming may be nil.
func NewDiscoverService(store *Store, providers []any, animeFallback DiscoverLister, nextEpisodeTiming NextEpisodeTimer, log *slog.Logger) *DiscoverService {
	s := &DiscoverService{
		store: store, sources: map[DiscoverList]DiscoverLister{}, seasonSources: map[SeasonKind]SeasonBrowser{},
		animeFallback: animeFallback, nextEpisodeTiming: nextEpisodeTiming,
		cache:       newSharedCache[DiscoverList, discoverFetch](0, "Discover list failed"),
		seasonCache: newSharedCache[string, SeasonPage](SeasonCacheCapacity, "Season page failed"),
		onAirCache:  &onAirCache{log: log},
		Now:         time.Now,
	}
	s.cache.log, s.seasonCache.log = log, log
	for _, p := range providers {
		if p == nil {
			continue
		}
		if l, ok := p.(DiscoverLister); ok {
			for _, list := range l.DiscoverLists() {
				if _, taken := s.sources[list]; !taken {
					s.sources[list] = l
				}
			}
		}
		if b, ok := p.(SeasonBrowser); ok {
			for _, kind := range b.SeasonKinds() {
				if _, taken := s.seasonSources[kind]; !taken {
					s.seasonSources[kind] = b
				}
			}
		}
		if o, ok := p.(OnAirLister); ok && s.onAirSource == nil {
			s.onAirSource = o
		}
	}
	return s
}

// Rows are every Discover row with hits, in display order, marked for userID.
func (s *DiscoverService) Rows(ctx context.Context, userID uuid.UUID) ([]DiscoverRow, error) {
	now := s.Now()
	var mu sync.Mutex
	var wg sync.WaitGroup
	lists := map[DiscoverList]discoverFetch{}
	for list, source := range s.sources {
		wg.Go(func() {
			fetched, ok := s.cache.get(ctx, list, now, func(f discoverFetch) time.Duration { return f.ttl },
				func(ctx context.Context) (discoverFetch, error) { return s.fetch(ctx, list, source, now) })
			if ok {
				mu.Lock()
				lists[list] = fetched
				mu.Unlock()
			}
		})
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	// A poster-less card reads as broken on a poster row.
	type ordered struct {
		list DiscoverList
		f    discoverFetch
	}
	var rows []ordered
	var all []Hit
	for _, list := range AllDiscoverLists {
		fetched, ok := lists[list]
		if !ok {
			continue
		}
		var hits []Hit
		for _, h := range fetched.hits {
			if h.PosterURL != nil && len(hits) < DiscoverRowLimit {
				hits = append(hits, h)
			}
		}
		if len(hits) == 0 {
			continue
		}
		fetched.hits = hits
		rows = append(rows, ordered{list, fetched})
		all = append(all, hits...)
	}
	marked, err := s.Mark(ctx, all, userID)
	if err != nil {
		return nil, err
	}
	out := make([]DiscoverRow, 0, len(rows))
	offset := 0
	for _, r := range rows {
		out = append(out, DiscoverRow{
			List: r.list, Title: r.list.Title(now), Items: marked[offset : offset+len(r.f.hits)], Note: r.f.note,
		})
		offset += len(r.f.hits)
	}
	return out, nil
}

// fetch is the list from its provider, or, while AniList is down, its anime lists
// from the stand-in.
func (s *DiscoverService) fetch(ctx context.Context, list DiscoverList, source DiscoverLister, now time.Time) (discoverFetch, error) {
	hits, err := source.List(ctx, list, now)
	if err == nil {
		return discoverFetch{hits: hits, ttl: DiscoverTTL}, nil
	}
	// Only anime has a stand-in: manga rows are simply absent while AniList is down.
	if !provider.IsAniListOutage(err) || s.animeFallback == nil || list.Kind() != RowAnime {
		return discoverFetch{}, err
	}
	hits, err = s.animeFallback.List(ctx, list, now)
	if err != nil {
		return discoverFetch{}, fmt.Errorf("anime fallback: %w", err)
	}
	note := AnimeFallbackNote
	return discoverFetch{hits: hits, ttl: FallbackTTL, note: &note}, nil
}

// Mark is each hit with the caller's item for it, from one library query.
func (s *DiscoverService) Mark(ctx context.Context, hits []Hit, userID uuid.UUID) ([]DiscoverItem, error) {
	var keys []Key
	for _, h := range hits {
		keys = append(keys, h.Keys()...)
	}
	owned, err := s.store.LibraryItemIDs(ctx, userID, keys)
	if err != nil {
		return nil, err
	}
	items := make([]DiscoverItem, 0, len(hits))
	for _, h := range hits {
		item := DiscoverItem{Hit: h}
		for _, k := range h.Keys() {
			if id, ok := owned[k]; ok {
				item.LibraryItemID = &id
				break
			}
		}
		items = append(items, item)
	}
	return items, nil
}
