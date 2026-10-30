package catalog

import (
	"aaru-go-api/internal/core"
	"cmp"
	"context"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// OnAirChannel is the broadcaster or streamer a show premieres on, which is what a
// viewer tunes to.
type OnAirChannel struct {
	Name    string
	LogoURL *string
}

// OnAirEpisode is the next episode of an on-air show. AirsAt is a UTC day until a
// time is known.
type OnAirEpisode struct {
	Season       int
	Number       int
	Name         *string
	AirsAt       time.Time
	AirTimeKnown bool
}

// WatchProvider is one streaming service (CAT-014). Data from JustWatch through
// TMDB, which must be credited.
type WatchProvider struct {
	Name    string
	LogoURL *string
}

// WatchProviders is where a title streams in one region: the services, and TMDB's
// page listing them all.
type WatchProviders struct {
	Link      *string
	Streaming []WatchProvider
}

// OnAirShow is one show airing this week (DISC-003), as the provider lists it: the
// same for every user.
type OnAirShow struct {
	Hit     Hit
	Channel *OnAirChannel
	Next    OnAirEpisode
	// Providers are by ISO 3166-1 region code, every region at once, so one cache
	// serves all of them.
	Providers map[string]WatchProviders
}

// OnAirLister lists the shows airing this week, with their next episode and where
// they stream.
type OnAirLister interface {
	OnAir(ctx context.Context, now time.Time) ([]OnAirShow, error)
}

// NextEpisodeTimer is an exact air time for a show's next episode (TVmaze, CAT-011).
type NextEpisodeTimer interface {
	NextAirTime(ctx context.Context, ids core.ExternalIDs) (*time.Time, error)
}

// OnAirEntry is one show of the guide as one caller sees it: marked against their
// library, for their region.
type OnAirEntry struct {
	Item      DiscoverItem
	Next      OnAirEpisode
	StreamsOn []WatchProvider
	WatchLink *string
}

// OnAirGroup is one channel's shows.
type OnAirGroup struct {
	Channel OnAirChannel
	Shows   []OnAirEntry
}

// OnAirGuide is the week's airings by channel.
type OnAirGuide struct {
	Channels  []OnAirGroup
	UpdatedAt *time.Time
}

// Guide limits.
const (
	// OtherChannel is the name used for shows with no known channel. Always the last group.
	OtherChannel = "Other"
	// StreamsOnLimit: "Streams on" lists at most this many services.
	StreamsOnLimit = 3
)

// OnAir is the shows airing this week, one group per channel (DISC-003). An empty
// guide when the provider is down and nothing is cached. region is an upper-case
// ISO 3166-1 code, or "".
func (s *DiscoverService) OnAir(ctx context.Context, userID uuid.UUID, region string) (OnAirGuide, error) {
	if s.onAirSource == nil {
		return OnAirGuide{Channels: []OnAirGroup{}}, nil
	}
	now := s.Now()
	timing := s.nextEpisodeTiming
	fetched := s.onAirCache.shows(ctx, now,
		func(ctx context.Context) ([]OnAirShow, error) { return s.onAirSource.OnAir(ctx, now) },
		func(ctx context.Context, shows []OnAirShow) []OnAirShow { return RefineOnAir(ctx, shows, timing) })
	if fetched == nil {
		return OnAirGuide{Channels: []OnAirGroup{}}, nil
	}
	hits := make([]Hit, len(fetched.shows))
	for i, show := range fetched.shows {
		hits[i] = show.Hit
	}
	marked, err := s.Mark(ctx, hits, userID)
	if err != nil {
		return OnAirGuide{}, err
	}
	entries := make([]channelEntry, 0, len(fetched.shows))
	for i, show := range fetched.shows {
		var local *WatchProviders
		if region != "" {
			if p, ok := show.Providers[region]; ok {
				local = &p
			}
		}
		entry := OnAirEntry{Item: marked[i], Next: show.Next}
		if local != nil {
			entry.StreamsOn = StreamsOn(local.Streaming, show.Channel)
			entry.WatchLink = local.Link
		} else {
			entry.StreamsOn = StreamsOn(nil, show.Channel)
		}
		entries = append(entries, channelEntry{show.Channel, entry})
	}
	at := fetched.fetchedAt
	return OnAirGuide{Channels: GroupOnAir(entries), UpdatedAt: &at}, nil
}

type channelEntry struct {
	channel *OnAirChannel
	entry   OnAirEntry
}

// GroupOnAir puts channels with the most shows first, then by name, "Other" last;
// shows by next air time.
func GroupOnAir(entries []channelEntry) []OnAirGroup {
	groups := map[string]*OnAirGroup{}
	var order []string
	for _, e := range entries {
		channel := OnAirChannel{Name: OtherChannel}
		if e.channel != nil {
			channel = *e.channel
		}
		g, ok := groups[channel.Name]
		if !ok {
			g = &OnAirGroup{Channel: channel}
			groups[channel.Name] = g
			order = append(order, channel.Name)
		}
		g.Shows = append(g.Shows, e.entry)
	}
	out := make([]OnAirGroup, 0, len(groups))
	for _, name := range order {
		g := *groups[name]
		slices.SortStableFunc(g.Shows, func(a, b OnAirEntry) int {
			return cmp.Or(a.Next.AirsAt.Compare(b.Next.AirsAt), strings.Compare(a.Item.Hit.Title, b.Item.Hit.Title))
		})
		out = append(out, g)
	}
	slices.SortStableFunc(out, func(a, b OnAirGroup) int {
		aOther, bOther := a.Channel.Name == OtherChannel, b.Channel.Name == OtherChannel
		if aOther != bOther {
			if bOther {
				return -1
			}
			return 1
		}
		if len(a.Shows) != len(b.Shows) {
			return len(b.Shows) - len(a.Shows)
		}
		return strings.Compare(strings.ToLower(a.Channel.Name), strings.ToLower(b.Channel.Name))
	})
	return out
}

// StreamsOn is the services a show also streams on, without the channel itself
// ("Netflix" on Netflix) or the resellers JustWatch lists beside the service
// ("… Amazon Channel", "… with Ads").
func StreamsOn(providers []WatchProvider, channel *OnAirChannel) []WatchProvider {
	resellers := []string{"amazon channel", "apple tv channel", "roku premium channel", "with ads"}
	own := ""
	if channel != nil {
		own = strings.ToLower(channel.Name)
	}
	seen := map[string]bool{}
	out := []WatchProvider{}
	for _, p := range providers {
		name := strings.ToLower(p.Name)
		if channel != nil && (strings.HasPrefix(name, own) || strings.HasPrefix(own, name)) {
			continue
		}
		if slices.ContainsFunc(resellers, func(r string) bool { return strings.Contains(name, r) }) {
			continue
		}
		if seen[name] {
			continue
		}
		seen[name] = true
		out = append(out, p)
		if len(out) == StreamsOnLimit {
			break
		}
	}
	return out
}

// RefineOnAir puts exact times on the next episodes, one show at a time through the
// provider's pacer. A time is kept only within TVmazeDateTolerance of the listed
// day, as for the calendar, since the two catalogs can number a season differently.
func RefineOnAir(ctx context.Context, shows []OnAirShow, timing NextEpisodeTimer) []OnAirShow {
	if timing == nil {
		return shows
	}
	refined := slices.Clone(shows)
	for i, show := range shows {
		if ctx.Err() != nil {
			break
		}
		stamp, err := timing.NextAirTime(ctx, show.Hit.IDs)
		if err != nil || stamp == nil {
			continue
		}
		if d := stamp.Sub(show.Next.AirsAt); d > TVmazeDateTolerance || d < -TVmazeDateTolerance {
			continue
		}
		refined[i].Next.AirsAt = *stamp
		refined[i].Next.AirTimeKnown = true
	}
	return refined
}

// onAirFetched is the guide as fetched, shared by every user.
type onAirFetched struct {
	shows     []OnAirShow
	fetchedAt time.Time
}

// onAirCache serves a stale guide while a fresh one is fetched; exact times arrive
// in a second pass after the guide is first published, so no viewer waits on
// TVmaze's pacer.
type onAirCache struct {
	mu       sync.Mutex
	fetched  *onAirFetched
	failedAt *time.Time
	inFlight chan struct{}
	result   *onAirFetched
	log      *slog.Logger
}

// onAirTTL is the guide's freshness window.
const onAirTTL = DiscoverTTL

// shows is the cached guide when fresh. A stale one is returned at once while a
// refetch runs; with none, the caller waits on the fetch (the refine pass never).
// Nil when there is nothing.
func (c *onAirCache) shows(
	ctx context.Context, now time.Time,
	fetch func(context.Context) ([]OnAirShow, error),
	refine func(context.Context, []OnAirShow) []OnAirShow,
) *onAirFetched {
	c.mu.Lock()
	if c.fetched != nil && now.Sub(c.fetched.fetchedAt) < onAirTTL {
		defer c.mu.Unlock()
		return c.fetched
	}
	if c.failedAt != nil && now.Sub(*c.failedAt) < DiscoverRetryAfter {
		defer c.mu.Unlock()
		return c.fetched
	}
	done := c.inFlight
	if done == nil {
		done = c.start(context.WithoutCancel(ctx), now, fetch, refine)
	}
	if c.fetched != nil {
		defer c.mu.Unlock()
		return c.fetched
	}
	c.mu.Unlock()
	select {
	case <-done:
	case <-ctx.Done():
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.result
}

// start runs the fetch detached; the caller holds mu.
func (c *onAirCache) start(
	ctx context.Context, now time.Time,
	fetch func(context.Context) ([]OnAirShow, error),
	refine func(context.Context, []OnAirShow) []OnAirShow,
) chan struct{} {
	done := make(chan struct{})
	c.inFlight = done
	c.result = nil
	go func() {
		shows, err := fetch(ctx)
		c.mu.Lock()
		c.inFlight = nil
		if err != nil {
			c.failedAt = &now
			c.mu.Unlock()
			close(done)
			log := c.log
			if log == nil {
				log = slog.Default()
			}
			log.Warn("On-air guide failed", "error", err.Error())
			return
		}
		fresh := &onAirFetched{shows: shows, fetchedAt: now}
		c.failedAt = nil
		c.fetched = fresh
		c.result = fresh
		c.mu.Unlock()
		close(done)
		refined := refine(ctx, shows)
		c.mu.Lock()
		defer c.mu.Unlock()
		// Exact times replace the dates only if no newer guide landed meanwhile.
		if c.fetched != nil && c.fetched.fetchedAt.Equal(now) {
			c.fetched = &onAirFetched{shows: refined, fetchedAt: now}
		}
	}()
	return done
}
