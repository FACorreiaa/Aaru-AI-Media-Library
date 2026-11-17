package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"time"
)

// Where to watch a title (CAT-014): the services that stream, rent or sell a film or show in one
// country, from TMDB's `watch/providers` (JustWatch data, which must be credited). Catalog data
// like a synopsis: read when asked, cached in memory, never stored. Aaru links out to TMDB's page
// and plays nothing.

const (
	// WatchTTL is how long a title's services are served from memory. Catalogues change by the
	// week, not the hour.
	WatchTTL = 6 * time.Hour
	// WatchCacheCapacity bounds the titles whose services are held.
	WatchCacheCapacity = 500
	// WatchLimit is how many services one group (stream, rent, buy) lists.
	WatchLimit = 8
)

// TitleWatch is where a title can be watched in one region.
type TitleWatch struct {
	// Link is TMDB's page of every way to watch it there. TMDB has no link per service.
	Link *string
	// Streaming is with a subscription; Rent and Buy are paid per title.
	Streaming, Rent, Buy []WatchProvider
}

// Empty is no service in any group: the client then shows nothing.
func (w TitleWatch) Empty() bool { return len(w.Streaming)+len(w.Rent)+len(w.Buy) == 0 }

// WatchSource is a provider that knows where titles are watched, every region at once so one
// cached answer serves all of them. Nil, with no error, when it does not know the title.
type WatchSource interface {
	WatchRegions(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (map[string]TitleWatch, error)
}

// WatchService reads where a film or show is watched.
type WatchService struct {
	// Source may be nil: nothing is then known.
	Source WatchSource
	cache  *sharedCache[string, map[string]TitleWatch]
	Now    func() time.Time
}

// NewWatchService builds the service; a provider that is no WatchSource leaves it empty.
func NewWatchService(video any, log *slog.Logger) *WatchService {
	s := &WatchService{
		cache: newSharedCache[string, map[string]TitleWatch](WatchCacheCapacity, "Where to watch failed"),
		Now:   time.Now,
	}
	s.cache.log = log
	if source, ok := video.(WatchSource); ok && source != nil {
		s.Source = source
	}
	return s
}

// For is where the title is watched in the region (ISO 3166-1 alpha-2, upper case). Nil when it
// is not a film or show, the provider does not know it or did not answer, or the region has no
// service: one answer for "nothing to show".
func (s *WatchService) For(ctx context.Context, title core.Title, region string) *TitleWatch {
	if s == nil || s.Source == nil || region == "" {
		return nil
	}
	if title.Type != core.MediaMovie && title.Type != core.MediaShow {
		return nil
	}
	regions, ok := s.cache.get(ctx, title.ID.String(), s.Now(),
		func(map[string]TitleWatch) time.Duration { return WatchTTL },
		func(ctx context.Context) (map[string]TitleWatch, error) {
			regions, err := s.Source.WatchRegions(ctx, title.IDs, title.Type)
			if err != nil {
				return nil, fmt.Errorf("where to watch: %w", err)
			}
			return regions, nil
		})
	if !ok {
		return nil
	}
	watch, found := regions[region]
	if !found || watch.Empty() {
		return nil
	}
	return &watch
}

// watchResellers are the entries JustWatch lists beside a service for the same catalogue
// ("… Amazon Channel", "… with Ads"): noise next to the service itself.
var watchResellers = []string{"amazon channel", "apple tv channel", "roku premium channel", "with ads"}

func isWatchReseller(lowerName string) bool {
	return slices.ContainsFunc(watchResellers, func(r string) bool { return strings.Contains(lowerName, r) })
}

// MARK: - TMDB

// tmdbWatchRegions is `{kind}/{id}/watch/providers`.
type tmdbWatchRegions struct {
	Results map[string]struct {
		Link     *string        `json:"link"`
		Flatrate []tmdbFlatrate `json:"flatrate"`
		Rent     []tmdbFlatrate `json:"rent"`
		Buy      []tmdbFlatrate `json:"buy"`
	} `json:"results"`
}

// WatchRegions is where TMDB says the film or show streams, rents and sells, by region.
func (t *TMDB) WatchRegions(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (map[string]TitleWatch, error) {
	kind, err := tmdbKind(mediaType)
	if err != nil {
		return nil, nil //nolint:nilnil,nilerr // not a kind TMDB has
	}
	id, err := t.tmdbID(ctx, ids, kind)
	if err != nil {
		return nil, err
	}
	if id == "" {
		return nil, nil //nolint:nilnil // TMDB does not know these ids
	}
	var body tmdbWatchRegions
	if err := t.get(ctx, kind+"/"+id+"/watch/providers", nil, &body); err != nil {
		if provider.IsNotFound(err) {
			return nil, nil //nolint:nilnil // TMDB no longer has this id
		}
		return nil, err
	}
	regions := map[string]TitleWatch{}
	for code, region := range body.Results {
		watch := TitleWatch{
			Link:      nilIfBlank(region.Link),
			Streaming: tmdbWatchGroup(region.Flatrate),
			Rent:      tmdbWatchGroup(region.Rent),
			Buy:       tmdbWatchGroup(region.Buy),
		}
		if !watch.Empty() {
			regions[strings.ToUpper(code)] = watch
		}
	}
	return regions, nil
}

// tmdbWatchGroup is one group's services in TMDB's display order, without resellers or a name
// twice, capped at WatchLimit.
func tmdbWatchGroup(entries []tmdbFlatrate) []WatchProvider {
	sorted := slices.Clone(entries)
	slices.SortStableFunc(sorted, func(a, b tmdbFlatrate) int {
		return priority(a.DisplayPriority) - priority(b.DisplayPriority)
	})
	seen := map[string]bool{}
	var out []WatchProvider
	for _, p := range sorted {
		name := blankToNil(p.ProviderName)
		if name == nil {
			continue
		}
		lower := strings.ToLower(*name)
		if seen[lower] || isWatchReseller(lower) {
			continue
		}
		seen[lower] = true
		out = append(out, WatchProvider{Name: *name, LogoURL: tmdbLogo(p.LogoPath)})
		if len(out) == WatchLimit {
			break
		}
	}
	return out
}
