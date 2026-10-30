package catalog

import (
	"aaru-go-api/internal/provider"
	"context"
	"slices"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sync/errgroup"
)

// TMDBOnAirLimit notes: the guide covers this many shows, two on-the-air pages after the row filter.
const TMDBOnAirLimit = 40

// OnAir is TMDB's on-the-air shows (an episode within the next week) with their next
// episode, first network and streaming services in every region, one detail call each.
func (t *TMDB) OnAir(ctx context.Context, now time.Time) ([]OnAirShow, error) {
	var hits []Hit
	for page := 1; page <= 2; page++ {
		found, more, err := t.onAirPage(ctx, page)
		if err != nil {
			return nil, err
		}
		hits = append(hits, found...)
		if !more {
			break
		}
	}
	seen := map[string]bool{}
	var unique []Hit
	for _, h := range hits {
		if h.IDs.TMDB == "" || seen[h.IDs.TMDB] {
			continue
		}
		seen[h.IDs.TMDB] = true
		if len(unique) < TMDBOnAirLimit {
			unique = append(unique, h)
		}
	}
	// A week back covers a show whose next episode TMDB has not rolled over yet.
	from, until := now.Add(-24*time.Hour), now.Add(8*24*time.Hour)
	shows := make([]*OnAirShow, len(unique))
	group, gctx := errgroup.WithContext(ctx)
	for i, hit := range unique {
		group.Go(func() error {
			var detail tmdbOnAirDetail
			err := t.get(gctx, "tv/"+hit.IDs.TMDB, map[string]string{"append_to_response": "external_ids,watch/providers"}, &detail)
			if provider.IsNotFound(err) {
				return nil
			}
			if err != nil {
				return err
			}
			shows[i] = detail.show(hit, from, until)
			return nil
		})
	}
	if err := group.Wait(); err != nil {
		return nil, err
	}
	out := []OnAirShow{}
	for _, s := range shows {
		if s != nil {
			out = append(out, *s)
		}
	}
	return out, nil
}

// tmdbOnAirDetail is `tv/{id}` with external ids and watch providers, for the guide only.
type tmdbOnAirDetail struct {
	Networks []struct {
		Name     string  `json:"name"`
		LogoPath *string `json:"logo_path"`
	} `json:"networks"`
	NextEpisodeToAir *struct {
		AirDate       *string `json:"air_date"`
		SeasonNumber  int     `json:"season_number"`
		EpisodeNumber int     `json:"episode_number"`
		Name          *string `json:"name"`
	} `json:"next_episode_to_air"`
	ExternalIDs    *tmdbExternalIDs `json:"external_ids"`
	WatchProviders *struct {
		Results map[string]struct {
			Link     *string        `json:"link"`
			Flatrate []tmdbFlatrate `json:"flatrate"`
		} `json:"results"`
	} `json:"watch/providers"`
}

// tmdbFlatrate is one streaming service in a region's `watch/providers` entry (JustWatch data).
type tmdbFlatrate struct {
	ProviderName    string  `json:"provider_name"`
	LogoPath        *string `json:"logo_path"`
	DisplayPriority *int    `json:"display_priority"`
}

func tmdbLogo(path *string) *string {
	if path == nil {
		return nil
	}
	return strPtr(tmdbLogoBase + *path)
}

func (d tmdbOnAirDetail) show(hit Hit, from, until time.Time) *OnAirShow {
	next := d.NextEpisodeToAir
	if next == nil {
		return nil
	}
	airsAt := ParseDay(next.AirDate)
	if airsAt == nil || airsAt.Before(from) || airsAt.After(until) {
		return nil
	}
	if d.ExternalIDs != nil {
		if hit.IDs.IMDB == "" {
			hit.IDs.IMDB = sval(nilIfBlank(d.ExternalIDs.IMDbID))
		}
		if hit.IDs.TVDB == "" && d.ExternalIDs.TVDBID != nil {
			hit.IDs.TVDB = strconv.Itoa(*d.ExternalIDs.TVDBID)
		}
	}
	var channel *OnAirChannel
	if len(d.Networks) > 0 {
		if name := blankToNil(d.Networks[0].Name); name != nil {
			channel = &OnAirChannel{Name: *name, LogoURL: tmdbLogo(d.Networks[0].LogoPath)}
		}
	}
	if channel != nil {
		hit.Network = &channel.Name
	}
	providers := map[string]WatchProviders{}
	if d.WatchProviders != nil {
		for code, region := range d.WatchProviders.Results {
			flat := slices.Clone(region.Flatrate)
			slices.SortStableFunc(flat, func(a, b tmdbFlatrate) int {
				return priority(a.DisplayPriority) - priority(b.DisplayPriority)
			})
			var streaming []WatchProvider
			for _, p := range flat {
				if name := blankToNil(p.ProviderName); name != nil {
					streaming = append(streaming, WatchProvider{Name: *name, LogoURL: tmdbLogo(p.LogoPath)})
				}
			}
			if len(streaming) == 0 {
				continue
			}
			providers[strings.ToUpper(code)] = WatchProviders{Link: region.Link, Streaming: streaming}
		}
	}
	return &OnAirShow{
		Hit: hit, Channel: channel, Providers: providers,
		Next: OnAirEpisode{Season: next.SeasonNumber, Number: next.EpisodeNumber, Name: nilIfBlank(next.Name), AirsAt: *airsAt},
	}
}

func priority(p *int) int {
	if p == nil {
		return int(^uint(0) >> 2)
	}
	return *p
}
