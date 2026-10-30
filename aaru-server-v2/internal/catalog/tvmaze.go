package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"strconv"
	"time"
)

// TVmazeBaseURL is TVmaze's API root.
const TVmazeBaseURL = "https://api.tvmaze.com"

// TVmazeDateTolerance notes: TVmaze and TMDB can number a season differently. A time is
// only trusted when its date is within this of TMDB's date for the same episode.
const TVmazeDateTolerance = 2 * 24 * time.Hour

// AirTimeRefiner refines a show's episode list with exact air times and its network
// (CAT-011). TMDB stays the episode source; this only replaces a date-only airsAt
// with the broadcast instant.
type AirTimeRefiner interface {
	Refine(ctx context.Context, episodes Episodes, ids core.ExternalIDs) (Episodes, error)
}

// TVmaze is the TVmaze adapter (CAT-011): no key, ~20 calls / 10 s per IP. Shows are
// found by TVDB or IMDb id; `airstamp` is the exact UTC instant. Data is CC BY-SA:
// credit TVmaze where it is shown (PRV-001).
type TVmaze struct {
	Client *provider.Client
	// BaseURL defaults to TVmazeBaseURL.
	BaseURL string
}

// Refine replaces date-only air times with TVmaze's instants, and the network with
// the one that premieres the show.
func (t *TVmaze) Refine(ctx context.Context, episodes Episodes, ids core.ExternalIDs) (Episodes, error) {
	show, err := t.lookup(ctx, ids)
	if err != nil || show == nil {
		return episodes, err
	}
	var listed []tvmazeEpisode
	if err := t.get(ctx, "shows/"+strconv.Itoa(show.ID)+"/episodes", map[string]string{"specials": "1"}, &listed); err != nil {
		return episodes, err
	}
	stamps := map[[2]int]time.Time{}
	for _, e := range listed {
		if e.Season == nil || e.Number == nil || e.Airstamp == nil {
			continue
		}
		if stamp, err := time.Parse(time.RFC3339, *e.Airstamp); err == nil {
			stamps[[2]int{*e.Season, *e.Number}] = stamp.UTC()
		}
	}
	refined := episodes
	refined.Episodes = make([]Episode, len(episodes.Episodes))
	for i, e := range episodes.Episodes {
		refined.Episodes[i] = e
		stamp, ok := stamps[[2]int{e.Season, e.Episode}]
		if !ok {
			continue
		}
		if e.AirsAt != nil {
			if d := stamp.Sub(*e.AirsAt); d > TVmazeDateTolerance || d < -TVmazeDateTolerance {
				continue
			}
		}
		refined.Episodes[i].AirsAt = &stamp
		refined.Episodes[i].AirTimeKnown = true
	}
	// The broadcaster or streamer that premieres the show, which is what a viewer tunes to.
	switch {
	case show.Network != nil && blankToNil(show.Network.Name) != nil:
		refined.Network = blankToNil(show.Network.Name)
	case show.WebChannel != nil && blankToNil(show.WebChannel.Name) != nil:
		refined.Network = blankToNil(show.WebChannel.Name)
	}
	return refined, nil
}

// NextAirTime is the exact instant of the show's next episode, for the on-air guide (DISC-003).
func (t *TVmaze) NextAirTime(ctx context.Context, ids core.ExternalIDs) (*time.Time, error) {
	show, err := t.lookup(ctx, ids)
	if err != nil || show == nil {
		return nil, err
	}
	var next tvmazeShow
	if err := t.get(ctx, "shows/"+strconv.Itoa(show.ID), map[string]string{"embed": "nextepisode"}, &next); err != nil {
		return nil, err
	}
	if next.Embedded == nil || next.Embedded.NextEpisode == nil || next.Embedded.NextEpisode.Airstamp == nil {
		return nil, nil //nolint:nilnil // nil: not known
	}
	stamp, err := time.Parse(time.RFC3339, *next.Embedded.NextEpisode.Airstamp)
	if err != nil {
		return nil, nil //nolint:nilnil // nil: not known
	}
	stamp = stamp.UTC()
	return &stamp, nil
}

func (t *TVmaze) lookup(ctx context.Context, ids core.ExternalIDs) (*tvmazeShow, error) {
	for _, kv := range [][2]string{{"thetvdb", ids.TVDB}, {"imdb", ids.IMDB}} {
		if kv[1] == "" {
			continue
		}
		var show tvmazeShow
		err := t.get(ctx, "lookup/shows", map[string]string{kv[0]: kv[1]}, &show)
		if provider.IsNotFound(err) {
			continue
		}
		if err != nil {
			return nil, err
		}
		return &show, nil
	}
	return nil, nil //nolint:nilnil // nil: not known
}

func (t *TVmaze) get(ctx context.Context, path string, query map[string]string, v any) error {
	return getJSON(ctx, t.Client, buildURL(cmp.Or(t.BaseURL, TVmazeBaseURL), path, query), [][2]string{{"Accept", "application/json"}}, v)
}

type tvmazeChannel struct {
	Name string `json:"name"`
}

type tvmazeShow struct {
	ID         int            `json:"id"`
	Network    *tvmazeChannel `json:"network"`
	WebChannel *tvmazeChannel `json:"webChannel"`
	Embedded   *struct {
		NextEpisode *tvmazeEpisode `json:"nextepisode"`
	} `json:"_embedded"`
}

type tvmazeEpisode struct {
	Season   *int    `json:"season"`
	Number   *int    `json:"number"`
	Airstamp *string `json:"airstamp"`
}
