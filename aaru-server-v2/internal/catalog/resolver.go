package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"context"
	"errors"
	"net/http"
	"slices"

	"github.com/google/uuid"
)

// ResolutionError is why a MediaRef could not become a Title. Import jobs count
// these as unmatched.
type ResolutionError int

// The resolution errors.
const (
	// ErrUnresolvable: no provider knows these ids, or no catalog entry matches the title + year.
	ErrUnresolvable ResolutionError = iota + 1
	// ErrAmbiguous: title + year matched more than one catalog entry. Never guess (IMP-007).
	ErrAmbiguous
)

func (e ResolutionError) Error() string { return e.AppError().Message }

// AppError is the 422 the API answers with.
func (e ResolutionError) AppError() *apperr.Error {
	if e == ErrAmbiguous {
		return apperr.New(http.StatusUnprocessableEntity, "ambiguous_match", "More than one catalog entry matches that title and year.")
	}
	return apperr.New(http.StatusUnprocessableEntity, "unresolvable", "No catalog entry matches that title.")
}

// ImportAiring is an episode a calendar says aired on a day (Pogdesign CAT's ICS).
type ImportAiring struct {
	Season  int    `json:"season"`
	Episode int    `json:"episode"`
	Day     string `json:"day"`
}

// MaxAiringCandidates notes: more same-name shows than this are not worth reading every
// episode list for.
const MaxAiringCandidates = 4

// Resolver turns a MediaRef into a Title, finding or hydrating (CAT-005). Every add
// and every import row goes through here.
//
// External ids first. Title + year only through a provider search with exactly one
// match, so two titles that merely share a name are never merged. Concurrent
// resolutions of the same work yield one `titles` row: the unique indexes decide,
// not a lock.
//
// A Resolver is a value: PrefetchingMAL and WithoutAniList return a copy.
type Resolver struct {
	Store     *Store
	Providers Providers
	// prefetchedMAL is AniList entries fetched ahead for one import run, by malKey
	// (IMP-017); unknownMAL the MAL ids AniList was asked about and does not know.
	prefetchedMAL map[string]Record
	unknownMAL    map[string]bool
	// aniListDown is AniList's failure on this run's batch, when the caller chose to
	// go on without it: refs only AniList could match fail with it at once.
	aniListDown error
}

// NewResolver builds a resolver.
func NewResolver(store *Store, providers Providers) Resolver {
	return Resolver{Store: store, Providers: providers}
}

// malKey is a MAL id as the prefetch keeps it: MAL numbers anime and manga apart (MNG-001).
func malKey(mal string, mediaType core.MediaType) string {
	if mediaType == core.MediaManga {
		return "manga:" + mal
	}
	return mal
}

// PrefetchingMAL is a resolver that already holds AniList's answer for every
// MyAnimeList-only ref that is not in the catalog yet and has no TMDB mapping: one
// request per 50 entries instead of one each. Refs that resolve another way are
// left alone.
func (r Resolver) PrefetchingMAL(ctx context.Context, refs []core.MediaRef) (Resolver, error) {
	batch, ok := r.Providers.AniList.(MALBatchHydrator)
	if !ok {
		return r, nil
	}
	var anime, manga []string
	seenAnime, seenManga := map[string]bool{}, map[string]bool{}
	for _, ref := range refs {
		if ref.TitleID != nil || (ref.Type != core.MediaMovie && ref.Type != core.MediaShow && ref.Type != core.MediaManga) {
			continue
		}
		ids := ref.IDs
		isManga := ref.Type == core.MediaManga
		seen := seenAnime
		if isManga {
			seen = seenManga
		}
		if ids.MAL == "" || ids.AniList != "" || ids.TMDB != "" || ids.IMDB != "" || ids.TVDB != "" || seen[ids.MAL] {
			continue
		}
		existing, err := r.Store.Find(ctx, ids, ref.Type)
		if err != nil {
			return r, err
		}
		if existing != nil {
			continue
		}
		if !isManga {
			mapping, err := r.AnimeMapping(ctx, ids)
			if err != nil {
				return r, err
			}
			if mapping != nil && mapping.TMDB != nil {
				continue
			}
		}
		seen[ids.MAL] = true
		if isManga {
			manga = append(manga, ids.MAL)
		} else {
			anime = append(anime, ids.MAL)
		}
	}
	if (len(anime) == 0 && len(manga) == 0) || r.aniListDown != nil {
		return r, nil
	}
	out := r
	out.prefetchedMAL = map[string]Record{}
	out.unknownMAL = map[string]bool{}
	for k, v := range r.prefetchedMAL {
		out.prefetchedMAL[k] = v
	}
	for k := range r.unknownMAL {
		out.unknownMAL[k] = true
	}
	for _, group := range []struct {
		wanted    []string
		mediaType core.MediaType
	}{{anime, core.MediaShow}, {manga, core.MediaManga}} {
		if len(group.wanted) == 0 {
			continue
		}
		found, err := batch.HydrateMAL(ctx, group.wanted, group.mediaType)
		if err != nil {
			return r, err
		}
		for mal, record := range found {
			out.prefetchedMAL[malKey(mal, group.mediaType)] = record
		}
		for _, mal := range group.wanted {
			if _, ok := found[mal]; !ok {
				out.unknownMAL[malKey(mal, group.mediaType)] = true
			}
		}
	}
	return out, nil
}

// WithoutAniList is a resolver that no longer asks AniList, after it failed with
// err. Anime with a TMDB mapping still resolve through TMDB.
func (r Resolver) WithoutAniList(err error) Resolver {
	r.aniListDown = err
	return r
}

// Resolve finds or creates the title a ref names. searchHint (an author, for books)
// narrows a title search. The only match it loosens is a book's year, by one, when
// the hint is also the hit's author (IMP-020).
func (r Resolver) Resolve(ctx context.Context, ref core.MediaRef, searchHint *string) (core.Title, error) {
	if err := ref.Validate(); err != nil {
		return core.Title{}, err
	}
	if ref.TitleID != nil {
		title, err := r.Store.Title(ctx, *ref.TitleID)
		if err != nil {
			return core.Title{}, err
		}
		if title == nil {
			return core.Title{}, ErrUnresolvable
		}
		return *title, nil
	}
	if !ref.IDs.IsEmpty() {
		return r.resolveIDs(ctx, ref.IDs, ref.Type)
	}
	return r.resolveByTitle(ctx, ref, searchHint)
}

// MARK: By ids

func (r Resolver) resolveIDs(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (core.Title, error) {
	existing, err := r.Store.Find(ctx, ids, mediaType)
	if err != nil {
		return core.Title{}, err
	}
	if existing != nil {
		if err := r.Store.FillIDs(ctx, existing.ID, ids); err != nil {
			return core.Title{}, err
		}
		return *existing, nil
	}
	record, err := r.hydrate(ctx, ids, mediaType)
	if err != nil {
		return core.Title{}, err
	}
	if record == nil {
		return core.Title{}, ErrUnresolvable
	}
	merged := record.Hit.IDs.Filling(ids)
	// The provider may have revealed an id another row already holds.
	existing, err = r.Store.Find(ctx, merged, record.Hit.Type)
	if err != nil {
		return core.Title{}, err
	}
	if existing != nil {
		if err := r.Store.FillIDs(ctx, existing.ID, merged); err != nil {
			return core.Title{}, err
		}
		return *existing, nil
	}
	hit := record.Hit
	title := core.Title{
		ID: uuid.New(), Type: hit.Type, Title: hit.Title, OriginalTitle: hit.OriginalTitle, Year: hit.Year,
		Synopsis: hit.Overview, PosterURL: hit.PosterURL, BackdropURL: hit.BackdropURL, Network: hit.Network,
		Byline: hit.Byline, PageCount: hit.PageCount, ChapterCount: hit.ChapterCount, VolumeCount: hit.VolumeCount,
		IDs: merged, IsAnime: hit.IsAnime,
	}
	err = r.Store.Insert(ctx, title, record.Status, record.RuntimeMinutes, record.Genres)
	if errors.Is(err, ErrTitleConflict) {
		// A concurrent resolution inserted it first.
		winner, err := r.Store.Find(ctx, merged, title.Type)
		if err != nil {
			return core.Title{}, err
		}
		if winner == nil {
			return core.Title{}, ErrUnresolvable
		}
		return *winner, nil
	}
	if err != nil {
		return core.Title{}, err
	}
	return title, nil
}

// Genres is the CAT-018 backfill: the genres the title's provider lists now; nil
// when no provider knows it.
func (r Resolver) Genres(ctx context.Context, title core.Title) ([]string, error) {
	record, err := r.hydrate(ctx, title.IDs, title.Type)
	if err != nil || record == nil {
		return nil, err
	}
	return nonNil(record.Genres), nil
}

// Hydrate is the record the owning provider has for these ids. Anime with a
// community TMDB mapping resolves to the TMDB show (CAT-009); otherwise AniList owns
// it. Manga is AniList's alone (MNG-001). Nil when no provider knows them.
func (r Resolver) Hydrate(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error) {
	return r.hydrate(ctx, ids, mediaType)
}

func (r Resolver) hydrate(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error) {
	switch mediaType {
	case core.MediaBook:
		return r.Providers.OpenLibrary.Hydrate(ctx, ids, mediaType)
	case core.MediaAlbum:
		if r.Providers.Music == nil {
			return nil, nil //nolint:nilnil // nil: not known
		}
		return r.Providers.Music.Hydrate(ctx, ids, mediaType)
	case core.MediaManga:
		return r.hydrateFromAniList(ctx, ids, mediaType)
	}
	mapping, err := r.AnimeMapping(ctx, ids)
	if err != nil {
		return nil, err
	}
	if mapping != nil && mapping.TMDB != nil {
		mapped := ids.Filling(core.ExternalIDs{
			TMDB: *mapping.TMDB, TVDB: sval(mapping.TVDB), MAL: sval(mapping.MAL), AniDB: sval(mapping.AniDB),
		})
		record, err := r.Providers.TMDB.Hydrate(ctx, mapped, core.MediaShow)
		if err != nil {
			return nil, err
		}
		if record != nil {
			record.Hit.IsAnime = true
			record.Hit.IDs = record.Hit.IDs.Filling(mapped)
			return record, nil
		}
	}
	if ids.TMDB != "" || ids.IMDB != "" || ids.TVDB != "" {
		return r.Providers.TMDB.Hydrate(ctx, ids, mediaType)
	}
	return r.hydrateFromAniList(ctx, ids, mediaType)
}

// hydrateFromAniList is AniList by its own id or a MAL id, through this run's
// prefetch when it has the answer.
func (r Resolver) hydrateFromAniList(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error) {
	if ids.AniList == "" && ids.MAL != "" {
		key := malKey(ids.MAL, mediaType)
		if record, ok := r.prefetchedMAL[key]; ok {
			record.Hit.IDs = record.Hit.IDs.Filling(ids)
			return &record, nil
		}
		if r.unknownMAL[key] {
			return nil, nil //nolint:nilnil // nil: not known
		}
	}
	if ids.AniList != "" || ids.MAL != "" {
		if r.aniListDown != nil {
			return nil, r.aniListDown
		}
		return r.Providers.AniList.Hydrate(ctx, ids, mediaType)
	}
	return nil, nil //nolint:nilnil // e.g. a Trakt-only id
}

// AnimeMapping is the community mapping for an anime: by AniList id, else by MAL id
// (a MAL export has no AniList id, and must still land on the TMDB show a Trakt
// import created).
func (r Resolver) AnimeMapping(ctx context.Context, ids core.ExternalIDs) (*AnimeMapping, error) {
	if ids.AniList != "" {
		mapping, err := r.Store.MappingByAniList(ctx, ids.AniList)
		if err != nil || mapping != nil {
			return mapping, err
		}
	}
	if ids.MAL != "" {
		return r.Store.MappingByMAL(ctx, ids.MAL)
	}
	return nil, nil //nolint:nilnil // nil: not known
}

// MARK: By title + year

func (r Resolver) resolveByTitle(ctx context.Context, ref core.MediaRef, hint *string) (core.Title, error) {
	if ref.Title == nil {
		return core.Title{}, ErrUnresolvable
	}
	var source Searcher
	switch ref.Type {
	case core.MediaBook:
		source = r.Providers.OpenLibrary
	case core.MediaAlbum:
		if r.Providers.Music == nil {
			return core.Title{}, ErrUnresolvable
		}
		source = r.Providers.Music
	case core.MediaMovie, core.MediaShow:
		source = r.Providers.TMDB
	case core.MediaManga:
		source = r.Providers.AniList
	default:
		return core.Title{}, ErrUnresolvable
	}
	query := *ref.Title
	if hint != nil {
		query += " " + *hint
	}
	hits, err := source.Search(ctx, query, ref.Type)
	if err != nil {
		return core.Title{}, err
	}
	wanted := core.MediaRef{Type: ref.Type, Title: ref.Title, Year: ref.Year}
	var matches []Hit
	for _, h := range hits {
		if h.Year != nil && core.CanMerge(wanted, h.MediaRef()) {
			matches = append(matches, h)
		}
	}
	// IMP-020: a book one year off, only when the author is the hit's too.
	if len(matches) == 0 && ref.Type == core.MediaBook {
		for _, h := range hits {
			if core.CanMergeBook(wanted, hint, h.MediaRef(), h.Byline) {
				matches = append(matches, h)
			}
		}
	}
	switch len(matches) {
	case 0:
		return core.Title{}, ErrUnresolvable
	case 1:
		return r.resolveIDs(ctx, matches[0].IDs, ref.Type)
	default:
		return core.Title{}, ErrAmbiguous
	}
}

// MARK: By name only

// ResolveNamed finds a movie or show known only by its name (Pogdesign CAT, IMP-009;
// Netflix, IMP-018): the one TMDB entry of the type whose normalized title equals it,
// in any year up to notAfter (the year it was watched). Two with the name (a remake)
// are ambiguous, never a guess, unless airing (from CAT's calendar) is an episode
// exactly one of the shows airs that day.
func (r Resolver) ResolveNamed(ctx context.Context, name string, mediaType core.MediaType, airing *ImportAiring, notAfter *int) (core.Title, error) {
	wanted := core.NormalizeTitle(name)
	if (mediaType != core.MediaMovie && mediaType != core.MediaShow) || wanted == "" {
		return core.Title{}, ErrUnresolvable
	}
	hits, err := r.Providers.TMDB.Search(ctx, name, mediaType)
	if err != nil {
		return core.Title{}, err
	}
	var matches []Hit
	for _, h := range hits {
		if h.Type != mediaType || h.Year == nil || core.NormalizeTitle(h.Title) != wanted {
			continue
		}
		if notAfter == nil || *h.Year <= *notAfter {
			matches = append(matches, h)
		}
	}
	if len(matches) == 0 {
		return core.Title{}, ErrUnresolvable
	}
	if len(matches) == 1 {
		return r.resolveIDs(ctx, matches[0].IDs, mediaType)
	}
	if mediaType != core.MediaShow || airing == nil {
		return core.Title{}, ErrAmbiguous
	}
	hit, err := r.airs(ctx, *airing, matches)
	if err != nil {
		return core.Title{}, err
	}
	if hit == nil {
		return core.Title{}, ErrAmbiguous
	}
	return r.resolveIDs(ctx, hit.IDs, core.MediaShow)
}

// EpisodesNamed is the episodes of title that names describe (Netflix names
// episodes, it does not number them). Names that match nothing, or more than one
// episode, are left out. Sorted, without duplicates.
func (r Resolver) EpisodesNamed(ctx context.Context, title core.Title, names []NamedEpisode) ([]core.EpisodeKey, error) {
	if title.Type != core.MediaShow || len(names) == 0 {
		return []core.EpisodeKey{}, nil
	}
	list, err := r.Providers.TMDB.Episodes(ctx, title.IDs)
	if err != nil {
		return nil, err
	}
	if list == nil {
		return []core.EpisodeKey{}, nil
	}
	seen := map[core.EpisodeKey]bool{}
	keys := []core.EpisodeKey{}
	for _, n := range names {
		if k, ok := MatchEpisodeName(n, list.Episodes); ok && !seen[k] {
			seen[k] = true
			keys = append(keys, k)
		}
	}
	slices.SortFunc(keys, core.EpisodeKey.Compare)
	return keys, nil
}

// airs is the one candidate with airing's episode dated within a day of it (calendar
// times are local, catalog dates are UTC days). None or several is no answer.
func (r Resolver) airs(ctx context.Context, airing ImportAiring, hits []Hit) (*Hit, error) {
	day := ParseDay(&airing.Day)
	year := ParseYear(&airing.Day)
	if len(hits) > MaxAiringCandidates || day == nil || year == nil {
		return nil, nil //nolint:nilnil // nil: not known
	}
	var airingHits []Hit
	for _, h := range hits {
		if h.Year != nil && *h.Year > *year {
			continue
		}
		list, err := r.Providers.TMDB.Episodes(ctx, h.IDs)
		if err != nil {
			return nil, err
		}
		if list == nil {
			continue
		}
		for _, e := range list.Episodes {
			if e.Season != airing.Season || e.Episode != airing.Episode || e.AirsAt == nil {
				continue
			}
			if d := e.AirsAt.Sub(*day); d <= 86400e9 && d >= -86400e9 {
				airingHits = append(airingHits, h)
				break
			}
		}
	}
	if len(airingHits) != 1 {
		return nil, nil //nolint:nilnil // nil: not known
	}
	return &airingHits[0], nil
}

// IsResolutionError reports whether err is a ResolutionError, and which.
func IsResolutionError(err error) (ResolutionError, bool) {
	var re ResolutionError
	ok := errors.As(err, &re)
	return re, ok
}
