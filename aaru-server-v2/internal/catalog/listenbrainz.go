package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"slices"
	"strconv"
	"time"

	"golang.org/x/sync/errgroup"
)

// ListenBrainzBaseURL is ListenBrainz's API root.
const ListenBrainzBaseURL = "https://api.listenbrainz.org/1"

// ListenBrainzVariousArtists is credited on compilations; it is not an artist anyone follows.
const ListenBrainzVariousArtists = "89ad4ac3-39f7-470e-963a-56509c546377"

const (
	listenBrainzWindow     = "30"
	listenBrainzStatsCount = "1000"
)

// ListenBrainz is Discover's album rows (MUS-002), no key. Fresh releases carry no
// listen counts of their own, so each list is ranked by what ListenBrainz users play
// this month: New albums are this month's most-played release groups that came out
// in the last 30 days; Coming soon is the next 30 days of releases by this month's
// most-played artists, soonest first. Albums and EPs with a cover only, never
// compilations of others, live records or spoken word. The same rows for everyone.
type ListenBrainz struct {
	Client    *provider.Client
	UserAgent string
	// BaseURL defaults to ListenBrainzBaseURL.
	BaseURL string
}

// DiscoverLists are the rows ListenBrainz serves.
func (l *ListenBrainz) DiscoverLists() []DiscoverList {
	return []DiscoverList{ListMusicNew, ListMusicUpcoming}
}

// List fetches one album row.
func (l *ListenBrainz) List(ctx context.Context, list DiscoverList, _ time.Time) ([]Hit, error) {
	switch list {
	case ListMusicNew:
		return l.newAlbums(ctx)
	case ListMusicUpcoming:
		return l.upcoming(ctx)
	default:
		return nil, provider.NewError("listenbrainz", provider.KindNotFound)
	}
}

func (l *ListenBrainz) newAlbums(ctx context.Context) ([]Hit, error) {
	var fresh []lbFreshRelease
	var played struct {
		Payload struct {
			ReleaseGroups []lbPlayedGroup `json:"release_groups"`
		} `json:"payload"`
	}
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) { fresh, err = l.releases(gctx, true); return err })
	g.Go(func() error {
		return l.get(gctx, "stats/sitewide/release-groups", map[string]string{"range": "this_month", "count": listenBrainzStatsCount}, &played)
	})
	if err := g.Wait(); err != nil {
		return nil, err
	}
	byGroup := map[string]lbFreshRelease{}
	for _, r := range fresh {
		if _, seen := byGroup[r.ReleaseGroupMBID]; r.isTracked() && !seen {
			byGroup[r.ReleaseGroupMBID] = r
		}
	}
	groups := played.Payload.ReleaseGroups
	slices.SortStableFunc(groups, func(a, b lbPlayedGroup) int { return cmp.Compare(b.ListenCount, a.ListenCount) })
	hits := []Hit{}
	for _, g := range groups {
		if g.ReleaseGroupMBID == nil {
			continue
		}
		if r, ok := byGroup[*g.ReleaseGroupMBID]; ok {
			hits = append(hits, r.hit())
		}
	}
	return hits, nil
}

func (l *ListenBrainz) upcoming(ctx context.Context) ([]Hit, error) {
	var fresh []lbFreshRelease
	var played struct {
		Payload struct {
			Artists []struct {
				ArtistMBID *string `json:"artist_mbid"`
			} `json:"artists"`
		} `json:"payload"`
	}
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) { fresh, err = l.releases(gctx, false); return err })
	g.Go(func() error {
		return l.get(gctx, "stats/sitewide/artists", map[string]string{"range": "this_month", "count": listenBrainzStatsCount}, &played)
	})
	if err := g.Wait(); err != nil {
		return nil, err
	}
	rank := map[string]int{}
	for i, a := range played.Payload.Artists {
		if a.ArtistMBID == nil || *a.ArtistMBID == ListenBrainzVariousArtists {
			continue
		}
		if _, ok := rank[*a.ArtistMBID]; !ok {
			rank[*a.ArtistMBID] = i
		}
	}
	type ranked struct {
		release lbFreshRelease
		rank    int
	}
	var picked []ranked
	for _, r := range fresh {
		if !r.isTracked() {
			continue
		}
		best, found := 0, false
		for _, id := range r.ArtistMBIDs {
			if n, ok := rank[id]; ok && (!found || n < best) {
				best, found = n, true
			}
		}
		if found {
			picked = append(picked, ranked{r, best})
		}
	}
	slices.SortStableFunc(picked, func(a, b ranked) int {
		return cmp.Or(cmp.Compare(a.release.ReleaseDate, b.release.ReleaseDate), cmp.Compare(a.rank, b.rank))
	})
	hits := make([]Hit, 0, len(picked))
	for _, p := range picked {
		hits = append(hits, p.release.hit())
	}
	return hits, nil
}

func (l *ListenBrainz) releases(ctx context.Context, past bool) ([]lbFreshRelease, error) {
	pastValue, futureValue := "false", "true"
	if past {
		pastValue, futureValue = "true", "false"
	}
	var page struct {
		Payload struct {
			Releases []lbFreshRelease `json:"releases"`
		} `json:"payload"`
	}
	err := l.get(ctx, "explore/fresh-releases/", map[string]string{"days": listenBrainzWindow, "past": pastValue, "future": futureValue}, &page)
	return page.Payload.Releases, err
}

func (l *ListenBrainz) get(ctx context.Context, path string, query map[string]string, v any) error {
	headers := [][2]string{{"User-Agent", cmp.Or(l.UserAgent, config.DefaultProviderUserAgent)}, {"Accept", "application/json"}}
	return getJSON(ctx, l.Client, buildURL(cmp.Or(l.BaseURL, ListenBrainzBaseURL), path, query), headers, v)
}

type lbPlayedGroup struct {
	ReleaseGroupMBID *string `json:"release_group_mbid"`
	ListenCount      int     `json:"listen_count"`
}

type lbFreshRelease struct {
	ArtistCreditName          string   `json:"artist_credit_name"`
	ArtistMBIDs               []string `json:"artist_mbids"`
	CAAID                     *int64   `json:"caa_id"`
	CAAReleaseMBID            *string  `json:"caa_release_mbid"`
	ReleaseDate               string   `json:"release_date"`
	ReleaseGroupMBID          string   `json:"release_group_mbid"`
	ReleaseGroupPrimaryType   *string  `json:"release_group_primary_type"`
	ReleaseGroupSecondaryType *string  `json:"release_group_secondary_type"`
	ReleaseName               string   `json:"release_name"`
}

// isTracked: an album or an EP of new work, with a cover to show.
func (r lbFreshRelease) isTracked() bool {
	return MusicBrainzTrackedTypes[sval(r.ReleaseGroupPrimaryType)] && r.ReleaseGroupSecondaryType == nil &&
		r.CAAID != nil && r.CAAReleaseMBID != nil
}

func (r lbFreshRelease) hit() Hit {
	var poster *string
	if r.CAAReleaseMBID != nil && r.CAAID != nil {
		poster = strPtr("https://coverartarchive.org/release/" + *r.CAAReleaseMBID + "/" + strconv.FormatInt(*r.CAAID, 10) + "-250.jpg")
	}
	return Hit{
		Type: core.MediaAlbum, Title: r.ReleaseName, Year: ParseYear(&r.ReleaseDate), PosterURL: poster,
		Byline: strPtr(r.ArtistCreditName), IDs: core.ExternalIDs{MusicBrainz: r.ReleaseGroupMBID},
		ReleaseDate: ParseDate(&r.ReleaseDate),
	}
}
