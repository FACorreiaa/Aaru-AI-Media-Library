package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sync/errgroup"
)

// TMDB image bases. Poster URLs are referenced, never downloaded.
const (
	TMDBBaseURL   = "https://api.themoviedb.org/3"
	tmdbImageBase = "https://image.tmdb.org/t/p/w500"
	// Backdrops render as wide banners, never full-screen: w780 is enough at 3x.
	tmdbBackdropBase = "https://image.tmdb.org/t/p/w780"
	// Episode stills render as row thumbnails and in the episode sheet: w300 covers both.
	tmdbStillBase = "https://image.tmdb.org/t/p/w300"
	tmdbLogoBase  = "https://image.tmdb.org/t/p/w92"
	// tmdbEnrichLimit: search results are enriched with IMDb ids up to this many hits.
	tmdbEnrichLimit = 10
)

// TMDB is the TMDB adapter (CAT-002): search and detail for movies and shows,
// external ids, and season/episode lists, plus Discover rows, seasons and the on-air
// guide. No TMDB field name leaves this adapter.
type TMDB struct {
	Client *provider.Client
	// APIKey is a v3 API key (sent as `api_key`) or a v4 read token (sent as a Bearer header).
	APIKey string
	// BaseURL defaults to TMDBBaseURL; tests point it at a stub server.
	BaseURL string
}

// Search finds movies or shows.
func (t *TMDB) Search(ctx context.Context, query string, mediaType core.MediaType) ([]Hit, error) {
	kind, err := tmdbKind(mediaType)
	if err != nil {
		return nil, err
	}
	var page tmdbSearchPage
	if err := t.get(ctx, "search/"+kind, map[string]string{"query": query, "include_adult": "false"}, &page); err != nil {
		return nil, err
	}
	var hits []Hit
	for _, d := range page.Results {
		if h, ok := d.hit(mediaType); ok {
			hits = append(hits, h)
		}
	}
	return t.withIMDbIDs(ctx, hits), nil
}

// SearchMulti is CAT-019: films and shows in one query. People and adult titles are dropped.
func (t *TMDB) SearchMulti(ctx context.Context, query string) ([]Hit, error) {
	var page tmdbSearchPage
	if err := t.get(ctx, "search/multi", map[string]string{"query": query, "include_adult": "false"}, &page); err != nil {
		return nil, err
	}
	var hits []Hit
	for _, d := range page.Results {
		if h, ok := d.mixedHit(); ok {
			hits = append(hits, h)
		}
	}
	return t.withIMDbIDs(ctx, hits), nil
}

// withIMDbIDs fills `imdb` on the top hits from each title's external ids,
// concurrently and paced. A failed lookup leaves the id empty.
func (t *TMDB) withIMDbIDs(ctx context.Context, hits []Hit) []Hit {
	enriched := slices.Clone(hits)
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i, hit := range hits[:min(len(hits), tmdbEnrichLimit)] {
		kind, err := tmdbKind(hit.Type)
		if hit.IDs.TMDB == "" || err != nil {
			continue
		}
		wg.Go(func() {
			var body tmdbExternalIDs
			imdb := ""
			if t.get(ctx, kind+"/"+hit.IDs.TMDB+"/external_ids", nil, &body) == nil {
				imdb = sval(nilIfBlank(body.IMDbID))
			}
			mu.Lock()
			enriched[i].IDs.IMDB = imdb
			mu.Unlock()
		})
	}
	wg.Wait()
	return enriched
}

// Hydrate is the full record for a movie or show these ids identify.
func (t *TMDB) Hydrate(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error) {
	kind, err := tmdbKind(mediaType)
	if err != nil {
		return nil, err
	}
	id, err := t.tmdbID(ctx, ids, kind)
	if err != nil || id == "" {
		return nil, err
	}
	var detail tmdbDetail
	if err := t.get(ctx, kind+"/"+id, map[string]string{"append_to_response": "external_ids"}, &detail); err != nil {
		if provider.IsNotFound(err) {
			return nil, nil //nolint:nilnil // nil: not known
		}
		return nil, err
	}
	hit, ok := detail.hit(mediaType)
	if !ok {
		return nil, nil //nolint:nilnil // nil: not known
	}
	hit.IDs = hit.IDs.Filling(ids)
	genres := []string{}
	for _, g := range detail.Genres {
		if n := nilIfBlank(g.Name); n != nil {
			genres = append(genres, *n)
		}
	}
	return &Record{Hit: hit, Status: detail.titleStatus(), RuntimeMinutes: detail.Runtime, Genres: genres}, nil
}

// tmdbID is the TMDB id directly, or found through IMDb / TVDB ids.
func (t *TMDB) tmdbID(ctx context.Context, ids core.ExternalIDs, kind string) (string, error) {
	if ids.TMDB != "" {
		return ids.TMDB, nil
	}
	for _, lookup := range [][2]string{{ids.IMDB, "imdb_id"}, {ids.TVDB, "tvdb_id"}} {
		if lookup[0] == "" {
			continue
		}
		var found tmdbFindResult
		if err := t.get(ctx, "find/"+lookup[0], map[string]string{"external_source": lookup[1]}, &found); err != nil {
			return "", err
		}
		results := found.TVResults
		if kind == "movie" {
			results = found.MovieResults
		}
		if len(results) > 0 {
			return strconv.Itoa(results[0].ID), nil
		}
	}
	return "", nil
}

// Episodes is every episode of the show, season by season, sorted.
func (t *TMDB) Episodes(ctx context.Context, ids core.ExternalIDs) (*Episodes, error) {
	id, err := t.tmdbID(ctx, ids, "tv")
	if err != nil || id == "" {
		return nil, err
	}
	var show tmdbDetail
	if err := t.get(ctx, "tv/"+id, nil, &show); err != nil {
		if provider.IsNotFound(err) {
			return nil, nil //nolint:nilnil // nil: not known
		}
		return nil, err
	}
	var fallbackRuntime *int
	if len(show.EpisodeRunTime) > 0 {
		fallbackRuntime = intPtr(show.EpisodeRunTime[0])
	}
	seasons := make([][]Episode, len(show.Seasons))
	group, gctx := errgroup.WithContext(ctx)
	for i, summary := range show.Seasons {
		group.Go(func() error {
			var season tmdbSeason
			if err := t.get(gctx, "tv/"+id+"/season/"+strconv.Itoa(summary.SeasonNumber), nil, &season); err != nil {
				return err
			}
			for _, e := range season.Episodes {
				runtime := e.Runtime
				if runtime == nil {
					runtime = fallbackRuntime
				}
				var still *string
				if e.StillPath != nil {
					still = strPtr(tmdbStillBase + *e.StillPath)
				}
				var episodeID *string
				if e.ID != nil {
					episodeID = strPtr(strconv.Itoa(*e.ID))
				}
				seasons[i] = append(seasons[i], Episode{
					Season: e.SeasonNumber, Episode: e.EpisodeNumber, Name: nilIfBlank(e.Name),
					AirsAt: ParseDay(e.AirDate), RuntimeMinutes: runtime, TMDBEpisodeID: episodeID,
					Overview: nilIfBlank(e.Overview), StillURL: still,
				})
			}
			return nil
		})
	}
	if err := group.Wait(); err != nil {
		return nil, err
	}
	episodes := []Episode{}
	for _, s := range seasons {
		episodes = append(episodes, s...)
	}
	slices.SortStableFunc(episodes, func(a, b Episode) int {
		return cmp.Or(cmp.Compare(a.Season, b.Season), cmp.Compare(a.Episode, b.Episode))
	})
	return &Episodes{Status: show.titleStatus(), Episodes: episodes, BackdropURL: show.backdropURL(), Network: show.network()}, nil
}

func tmdbKind(mediaType core.MediaType) (string, error) {
	switch mediaType {
	case core.MediaMovie:
		return "movie", nil
	case core.MediaShow:
		return "tv", nil
	}
	return "", provider.NewError("tmdb", provider.KindNotFound)
}

func (t *TMDB) get(ctx context.Context, path string, query map[string]string, v any) error {
	headers := [][2]string{{"Accept", "application/json"}}
	var extra [][2]string
	if strings.Contains(t.APIKey, ".") {
		headers = append(headers, [2]string{"Authorization", "Bearer " + t.APIKey})
	} else {
		extra = append(extra, [2]string{"api_key", t.APIKey})
	}
	return getJSON(ctx, t.Client, buildURL(cmp.Or(t.BaseURL, TMDBBaseURL), path, query, extra...), headers, v)
}

// MARK: - Discover (DISC-001)

// tmdbOffRowGenres are TV genres a "what to watch" row leaves out: news, soap, talk.
var tmdbOffRowGenres = map[int]bool{10763: true, 10766: true, 10767: true}

// tmdbNewShowWindow: "New shows" premiered within this window.
const tmdbNewShowWindow = 90 * 24 * time.Hour

// DiscoverLists are the rows TMDB serves.
func (t *TMDB) DiscoverLists() []DiscoverList {
	return []DiscoverList{ListTVTrending, ListTVOnAir, ListTVNew, ListMoviesTrending, ListMoviesInTheaters}
}

// List fetches one Discover row; the anime rows are the stand-in while AniList is down.
func (t *TMDB) List(ctx context.Context, list DiscoverList, now time.Time) ([]Hit, error) {
	var mediaType core.MediaType
	var path string
	query := map[string]string{"include_adult": "false"}
	switch list {
	case ListTVTrending:
		mediaType, path = core.MediaShow, "trending/tv/week"
	case ListTVOnAir:
		mediaType, path = core.MediaShow, "tv/on_the_air"
	case ListTVNew:
		mediaType, path = core.MediaShow, "discover/tv"
		query["first_air_date.gte"] = dayString(now.Add(-tmdbNewShowWindow))
		query["first_air_date.lte"] = dayString(now)
		query["sort_by"] = "popularity.desc"
		// Popularity alone surfaces shows nobody has rated yet.
		query["vote_count.gte"] = "10"
	case ListMoviesTrending:
		mediaType, path = core.MediaMovie, "trending/movie/week"
	case ListMoviesInTheaters:
		mediaType, path = core.MediaMovie, "movie/now_playing"
	case ListAnimeSeason, ListAnimeTrending:
		// Not in DiscoverLists: AniList serves these. TMDB's Japanese animation stands in
		// only while AniList is down (CAT-021).
		mediaType, path = core.MediaShow, "discover/tv"
		extra, err := tmdbAnimeQuery(list, now)
		if err != nil {
			return nil, err
		}
		for k, v := range extra {
			query[k] = v
		}
	default:
		return nil, provider.NewError("tmdb", provider.KindNotFound)
	}
	var page tmdbSearchPage
	if err := t.get(ctx, path, query, &page); err != nil {
		return nil, err
	}
	return tmdbRowHits(page, mediaType, list == ListAnimeSeason || list == ListAnimeTrending), nil
}

// onAirPage is one page of `tv/on_the_air` as row cards with posters, and whether
// another follows (DISC-003).
func (t *TMDB) onAirPage(ctx context.Context, page int) ([]Hit, bool, error) {
	var body tmdbSearchPage
	if err := t.get(ctx, "tv/on_the_air", map[string]string{"include_adult": "false", "page": strconv.Itoa(page)}, &body); err != nil {
		return nil, false, err
	}
	var hits []Hit
	for _, h := range tmdbRowHits(body, core.MediaShow, false) {
		if h.PosterURL != nil {
			hits = append(hits, h)
		}
	}
	total := 1
	if body.TotalPages != nil {
		total = *body.TotalPages
	}
	return hits, page < total, nil
}

// tmdbRowHits is a page as row cards. Anime rows come from AniList, so TV rows drop
// anime, and news, soap and talk shows; anime keeps them instead, for the stand-in rows.
func tmdbRowHits(page tmdbSearchPage, mediaType core.MediaType, anime bool) []Hit {
	hits := []Hit{}
	for _, entry := range page.Results {
		hit, ok := entry.hit(mediaType)
		if !ok {
			continue
		}
		if anime {
			hit.IsAnime = true
			hits = append(hits, hit)
			continue
		}
		if mediaType != core.MediaShow {
			hits = append(hits, hit)
			continue
		}
		offRow := false
		for _, g := range entry.GenreIDs {
			if tmdbOffRowGenres[g] {
				offRow = true
			}
		}
		if !hit.IsAnime && !offRow {
			hits = append(hits, hit)
		}
	}
	return hits
}

// tmdbAnimeQuery is Japanese animation: this season's premieres, or what aired in
// the last and next week.
func tmdbAnimeQuery(list DiscoverList, now time.Time) (map[string]string, error) {
	query := map[string]string{"with_genres": "16", "with_origin_country": "JP", "sort_by": "popularity.desc"}
	if list == ListAnimeSeason {
		season := CurrentSeason(now)
		first, last := season.Days()
		query["first_air_date.gte"] = first
		query["first_air_date.lte"] = last
	} else {
		query["air_date.gte"] = dayString(now.Add(-7 * 24 * time.Hour))
		query["air_date.lte"] = dayString(now.Add(7 * 24 * time.Hour))
	}
	return query, nil
}

// MARK: - Seasons (DISC-002)

// tmdbMaxDiscoverPage: TMDB serves at most this many discover pages.
const tmdbMaxDiscoverPage = 500

// SeasonKinds are the Seasons lists TMDB serves.
func (t *TMDB) SeasonKinds() []SeasonKind {
	return []SeasonKind{SeasonShowsNew, SeasonShowsReturning, SeasonMovies}
}

// Season is one page of a season's shows or films.
func (t *TMDB) Season(ctx context.Context, key SeasonKey, kind SeasonKind, page int, now time.Time) (SeasonPage, error) {
	first, last := key.Days()
	start, end := key.Range()
	query := map[string]string{"include_adult": "false", "sort_by": "popularity.desc", "page": strconv.Itoa(page)}
	var mediaType core.MediaType
	var path string
	switch kind {
	case SeasonShowsNew:
		mediaType, path = core.MediaShow, "discover/tv"
		query["first_air_date.gte"] = first
		query["first_air_date.lte"] = last
	case SeasonShowsReturning:
		mediaType, path = core.MediaShow, "discover/tv"
		query["air_date.gte"] = first
		query["air_date.lte"] = last
		query["first_air_date.lte"] = dayString(start.Add(-24 * time.Hour))
	case SeasonMovies:
		mediaType, path = core.MediaMovie, "discover/movie"
		query["primary_release_date.gte"] = first
		query["primary_release_date.lte"] = last
	default:
		return SeasonPage{}, provider.NewError("tmdb", provider.KindNotFound)
	}
	// An ended season has votes; without a floor its popular end fills with unrated
	// titles. A current or coming season has none yet, so it gets no floor.
	if !end.After(now) {
		query["vote_count.gte"] = "10"
	}
	var body tmdbSearchPage
	if err := t.get(ctx, path, query, &body); err != nil {
		return SeasonPage{}, err
	}
	lastPage := page
	if body.TotalPages != nil {
		lastPage = *body.TotalPages
	}
	lastPage = min(lastPage, tmdbMaxDiscoverPage)
	return SeasonPage{Hits: tmdbRowHits(body, mediaType, false), HasMore: page < lastPage, Total: body.TotalResults}, nil
}

// MARK: - TMDB wire shapes (private to this adapter)

type tmdbSearchPage struct {
	Results []tmdbDetail `json:"results"`
	// TotalPages and TotalResults are on discover pages only.
	TotalPages   *int `json:"total_pages"`
	TotalResults *int `json:"total_results"`
}

type tmdbExternalIDs struct {
	IMDbID *string `json:"imdb_id"`
	TVDBID *int    `json:"tvdb_id"`
}

type tmdbFindResult struct {
	MovieResults []struct {
		ID int `json:"id"`
	} `json:"movie_results"`
	TVResults []struct {
		ID int `json:"id"`
	} `json:"tv_results"`
}

type tmdbSeason struct {
	Episodes []struct {
		ID            *int    `json:"id"`
		SeasonNumber  int     `json:"season_number"`
		EpisodeNumber int     `json:"episode_number"`
		Name          *string `json:"name"`
		Overview      *string `json:"overview"`
		AirDate       *string `json:"air_date"`
		Runtime       *int    `json:"runtime"`
		StillPath     *string `json:"still_path"`
	} `json:"episodes"`
}

// tmdbDetail is the shape movie and TV detail/search entries share; fields absent
// on one kind are nil.
type tmdbDetail struct {
	ID            int     `json:"id"`
	Title         *string `json:"title"`
	Name          *string `json:"name"`
	OriginalTitle *string `json:"original_title"`
	OriginalName  *string `json:"original_name"`
	ReleaseDate   *string `json:"release_date"`
	FirstAirDate  *string `json:"first_air_date"`
	PosterPath    *string `json:"poster_path"`
	BackdropPath  *string `json:"backdrop_path"`
	Networks      []struct {
		Name string `json:"name"`
	} `json:"networks"`
	Overview *string `json:"overview"`
	GenreIDs []int   `json:"genre_ids"`
	Genres   []struct {
		ID   int     `json:"id"`
		Name *string `json:"name"`
	} `json:"genres"`
	OriginalLanguage *string `json:"original_language"`
	Status           *string `json:"status"`
	Runtime          *int    `json:"runtime"`
	EpisodeRunTime   []int   `json:"episode_run_time"`
	Seasons          []struct {
		SeasonNumber int `json:"season_number"`
	} `json:"seasons"`
	ExternalIDs *tmdbExternalIDs `json:"external_ids"`
	IMDbID      *string          `json:"imdb_id"`
	// MediaType is on `search/multi` only: movie, tv or person.
	MediaType *string `json:"media_type"`
	Adult     *bool   `json:"adult"`
}

func (d tmdbDetail) backdropURL() *string {
	if d.BackdropPath == nil {
		return nil
	}
	return strPtr(tmdbBackdropBase + *d.BackdropPath)
}

// network is the first network TMDB lists: the original broadcaster or streamer.
func (d tmdbDetail) network() *string {
	if len(d.Networks) == 0 {
		return nil
	}
	return blankToNil(d.Networks[0].Name)
}

// mixedHit is a mixed-list entry as a film or show; people and adult titles are not.
func (d tmdbDetail) mixedHit() (Hit, bool) {
	if d.Adult != nil && *d.Adult {
		return Hit{}, false
	}
	switch sval(d.MediaType) {
	case "movie":
		return d.hit(core.MediaMovie)
	case "tv":
		return d.hit(core.MediaShow)
	}
	return Hit{}, false
}

func (d tmdbDetail) hit(mediaType core.MediaType) (Hit, bool) {
	display := d.Title
	if display == nil {
		display = d.Name
	}
	display = nilIfBlank(display)
	if display == nil {
		return Hit{}, false
	}
	genreIDs := d.GenreIDs
	if genreIDs == nil {
		for _, g := range d.Genres {
			genreIDs = append(genreIDs, g.ID)
		}
	}
	original := d.OriginalTitle
	if original == nil {
		original = d.OriginalName
	}
	if original != nil && *original == *display {
		original = nil
	}
	date := d.ReleaseDate
	if date == nil {
		date = d.FirstAirDate
	}
	var poster *string
	if d.PosterPath != nil {
		poster = strPtr(tmdbImageBase + *d.PosterPath)
	}
	imdb := d.IMDbID
	tvdb := ""
	if d.ExternalIDs != nil {
		if d.ExternalIDs.IMDbID != nil {
			imdb = d.ExternalIDs.IMDbID
		}
		if d.ExternalIDs.TVDBID != nil {
			tvdb = strconv.Itoa(*d.ExternalIDs.TVDBID)
		}
	}
	release := nilIfBlank(d.ReleaseDate)
	if release == nil {
		release = d.FirstAirDate
	}
	return Hit{
		Type: mediaType, Title: *display, OriginalTitle: original, Year: ParseYear(date), PosterURL: poster,
		Overview: nilIfBlank(d.Overview),
		IDs:      core.ExternalIDs{TMDB: strconv.Itoa(d.ID), IMDB: sval(nilIfBlank(imdb)), TVDB: tvdb},
		// Japanese animation. AniList is the anime catalog; this flags TMDB hits.
		IsAnime:     slices.Contains(genreIDs, 16) && sval(d.OriginalLanguage) == "ja",
		BackdropURL: d.backdropURL(), Network: d.network(), ReleaseDate: ParseDate(release),
	}, true
}

func (d tmdbDetail) titleStatus() *TitleStatus {
	var s TitleStatus
	switch sval(d.Status) {
	case "Returning Series", "In Production":
		s = StatusReturning
	case "Planned", "Pilot", "Post Production", "Rumored":
		s = StatusUpcoming
	case "Ended":
		s = StatusEnded
	case "Canceled":
		s = StatusCanceled
	default:
		return nil
	}
	return &s
}
