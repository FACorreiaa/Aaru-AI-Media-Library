package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Hydration windows (CAT-006).
const (
	// AiringWindow: shows with an episode airing within this window re-hydrate daily.
	AiringWindow = 30 * 24 * time.Hour
	// AiringStaleness is how old an airing show's episodes may get.
	AiringStaleness = 24 * time.Hour
	// DormantStaleness is how old any other show's episodes, or an album's tracks, may get.
	DormantStaleness = 30 * 24 * time.Hour
	// AllLimit is the All scope's cap on merged hits.
	AllLimit = 40
	// DefaultAniListDeadline is how long the All scope waits for AniList before
	// answering with TMDB alone.
	DefaultAniListDeadline = 2 * time.Second
)

// SearchScope is a search scope a client can ask for. `anime` is AniList; `all` is
// films, shows and anime together (books stay out); the others map to their MediaType.
type SearchScope string

// The search scopes.
const (
	ScopeAll   SearchScope = "all"
	ScopeMovie SearchScope = "movie"
	ScopeShow  SearchScope = "show"
	ScopeAnime SearchScope = "anime"
	ScopeBook  SearchScope = "book"
	ScopeAlbum SearchScope = "album"
	ScopeManga SearchScope = "manga"
)

// Search notices, in words a client can show.
const (
	NoticeAniListDown = "AniList is down right now, so anime results come from TMDB and may be missing some."
	NoticeMangaDown   = "AniList is down right now, so manga can't be searched. Try again in a little while."
)

// SearchResult is search hits, and whether a provider failed so the hits are only
// part of the answer.
type SearchResult struct {
	Hits       []Hit
	Incomplete bool
	// Notice says why the hits are partial, when a provider is down.
	Notice *string
}

// TitleDetail is a title as the detail route returns it: the catalog row plus show state.
type TitleDetail struct {
	Title          core.Title
	Status         *TitleStatus
	RuntimeMinutes *int
	// Episodes is shows only; nil for movies and books.
	Episodes []Episode
	// Tracks is albums only (MUS-001); nil until a tracklist was fetched once.
	Tracks []AlbumTrack
	Genres []string
}

// Service is catalog reads: search (CAT-004) and title detail with lazy episode
// hydration (CAT-006).
type Service struct {
	Store     *Store
	Providers Providers
	// Now defaults to time.Now.
	Now func() time.Time
	// AniListDeadline defaults to DefaultAniListDeadline.
	AniListDeadline time.Duration
}

// NewService builds the catalog service.
func NewService(store *Store, providers Providers) *Service {
	return &Service{Store: store, Providers: providers, Now: time.Now, AniListDeadline: DefaultAniListDeadline}
}

func (s *Service) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

// ErrSearchLength is the 422 for a query outside 1–200 characters.
func ErrSearchLength() *apperr.Error {
	return apperr.Validation("q", "Search needs 1–200 characters.")
}

// Search finds titles in one scope.
func (s *Service) Search(ctx context.Context, query string, scope SearchScope) (SearchResult, error) {
	trimmed := strings.TrimSpace(query)
	if trimmed == "" || utf8.RuneCountInString(trimmed) > 200 {
		return SearchResult{}, ErrSearchLength()
	}
	hits := func(h []Hit, err error) (SearchResult, error) {
		if err != nil {
			return SearchResult{}, err
		}
		return SearchResult{Hits: h}, nil
	}
	switch scope {
	case ScopeAll:
		return s.searchAll(ctx, trimmed)
	case ScopeMovie:
		return hits(s.Providers.TMDB.Search(ctx, trimmed, core.MediaMovie))
	case ScopeShow:
		return hits(s.Providers.TMDB.Search(ctx, trimmed, core.MediaShow))
	case ScopeAnime:
		return s.searchAnime(ctx, trimmed)
	case ScopeBook:
		return hits(s.Providers.OpenLibrary.Search(ctx, trimmed, core.MediaBook))
	case ScopeAlbum:
		if s.Providers.Music == nil {
			return SearchResult{Hits: []Hit{}, Incomplete: true}, nil
		}
		return hits(s.Providers.Music.Search(ctx, trimmed, core.MediaAlbum))
	case ScopeManga:
		return s.searchManga(ctx, trimmed)
	default:
		return SearchResult{}, apperr.Validation("type", "Unknown search type.")
	}
}

// Detail is a stored title with its show state, hydrating episodes when stale.
func (s *Service) Detail(ctx context.Context, id uuid.UUID) (*TitleDetail, error) {
	title, err := s.Store.Title(ctx, id)
	if err != nil {
		return nil, err
	}
	if title == nil {
		return nil, apperr.NotFound()
	}
	state, err := s.Store.State(ctx, id)
	if err != nil {
		return nil, err
	}
	if state == nil {
		return nil, apperr.NotFound()
	}
	if title.Type == core.MediaAlbum {
		return s.albumDetail(ctx, *title, *state)
	}
	if title.Type != core.MediaShow {
		return &TitleDetail{Title: *title, Status: state.Status, RuntimeMinutes: state.RuntimeMinutes, Genres: []string{}}, nil
	}
	episodes, err := s.Store.ShowEpisodes(ctx, id)
	if err != nil {
		return nil, err
	}
	status := state.Status
	if s.NeedsHydration(*state, episodes) {
		fromAniList := title.IsAnime && title.IDs.TMDB == ""
		var source EpisodeLister = s.Providers.TMDB
		if fromAniList {
			source = s.Providers.AniList
		}
		fresh, err := freshEpisodes(ctx, source, title.IDs, episodes)
		if err != nil {
			return nil, err
		}
		if fresh != nil {
			// AniList times are already exact. TVmaze failing never fails the hydration.
			if !fromAniList && s.Providers.AirTimes != nil {
				if refined, err := s.Providers.AirTimes.Refine(ctx, *fresh, title.IDs); err == nil {
					fresh = &refined
				}
			}
			if err := s.Store.SaveEpisodes(ctx, id, *fresh, s.now()); err != nil {
				return nil, err
			}
			if episodes, err = s.Store.ShowEpisodes(ctx, id); err != nil {
				return nil, err
			}
			status = fresh.Status
		}
	}
	return &TitleDetail{
		Title: *title, Status: status, RuntimeMinutes: state.RuntimeMinutes, Episodes: nonNil(episodes), Genres: []string{},
	}, nil
}

func nonNil[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}

// freshEpisodes is the provider's episodes. While AniList is down, a show it already
// hydrated keeps the stored episodes rather than failing; only a never-hydrated show
// reports the outage. Nil without an error means keep what is stored.
func freshEpisodes(ctx context.Context, source EpisodeLister, ids core.ExternalIDs, stored []Episode) (*Episodes, error) {
	fresh, err := source.Episodes(ctx, ids)
	if err != nil {
		if provider.IsAniListOutage(err) && len(stored) > 0 {
			return nil, nil //nolint:nilnil // nil: not known
		}
		return nil, err
	}
	return fresh, nil
}

// searchAnime is AniList, or while it is down, TMDB's Japanese animation (CAT-021).
func (s *Service) searchAnime(ctx context.Context, query string) (SearchResult, error) {
	hits, err := s.Providers.AniList.Search(ctx, query, core.MediaShow)
	if err == nil {
		return SearchResult{Hits: hits}, nil
	}
	if !provider.IsAniListOutage(err) {
		return SearchResult{}, err
	}
	multi, err := s.Providers.TMDB.SearchMulti(ctx, query)
	if err != nil {
		return SearchResult{}, err
	}
	anime := []Hit{}
	for _, h := range multi {
		if h.IsAnime {
			anime = append(anime, h)
		}
	}
	return SearchResult{Hits: anime, Incomplete: true, Notice: strPtr(NoticeAniListDown)}, nil
}

// searchManga is AniList alone: no other catalog Aaru reads has manga, so an outage
// is an empty answer that says why (MNG-001).
func (s *Service) searchManga(ctx context.Context, query string) (SearchResult, error) {
	hits, err := s.Providers.AniList.Search(ctx, query, core.MediaManga)
	if err == nil {
		return SearchResult{Hits: hits}, nil
	}
	if provider.IsAniListOutage(err) {
		return SearchResult{Hits: []Hit{}, Incomplete: true, Notice: strPtr(NoticeMangaDown)}, nil
	}
	return SearchResult{}, err
}

// albumDetail is an album with its tracklist, fetched the first time and again after
// DormantStaleness. MusicBrainz failing never fails the page: the album shows
// without its tracks.
func (s *Service) albumDetail(ctx context.Context, title core.Title, state State) (*TitleDetail, error) {
	var tracks []AlbumTrack
	if state.TracksHydratedAt != nil {
		stored, err := s.Store.Tracks(ctx, title.ID)
		if err != nil {
			return nil, err
		}
		tracks = nonNil(stored)
	}
	stale := state.TracksHydratedAt == nil || s.now().Sub(*state.TracksHydratedAt) >= DormantStaleness
	if stale && s.Providers.Music != nil {
		if fresh, err := s.Providers.Music.Tracks(ctx, title.IDs); err == nil && fresh != nil {
			if err := s.Store.SaveTracks(ctx, title.ID, fresh, s.now()); err != nil {
				return nil, err
			}
			tracks = fresh
		}
	}
	genres, err := s.Store.Genres(ctx, title.ID)
	if err != nil {
		return nil, err
	}
	return &TitleDetail{Title: title, Tracks: tracks, Genres: nonNil(genres)}, nil
}

// NeedsHydration is true when episodes were never hydrated, or are older than their
// window: 24h while an episode airs within 30 days, 30 days otherwise.
func (s *Service) NeedsHydration(state State, episodes []Episode) bool {
	if state.EpisodesHydratedAt == nil {
		return true
	}
	now := s.now()
	window := DormantStaleness
	for _, e := range episodes {
		if e.AirsAt == nil {
			continue
		}
		if d := e.AirsAt.Sub(now); d <= AiringWindow && d >= -AiringWindow {
			window = AiringStaleness
			break
		}
	}
	return now.Sub(*state.EpisodesHydratedAt) >= window
}

// MARK: - All scope (CAT-019)

type hitsResult struct {
	hits []Hit
	err  error
}

// searchAll runs TMDB multi search and AniList in parallel, AniList under a deadline.
// One failing leaves the other's hits, marked incomplete; both failing returns
// TMDB's error (502).
func (s *Service) searchAll(ctx context.Context, query string) (SearchResult, error) {
	videoCh := make(chan hitsResult, 1)
	animeCh := make(chan hitsResult, 1)
	go func() {
		h, err := s.Providers.TMDB.SearchMulti(ctx, query)
		videoCh <- hitsResult{h, err}
	}()
	go func() {
		h, err := Within(ctx, s.aniListDeadline(), "anilist", func(ctx context.Context) ([]Hit, error) {
			return s.Providers.AniList.Search(ctx, query, core.MediaShow)
		})
		animeCh <- hitsResult{h, err}
	}()
	video, anime := <-videoCh, <-animeCh
	if err := ctx.Err(); err != nil {
		return SearchResult{}, err
	}
	switch {
	case video.err != nil && anime.err != nil:
		return SearchResult{}, video.err
	case anime.err != nil:
		return SearchResult{Hits: Ranked(video.hits, nil, query), Incomplete: true, Notice: strPtr(NoticeAniListDown)}, nil
	case video.err != nil:
		return SearchResult{Hits: Ranked(nil, anime.hits, query), Incomplete: true}, nil
	}
	keptVideo, mappedAnime, err := s.Deduplicated(ctx, video.hits, anime.hits)
	if err != nil {
		return SearchResult{}, err
	}
	return SearchResult{Hits: Ranked(keptVideo, mappedAnime, query)}, nil
}

func (s *Service) aniListDeadline() time.Duration {
	if s.AniListDeadline <= 0 {
		return DefaultAniListDeadline
	}
	return s.AniListDeadline
}

// Deduplicated drops a TMDB show only when `anime_mappings` links an AniList show in
// the same results to it; that AniList hit gains the TMDB id. Nothing is ever merged
// on a name.
func (s *Service) Deduplicated(ctx context.Context, video, anime []Hit) ([]Hit, []Hit, error) {
	var anilistIDs []string
	for _, h := range anime {
		if h.Type == core.MediaShow && h.IDs.AniList != "" {
			anilistIDs = append(anilistIDs, h.IDs.AniList)
		}
	}
	if len(anilistIDs) == 0 {
		return video, anime, nil
	}
	mappings, err := s.Store.MappingsByAniList(ctx, anilistIDs)
	if err != nil {
		return nil, nil, err
	}
	tmdbByAniList := map[string]string{}
	for _, m := range mappings {
		if _, seen := tmdbByAniList[m.AniList]; m.TMDB != nil && !seen {
			tmdbByAniList[m.AniList] = *m.TMDB
		}
	}
	mapped := map[string]bool{}
	outAnime := make([]Hit, len(anime))
	for i, h := range anime {
		outAnime[i] = h
		if h.Type != core.MediaShow || h.IDs.AniList == "" {
			continue
		}
		if tmdb, ok := tmdbByAniList[h.IDs.AniList]; ok {
			mapped[tmdb] = true
			outAnime[i].IDs = h.IDs.Filling(core.ExternalIDs{TMDB: tmdb})
		}
	}
	outVideo := []Hit{}
	for _, h := range video {
		if h.Type != core.MediaShow || h.IDs.TMDB == "" || !mapped[h.IDs.TMDB] {
			outVideo = append(outVideo, h)
		}
	}
	return outVideo, outAnime, nil
}

// Ranked puts exact title matches first, then TMDB and AniList alternating, at most AllLimit.
func Ranked(video, anime []Hit, query string) []Hit {
	var merged []Hit
	for i := range max(len(video), len(anime)) {
		if i < len(video) {
			merged = append(merged, video[i])
		}
		if i < len(anime) {
			merged = append(merged, anime[i])
		}
	}
	wanted := core.NormalizeTitle(query)
	isExact := func(h Hit) bool {
		if wanted == "" {
			return false
		}
		return core.NormalizeTitle(h.Title) == wanted || (h.OriginalTitle != nil && core.NormalizeTitle(*h.OriginalTitle) == wanted)
	}
	exact, rest := []Hit{}, []Hit{}
	for _, h := range merged {
		if isExact(h) {
			exact = append(exact, h)
		} else {
			rest = append(rest, h)
		}
	}
	all := append(exact, rest...)
	return all[:min(AllLimit, len(all))]
}

// Within runs op, giving up after deadline with the provider unavailable.
func Within[T any](ctx context.Context, deadline time.Duration, providerName string, op func(context.Context) (T, error)) (T, error) {
	inner, cancel := context.WithCancel(ctx)
	defer cancel()
	type result struct {
		value T
		err   error
	}
	done := make(chan result, 1)
	go func() {
		v, err := op(inner)
		done <- result{v, err}
	}()
	timer := time.NewTimer(deadline)
	defer timer.Stop()
	select {
	case r := <-done:
		return r.value, r.err
	case <-timer.C:
		var zero T
		return zero, provider.NewError(providerName, provider.KindUnavailable)
	case <-ctx.Done():
		var zero T
		return zero, ctx.Err()
	}
}
