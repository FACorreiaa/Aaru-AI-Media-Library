package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/safe"
	"cmp"
	"context"
	"fmt"
	"log/slog"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Onboarding rows (ONB-001): titles most people have heard of, by kind, for the first-run flow to
// pick from. Popular first, then a row per genre (per subject for books). Catalog data cached for
// every user and marked against the caller's library, like Discover, but kept out of
// `/v1/discover` so Discover's fan-out does not grow. Nothing here reads a per-user signal.

// OnboardingGenre is one onboarding row of a kind: the provider's genre, subject or none.
type OnboardingGenre struct {
	// Key ends the row id: `onb_<kind>_<key>`.
	Key   string
	Title string
	// TMDBGenre is TMDB's genre id for film and show rows; 0 is every genre.
	TMDBGenre int
	// AniListGenre is AniList's genre for anime and manga rows; empty is every genre.
	AniListGenre string
	// Subject is Open Library's subject for book rows.
	Subject string
}

// ID is the row's stable id, e.g. `onb_show_drama`.
func (g OnboardingGenre) ID(kind RowKind) string { return "onb_" + string(kind) + "_" + g.Key }

var onboardingPopular = OnboardingGenre{Key: "popular", Title: "Popular"}

// aniListOnboardingGenres are the anime and manga rows after Popular.
var aniListOnboardingGenres = []OnboardingGenre{
	onboardingPopular,
	{Key: "action", Title: "Action", AniListGenre: "Action"},
	{Key: "romance", Title: "Romance", AniListGenre: "Romance"},
	{Key: "comedy", Title: "Comedy", AniListGenre: "Comedy"},
	{Key: "fantasy", Title: "Fantasy", AniListGenre: "Fantasy"},
	{Key: "slice_of_life", Title: "Slice of Life", AniListGenre: "Slice of Life"},
	{Key: "sports", Title: "Sports", AniListGenre: "Sports"},
}

// OnboardingGenres are each kind's rows, in display order. Albums have Popular only: MusicBrainz
// tags are too thin for genre rows.
var OnboardingGenres = map[RowKind][]OnboardingGenre{
	RowShow: {
		onboardingPopular,
		{Key: "drama", Title: "Drama", TMDBGenre: 18},
		{Key: "comedy", Title: "Comedy", TMDBGenre: 35},
		{Key: "crime", Title: "Crime", TMDBGenre: 80},
		{Key: "scifi_fantasy", Title: "Sci-Fi & Fantasy", TMDBGenre: 10765},
		{Key: "mystery", Title: "Mystery", TMDBGenre: 9648},
	},
	RowFilm: {
		onboardingPopular,
		{Key: "action", Title: "Action", TMDBGenre: 28},
		{Key: "comedy", Title: "Comedy", TMDBGenre: 35},
		{Key: "drama", Title: "Drama", TMDBGenre: 18},
		{Key: "horror", Title: "Horror", TMDBGenre: 27},
		{Key: "science_fiction", Title: "Science fiction", TMDBGenre: 878},
		{Key: "thriller", Title: "Thriller", TMDBGenre: 53},
		{Key: "romance", Title: "Romance", TMDBGenre: 10749},
	},
	RowAnime: aniListOnboardingGenres,
	RowManga: aniListOnboardingGenres,
	RowBook: {
		{Key: "fantasy", Title: "Fantasy", Subject: "fantasy"},
		{Key: "romance", Title: "Romance", Subject: "romance"},
		{Key: "mystery", Title: "Mystery", Subject: "mystery_and_detective_stories"},
		{Key: "thriller", Title: "Thriller", Subject: "thriller"},
		{Key: "science_fiction", Title: "Science fiction", Subject: "science_fiction"},
		{Key: "classics", Title: "Classics", Subject: "classics"},
		{Key: "biography", Title: "Biography", Subject: "biography"},
	},
	RowAlbum: {onboardingPopular},
}

// PopularLister is a provider of well-known titles of some kinds, one genre row at a time.
type PopularLister interface {
	OnboardingKinds() []RowKind
	Popular(ctx context.Context, kind RowKind, genre OnboardingGenre) ([]Hit, error)
}

// OnboardingTTL is a day: what is well known changes slowly, and providers stay quiet.
const OnboardingTTL = 24 * time.Hour

// OnboardingRow is one row for one caller.
type OnboardingRow struct {
	ID    string
	Kind  RowKind
	Title string
	Items []DiscoverItem
	// Note says where a stand-in row came from (AniList down, TMDB filling in).
	Note *string
}

// OnboardingService is the first-run flow's rows (ONB-001), cached for every user.
type OnboardingService struct {
	discover *DiscoverService
	sources  map[RowKind]PopularLister
	// animeFallback serves anime's Popular row while AniList is down (CAT-021). TMDB in production.
	animeFallback PopularLister
	cache         *sharedCache[string, discoverFetch]
	// Now is the clock; replaceable in tests.
	Now func() time.Time
	// Wait bounds the wait for rows not cached yet (OnboardingRowsWait); replaceable in tests.
	Wait time.Duration
}

// NewOnboardingService builds the service over Discover's library mark. providers are the
// catalog adapters in priority order: the first that serves a kind serves it. animeFallback may
// be nil.
func NewOnboardingService(discover *DiscoverService, providers []any, animeFallback PopularLister, log *slog.Logger) *OnboardingService {
	s := &OnboardingService{
		discover: discover, sources: map[RowKind]PopularLister{}, animeFallback: animeFallback,
		cache: newSharedCache[string, discoverFetch](0, "Onboarding row failed"), Now: time.Now,
		Wait: OnboardingRowsWait,
	}
	s.cache.log = log
	for _, p := range providers {
		if p == nil {
			continue
		}
		if l, ok := p.(PopularLister); ok {
			for _, kind := range l.OnboardingKinds() {
				if _, taken := s.sources[kind]; !taken {
					s.sources[kind] = l
				}
			}
		}
	}
	return s
}

// OnboardingRowsWait is how long Rows waits for rows not cached yet, under the request deadline.
// A slow provider (Open Library's sorted search takes up to 11 s) keeps fetching into the cache
// past it, and its rows come on the next call.
const OnboardingRowsWait = 12 * time.Second

// Rows are kind's rows with hits, in display order, marked for userID. A row whose provider
// failed, or is still loading after OnboardingRowsWait, is left out; the rest still come.
func (s *OnboardingService) Rows(ctx context.Context, kind RowKind, userID uuid.UUID) ([]OnboardingRow, error) {
	genres := OnboardingGenres[kind]
	source := s.sources[kind]
	if source == nil || len(genres) == 0 {
		return []OnboardingRow{}, nil
	}
	now := s.Now()
	fetched := make([]*discoverFetch, len(genres))
	waitCtx, cancel := context.WithTimeout(ctx, s.Wait)
	defer cancel()
	var wg sync.WaitGroup
	for i, genre := range genres {
		wg.Go(func() {
			defer func() { _ = recovered(s.cache.log, "Onboarding row", recover()) }()
			f, ok := s.cache.get(waitCtx, genre.ID(kind), now, func(f discoverFetch) time.Duration { return f.ttl },
				func(ctx context.Context) (discoverFetch, error) { return s.fetch(ctx, kind, genre, source) })
			if ok {
				fetched[i] = &f
			}
		})
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	type ordered struct {
		genre OnboardingGenre
		hits  []Hit
		note  *string
	}
	var rows []ordered
	var all []Hit
	for i, genre := range genres {
		if fetched[i] == nil {
			continue
		}
		// A poster-less card reads as broken on a poster row.
		var hits []Hit
		for _, h := range fetched[i].hits {
			if h.PosterURL != nil && len(hits) < DiscoverRowLimit {
				hits = append(hits, h)
			}
		}
		if len(hits) == 0 {
			continue
		}
		rows = append(rows, ordered{genre, hits, fetched[i].note})
		all = append(all, hits...)
	}
	marked, err := s.discover.Mark(ctx, all, userID)
	if err != nil {
		return nil, err
	}
	out := make([]OnboardingRow, 0, len(rows))
	offset := 0
	for _, r := range rows {
		out = append(out, OnboardingRow{
			ID: r.genre.ID(kind), Kind: kind, Title: r.genre.Title, Items: marked[offset : offset+len(r.hits)], Note: r.note,
		})
		offset += len(r.hits)
	}
	return out, nil
}

// fetch is one row from its provider, or, while AniList is down, anime's Popular row from the
// stand-in. Anime's genre rows and every manga row are simply absent until AniList is back.
func (s *OnboardingService) fetch(ctx context.Context, kind RowKind, genre OnboardingGenre, source PopularLister) (discoverFetch, error) {
	hits, err := source.Popular(ctx, kind, genre)
	if err == nil {
		return discoverFetch{hits: hits, ttl: OnboardingTTL}, nil
	}
	if !provider.IsAniListOutage(err) || s.animeFallback == nil || kind != RowAnime || genre.Key != onboardingPopular.Key {
		return discoverFetch{}, err
	}
	hits, err = s.animeFallback.Popular(ctx, kind, genre)
	if err != nil {
		return discoverFetch{}, fmt.Errorf("anime fallback: %w", err)
	}
	note := AnimeFallbackNote
	return discoverFetch{hits: hits, ttl: FallbackTTL, note: &note}, nil
}

// MARK: - TMDB

// Vote floors for TMDB's onboarding rows: popularity alone surfaces this week's unknowns, and a
// floor keeps the rows to titles people have seen. Shows gather fewer votes than films.
const (
	tmdbOnboardingFilmVotes = 1000
	tmdbOnboardingShowVotes = 300
)

// OnboardingKinds are the onboarding kinds TMDB serves.
func (t *TMDB) OnboardingKinds() []RowKind { return []RowKind{RowShow, RowFilm} }

// Popular is the best-known films or shows in a genre, most popular first. Show rows leave out
// animation (anime has its own kind) and news, soap and talk. Anime is the stand-in while AniList
// is down: Japanese animation, every genre.
func (t *TMDB) Popular(ctx context.Context, kind RowKind, genre OnboardingGenre) ([]Hit, error) {
	query := map[string]string{"include_adult": "false", "sort_by": "popularity.desc"}
	var mediaType core.MediaType
	var path string
	switch kind {
	case RowFilm:
		mediaType, path = core.MediaMovie, "discover/movie"
		query["vote_count.gte"] = strconv.Itoa(tmdbOnboardingFilmVotes)
	case RowShow:
		mediaType, path = core.MediaShow, "discover/tv"
		query["vote_count.gte"] = strconv.Itoa(tmdbOnboardingShowVotes)
		query["without_genres"] = "16,10763,10766,10767"
	case RowAnime:
		mediaType, path = core.MediaShow, "discover/tv"
		for k, v := range tmdbJapaneseAnimation() {
			query[k] = v
		}
		query["vote_count.gte"] = strconv.Itoa(tmdbOnboardingShowVotes)
	default:
		return nil, provider.NewError("tmdb", provider.KindNotFound)
	}
	if genre.TMDBGenre != 0 {
		query["with_genres"] = strconv.Itoa(genre.TMDBGenre)
	}
	var page tmdbSearchPage
	if err := t.get(ctx, path, query, &page); err != nil {
		return nil, err
	}
	return tmdbRowHits(page, mediaType, kind == RowAnime), nil
}

// MARK: - AniList

// OnboardingKinds are the onboarding kinds AniList serves.
func (a *AniList) OnboardingKinds() []RowKind { return []RowKind{RowAnime, RowManga} }

// Popular is the most popular anime or manga of all time, in one genre or any. No adult works.
func (a *AniList) Popular(ctx context.Context, kind RowKind, genre OnboardingGenre) ([]Hit, error) {
	var filter, fields string
	switch kind {
	case RowAnime:
		filter, fields = "type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, ONA, MOVIE]", aniListMediaFields
	case RowManga:
		filter, fields = "type: MANGA, isAdult: false", aniListFields(core.MediaManga)
	default:
		return nil, provider.NewError("anilist", provider.KindNotFound)
	}
	params, variables := "", map[string]any{}
	if genre.AniListGenre != "" {
		params, filter = "($genres: [String])", filter+", genre_in: $genres"
		variables["genres"] = []string{genre.AniListGenre}
	}
	var body aniListSearchData
	err := a.post(ctx, fmt.Sprintf(`query %s {
  Page(perPage: %d) {
    media(%s, sort: POPULARITY_DESC) {
      %s
    }
  }
}`, params, DiscoverRowLimit, filter, fields), variables, &body)
	if err != nil {
		return nil, err
	}
	return body.hits(), nil
}

// MARK: - Open Library

// OnboardingKinds are the onboarding kinds Open Library serves.
func (o *OpenLibrary) OnboardingKinds() []RowKind { return []RowKind{RowBook} }

// Popular is a subject's books Open Library readers have logged most (search sorted by
// `readinglog`), so the row holds books a new account has likely read.
func (o *OpenLibrary) Popular(ctx context.Context, kind RowKind, genre OnboardingGenre) ([]Hit, error) {
	if kind != RowBook || genre.Subject == "" {
		return nil, provider.NewError("openlibrary", provider.KindNotFound)
	}
	// Not `subjects/<s>.json`: it ranks by edition count, which brings up public-domain classics.
	// English works only: the most-logged list otherwise leads with a translation's title.
	query := map[string]string{
		"q":    "subject_key:" + genre.Subject + " language:eng",
		"sort": "readinglog", "fields": openLibraryFields, "limit": "30",
	}
	headers := [][2]string{{"User-Agent", cmp.Or(o.UserAgent, config.DefaultProviderUserAgent)}, {"Accept", "application/json"}}
	req := provider.Request{
		URL: buildURL(cmp.Or(o.BaseURL, OpenLibraryBaseURL), "search.json", query), Headers: headers,
		Timeout: openLibrarySortedSearchTimeout,
	}
	var page openLibraryPage
	if err := o.Client.DecodeJSON(ctx, req, &page); err != nil {
		return nil, err
	}
	return page.hits(page.Docs), nil
}

// openLibrarySortedSearchTimeout is one sorted subject search: Open Library takes 2 to 11 s for
// one, past provider.DefaultTimeout. The rows are cached a day for everyone, so one slow fetch
// a day is the cost.
const openLibrarySortedSearchTimeout = 30 * time.Second

// MARK: - ListenBrainz

// listenBrainzPopularCount is how many of the most-played release groups are read: compilations
// and coverless ones drop out, and a row needs 20.
const listenBrainzPopularCount = "100"

// OnboardingKinds are the onboarding kinds ListenBrainz serves.
func (l *ListenBrainz) OnboardingKinds() []RowKind { return []RowKind{RowAlbum} }

// Popular is the release groups ListenBrainz users have played most, all time, with a cover.
// Compilations credited to Various Artists are left out.
func (l *ListenBrainz) Popular(ctx context.Context, kind RowKind, _ OnboardingGenre) ([]Hit, error) {
	if kind != RowAlbum {
		return nil, provider.NewError("listenbrainz", provider.KindNotFound)
	}
	var played struct {
		Payload struct {
			ReleaseGroups []struct {
				ArtistMBIDs      []string `json:"artist_mbids"`
				ArtistName       string   `json:"artist_name"`
				CAAID            *int64   `json:"caa_id"`
				CAAReleaseMBID   *string  `json:"caa_release_mbid"`
				ReleaseGroupMBID *string  `json:"release_group_mbid"`
				ReleaseGroupName string   `json:"release_group_name"`
			} `json:"release_groups"`
		} `json:"payload"`
	}
	err := l.get(ctx, "stats/sitewide/release-groups", map[string]string{"range": "all_time", "count": listenBrainzPopularCount}, &played)
	if err != nil {
		return nil, err
	}
	hits := []Hit{}
	seen := map[string]bool{}
	for _, g := range played.Payload.ReleaseGroups {
		if g.ReleaseGroupMBID == nil || seen[*g.ReleaseGroupMBID] || g.CAAID == nil || g.CAAReleaseMBID == nil ||
			g.ReleaseGroupName == "" {
			continue
		}
		various := false
		for _, id := range g.ArtistMBIDs {
			various = various || id == ListenBrainzVariousArtists
		}
		if various {
			continue
		}
		seen[*g.ReleaseGroupMBID] = true
		poster := "https://coverartarchive.org/release/" + *g.CAAReleaseMBID + "/" + strconv.FormatInt(*g.CAAID, 10) + "-250.jpg"
		hits = append(hits, Hit{
			Type: core.MediaAlbum, Title: g.ReleaseGroupName, PosterURL: &poster, Byline: blankToNil(g.ArtistName),
			IDs: core.ExternalIDs{MusicBrainz: *g.ReleaseGroupMBID},
		})
	}
	return hits, nil
}

// Warm loads every kind's rows into the cache, nobody waiting: Open Library's sorted search takes
// up to half a minute, and a new account should not be the one to wait for it.
func (s *OnboardingService) Warm(ctx context.Context) {
	now := s.Now()
	var wg sync.WaitGroup
	for kind, genres := range OnboardingGenres {
		source := s.sources[kind]
		if source == nil {
			continue
		}
		for _, genre := range genres {
			wg.Go(func() {
				defer func() { _ = recovered(s.cache.log, "Onboarding warm", recover()) }()
				s.cache.get(ctx, genre.ID(kind), now, func(f discoverFetch) time.Duration { return f.ttl },
					func(ctx context.Context) (discoverFetch, error) { return s.fetch(ctx, kind, genre, source) })
			})
		}
	}
	wg.Wait()
}

// OnboardingWarmer keeps the first-run rows loaded: once at start, then each time they expire, so
// a row past its day is refetched while the stale copy still serves.
type OnboardingWarmer struct {
	Service *OnboardingService
	Log     *slog.Logger
	// Interval is the pause between passes (OnboardingTTL and a minute when zero).
	Interval time.Duration
}

// Name is the worker's name in logs and metrics.
func (w *OnboardingWarmer) Name() string { return "onboarding_warmer" }

// Run warms the rows until ctx is cancelled.
func (w *OnboardingWarmer) Run(ctx context.Context) error {
	interval := cmp.Or(w.Interval, OnboardingTTL+time.Minute)
	for ctx.Err() == nil {
		err := safe.Step(func() error { w.Service.Warm(ctx); return nil })
		if ctx.Err() == nil {
			metrics.WorkerPass(w.Name(), err)
		}
		if err != nil && ctx.Err() == nil {
			cmp.Or(w.Log, slog.Default()).Error("Onboarding warm pass failed", "error", err.Error())
		}
		timer := time.NewTimer(interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-timer.C:
		}
	}
	return nil
}
