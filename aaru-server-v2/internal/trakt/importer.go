package trakt

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"context"
	"slices"
	"strconv"
	"time"

	"github.com/google/uuid"
	"golang.org/x/sync/errgroup"
)

// Importer is IMP-003: reads a user's Trakt library into import rows. Watched history (with every
// watched episode), watchlist, ratings and lists; the plan-then-approve pipeline does the rest.
type Importer struct {
	API *API
}

// Rows reads the whole library. The reads run at once on Trakt's shared pacer; the first failure
// stops the rest.
func (im *Importer) Rows(ctx context.Context, token string) ([]imports.Row, error) {
	var (
		movies                    []WatchedMovie
		shows                     []WatchedShow
		watchMovies, watchShows   []Item
		ratingMovies, ratingShows []Item
		lists                     []List
	)
	api := im.API
	validMovie := func(m WatchedMovie) bool { return validMedia(m.Movie) }
	validShow := func(s WatchedShow) bool { return validMedia(s.Show) && validSeasons(s.Seasons) }
	validList := func(l List) bool { return l.Name != nil && l.IDs != nil && l.IDs.Trakt != nil }
	g, gctx := errgroup.WithContext(ctx)
	item := func(path string, out *[]Item) func() error {
		return func() error {
			got, err := paged(gctx, api, path, nil, token, validItem)
			*out = got
			return err
		}
	}
	g.Go(func() error {
		got, err := paged(gctx, api, "sync/watched/movies", nil, token, validMovie)
		movies = got
		return err
	})
	// Since 2026-06-30 watched shows carry no seasons unless asked for progress.
	g.Go(func() error {
		got, err := paged(gctx, api, "sync/watched/shows", [][2]string{{"extended", "progress"}}, token, validShow)
		shows = got
		return err
	})
	g.Go(item("sync/watchlist/movies", &watchMovies))
	g.Go(item("sync/watchlist/shows", &watchShows))
	g.Go(item("sync/ratings/movies", &ratingMovies))
	g.Go(item("sync/ratings/shows", &ratingShows))
	g.Go(func() error {
		got, err := paged(gctx, api, "users/me/lists", nil, token, validList)
		lists = got
		return err
	})
	if err := g.Wait(); err != nil {
		return nil, err
	}

	b := builder{index: map[string]int{}}
	for _, entry := range movies {
		b.add(*entry.Movie, core.MediaMovie, core.StatusFinished, parseDate(entry.LastWatchedAt), nil)
	}
	for _, entry := range shows {
		var watched []core.EpisodeKey
		for _, season := range entry.Seasons {
			for _, e := range season.Episodes {
				if key, err := core.NewEpisodeKey(*season.Number, *e.Number); err == nil {
					watched = append(watched, key)
				}
			}
		}
		b.add(*entry.Show, core.MediaShow, core.StatusInProgress, nil, watched)
	}
	for _, it := range append(watchMovies, watchShows...) {
		if media, mediaType, ok := mediaOf(it); ok {
			b.add(media, mediaType, core.StatusWishlist, nil, nil)
		}
	}
	for _, it := range append(ratingMovies, ratingShows...) {
		media, mediaType, ok := mediaOf(it)
		if !ok || it.Rating == nil {
			continue
		}
		b.rate(media, mediaType, float64(*it.Rating))
	}
	for _, list := range lists {
		items, err := paged(ctx, api, "users/me/lists/"+strconv.Itoa(*list.IDs.Trakt)+"/items", nil, token, validItem)
		if err != nil {
			return nil, err
		}
		for _, it := range items {
			if media, mediaType, ok := mediaOf(it); ok {
				b.list(media, mediaType, *list.Name)
			}
		}
	}
	if b.rows == nil {
		return []imports.Row{}, nil
	}
	return b.rows, nil
}

// builder keys rows by Trakt id, so a title that is watched, rated and on a list is one row.
type builder struct {
	rows  []imports.Row
	index map[string]int
}

func key(m Media, mediaType core.MediaType) string {
	id := ""
	switch {
	case m.IDs.Trakt != nil:
		id = strconv.Itoa(*m.IDs.Trakt)
	case m.IDs.IMDB != nil:
		id = *m.IDs.IMDB
	case m.Title != nil:
		id = *m.Title
	}
	return string(mediaType) + ":" + id
}

func (b *builder) row(m Media, mediaType core.MediaType) int {
	k := key(m, mediaType)
	if existing, ok := b.index[k]; ok {
		return existing
	}
	var sourceKey *string
	if m.IDs.Trakt != nil {
		sk := "trakt:" + strconv.Itoa(*m.IDs.Trakt)
		sourceKey = &sk
	}
	title := "Untitled"
	if m.Title != nil {
		title = *m.Title
	}
	listOnly := true
	b.rows = append(b.rows, imports.Row{
		SourceKey: sourceKey, Type: mediaType, Title: title, Year: m.Year, IDs: m.IDs.ExternalIDs(),
		Lists: []string{}, ListOnly: &listOnly,
	})
	b.index[k] = len(b.rows) - 1
	return len(b.rows) - 1
}

// add: the first status wins: watched history comes first, then the watchlist.
func (b *builder) add(m Media, mediaType core.MediaType, status core.LibraryStatus, finishedAt *time.Time, watched []core.EpisodeKey) {
	r := &b.rows[b.row(m, mediaType)]
	r.ListOnly = nil
	if r.Status == nil {
		st := status
		r.Status = &st
	}
	if r.FinishedAt == nil {
		r.FinishedAt = finishedAt
	}
	if len(watched) > 0 {
		r.Watched = watched
	}
}

// rate: a rating alone means the title was watched.
func (b *builder) rate(m Media, mediaType core.MediaType, rating float64) {
	r := &b.rows[b.row(m, mediaType)]
	r.Rating = &rating
	if r.ListOnly != nil && *r.ListOnly {
		r.ListOnly = nil
		st := core.StatusFinished
		r.Status = &st
	}
}

// list: a title only on a list joins the list without joining the library.
func (b *builder) list(m Media, mediaType core.MediaType, name string) {
	r := &b.rows[b.row(m, mediaType)]
	if !slices.Contains(r.Lists, name) {
		r.Lists = append(r.Lists, name)
	}
}

func mediaOf(it Item) (Media, core.MediaType, bool) {
	switch *it.Type {
	case "movie":
		if it.Movie != nil {
			return *it.Movie, core.MediaMovie, true
		}
	case "show":
		if it.Show != nil {
			return *it.Show, core.MediaShow, true
		}
	}
	return Media{}, "", false
}

// parseDate reads Trakt's ISO 8601 timestamps, with or without fractional seconds.
func parseDate(raw *string) *time.Time {
	if raw == nil {
		return nil
	}
	t, err := time.Parse(time.RFC3339Nano, *raw)
	if err != nil {
		return nil
	}
	return &t
}

// Source is the import worker's view of Trakt (imports.TraktSource).
type Source struct {
	Connect  *ConnectService
	Importer *Importer
}

var _ imports.TraktSource = (*Source)(nil)

// NewSource is Trakt for imports over one API.
func NewSource(store *Store, settings *Settings, api *API) *Source {
	return &Source{Connect: &ConnectService{Store: store, Settings: settings, API: api}, Importer: &Importer{API: api}}
}

// Connected is whether the user has a Trakt connection.
func (s *Source) Connected(ctx context.Context, user uuid.UUID) (bool, error) {
	st, err := s.Connect.Status(ctx, user)
	return st.Connected, err
}

// AccessToken is a fresh access token; nil when not connected.
func (s *Source) AccessToken(ctx context.Context, user uuid.UUID) (*string, error) {
	return s.Connect.AccessToken(ctx, user)
}

// Rows reads the user's Trakt library as import rows.
func (s *Source) Rows(ctx context.Context, token string) ([]imports.Row, error) {
	return s.Importer.Rows(ctx, token)
}

// DeleteConnection forgets the user's tokens (a revoked connection).
func (s *Source) DeleteConnection(ctx context.Context, user uuid.UUID) error {
	return s.Connect.Store.DeleteConnection(ctx, user)
}
