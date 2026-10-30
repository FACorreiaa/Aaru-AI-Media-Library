package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"sync"
	"time"
)

// fakeCatalog is every provider role at once, from stubbed answers. Test-only.
type fakeCatalog struct {
	mu            sync.Mutex
	searchResults map[string][]Hit
	titles        []Record
	episodeLists  map[string]Episodes
	calls         map[string]int
	failure       error
	latency       time.Duration
	discoverHits  map[DiscoverList][]Hit
	seasonHits    map[SeasonKind][]Hit
	onAirShows    []OnAirShow
	trackLists    map[string][]AlbumTrack
}

func newFake() *fakeCatalog {
	return &fakeCatalog{
		searchResults: map[string][]Hit{}, episodeLists: map[string]Episodes{}, calls: map[string]int{},
		discoverHits: map[DiscoverList][]Hit{}, seasonHits: map[SeasonKind][]Hit{}, trackLists: map[string][]AlbumTrack{},
	}
}

func (f *fakeCatalog) providers() Providers {
	return Providers{TMDB: f, AniList: f, OpenLibrary: f, Music: f}
}

func (f *fakeCatalog) fail(err error) { f.mu.Lock(); f.failure = err; f.mu.Unlock() }

func (f *fakeCatalog) stubSearch(query string, hits []Hit) {
	f.mu.Lock()
	f.searchResults[query] = hits
	f.mu.Unlock()
}

func (f *fakeCatalog) stubTitle(r Record) { f.mu.Lock(); f.titles = append(f.titles, r); f.mu.Unlock() }

// stubEpisodes is keyed by the show's tmdb or anilist id.
func (f *fakeCatalog) stubEpisodes(key string, e Episodes) {
	f.mu.Lock()
	f.episodeLists[key] = e
	f.mu.Unlock()
}

func (f *fakeCatalog) delay(d time.Duration) { f.mu.Lock(); f.latency = d; f.mu.Unlock() }

func (f *fakeCatalog) callCount(name string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls[name]
}

func (f *fakeCatalog) record(name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls[name]++
	return f.failure
}

func (f *fakeCatalog) wait(ctx context.Context) error {
	f.mu.Lock()
	d := f.latency
	f.mu.Unlock()
	if d == 0 {
		return nil
	}
	select {
	case <-time.After(d):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (f *fakeCatalog) Search(ctx context.Context, query string, _ core.MediaType) ([]Hit, error) {
	if err := f.record("search"); err != nil {
		return nil, err
	}
	if err := f.wait(ctx); err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.searchResults[query], nil
}

func (f *fakeCatalog) SearchMulti(ctx context.Context, query string) ([]Hit, error) {
	if err := f.record("searchMulti"); err != nil {
		return nil, err
	}
	if err := f.wait(ctx); err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.searchResults[query], nil
}

func (f *fakeCatalog) Hydrate(_ context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error) {
	if err := f.record("hydrate"); err != nil {
		return nil, err
	}
	// Simulate provider latency so concurrent resolutions overlap.
	time.Sleep(5 * time.Millisecond)
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, r := range f.titles {
		if r.Hit.Type == mediaType && r.Hit.IDs.Matches(ids) {
			return &r, nil
		}
	}
	return nil, nil //nolint:nilnil // not known
}

func (f *fakeCatalog) HydrateMAL(_ context.Context, malIDs []string, mediaType core.MediaType) (map[string]Record, error) {
	if err := f.record("hydrateMAL"); err != nil {
		return nil, err
	}
	wanted := map[string]bool{}
	for _, id := range malIDs {
		wanted[id] = true
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	found := map[string]Record{}
	for _, r := range f.titles {
		if (r.Hit.Type == core.MediaManga) != (mediaType == core.MediaManga) {
			continue
		}
		if mal := r.Hit.IDs.MAL; mal != "" && wanted[mal] {
			if _, ok := found[mal]; !ok {
				found[mal] = r
			}
		}
	}
	return found, nil
}

func (f *fakeCatalog) Episodes(_ context.Context, ids core.ExternalIDs) (*Episodes, error) {
	if err := f.record("episodes"); err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if e, ok := f.episodeLists[ids.TMDB]; ids.TMDB != "" && ok {
		return &e, nil
	}
	if e, ok := f.episodeLists[ids.AniList]; ids.AniList != "" && ok {
		return &e, nil
	}
	return nil, nil //nolint:nilnil // not known
}

func (f *fakeCatalog) stubDiscover(list DiscoverList, hits []Hit) {
	f.mu.Lock()
	f.discoverHits[list] = hits
	f.mu.Unlock()
}

func (f *fakeCatalog) stubSeason(kind SeasonKind, hits []Hit) {
	f.mu.Lock()
	f.seasonHits[kind] = hits
	f.mu.Unlock()
}

func (f *fakeCatalog) SeasonKinds() []SeasonKind { return AllSeasonKinds }

func (f *fakeCatalog) Season(_ context.Context, _ SeasonKey, kind SeasonKind, _ int, _ time.Time) (SeasonPage, error) {
	if err := f.record("season"); err != nil {
		return SeasonPage{}, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	hits := f.seasonHits[kind]
	return SeasonPage{Hits: hits, Total: ptr(len(hits))}, nil
}

func (f *fakeCatalog) DiscoverLists() []DiscoverList { return AllDiscoverLists }

func (f *fakeCatalog) List(_ context.Context, list DiscoverList, _ time.Time) ([]Hit, error) {
	if err := f.record("discover"); err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.discoverHits[list], nil
}

func (f *fakeCatalog) stubOnAir(shows []OnAirShow) { f.mu.Lock(); f.onAirShows = shows; f.mu.Unlock() }

func (f *fakeCatalog) OnAir(context.Context, time.Time) ([]OnAirShow, error) {
	if err := f.record("onAir"); err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.onAirShows, nil
}

// stubTracks is keyed by the album's MusicBrainz release-group id.
func (f *fakeCatalog) stubTracks(mbid string, tracks []AlbumTrack) {
	f.mu.Lock()
	f.trackLists[mbid] = tracks
	f.mu.Unlock()
}

func (f *fakeCatalog) Tracks(_ context.Context, ids core.ExternalIDs) ([]AlbumTrack, error) {
	if err := f.record("tracks"); err != nil {
		return nil, err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if ids.MusicBrainz == "" {
		return nil, nil
	}
	return f.trackLists[ids.MusicBrainz], nil
}
