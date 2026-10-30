package catalog

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The on-air guide (DISC-003) and its "streams on" (CAT-014) against canned JSON.

func listedDay(day string) time.Time { return *ParseDay(&day) }

func instant(stamp string) time.Time {
	t, err := time.Parse(time.RFC3339, stamp)
	if err != nil {
		panic(err)
	}
	return t.UTC()
}

func onAirShow(title, tmdb string, channel *string, day string, providers map[string][]string) OnAirShow {
	show := OnAirShow{
		Hit:  discoverHit(title, core.MediaShow, tmdb, true),
		Next: OnAirEpisode{Season: 1, Number: 2, AirsAt: listedDay(day)},
	}
	if channel != nil {
		show.Channel = &OnAirChannel{Name: *channel}
	}
	if providers != nil {
		show.Providers = map[string]WatchProviders{}
		for region, names := range providers {
			var services []WatchProvider
			for _, n := range names {
				services = append(services, WatchProvider{Name: n})
			}
			show.Providers[region] = WatchProviders{Link: ptr("https://www.themoviedb.org/tv/" + tmdb + "/watch"), Streaming: services}
		}
	}
	return show
}

func TestTMDBOnAir(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		var body string
		switch urlPath(req.URL) {
		case "/3/tv/on_the_air":
			body = `{"total_pages":1,"results":[
			  {"id":101,"name":"Drama","poster_path":"/d.jpg","genre_ids":[18],"original_language":"en"},
			  {"id":102,"name":"Anime","poster_path":"/a.jpg","genre_ids":[16],"original_language":"ja"},
			  {"id":103,"name":"Later","poster_path":"/l.jpg","genre_ids":[18],"original_language":"en"},
			  {"id":104,"name":"No cover","genre_ids":[18],"original_language":"en"}]}`
		case "/3/tv/101":
			assert.Equal(t, "external_ids,watch/providers", urlQuery(req.URL).Get("append_to_response"))
			body = `{"networks":[{"name":"HBO","logo_path":"/hbo.png"},{"name":"Other"}],
			 "next_episode_to_air":{"air_date":"2026-10-22","season_number":2,"episode_number":5,"name":"Five"},
			 "external_ids":{"imdb_id":"tt1","tvdb_id":81189},
			 "watch/providers":{"results":{
			   "US":{"link":"https://www.themoviedb.org/tv/101/watch?locale=US","flatrate":[
			     {"provider_name":"Max","logo_path":"/max.png","display_priority":2},
			     {"provider_name":"Hulu","logo_path":"/hulu.png","display_priority":1}]},
			   "PT":{"link":"https://x","flatrate":[]}}}}`
		case "/3/tv/103":
			body = `{"next_episode_to_air":{"air_date":"2026-12-01","season_number":1,"episode_number":1}}`
		default:
			return provider.Response{Status: 404}
		}
		return provider.Response{Status: 200, Body: []byte(body)}
	})
	shows, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).OnAir(context.Background(), discoverNow)
	require.NoError(t, err)
	require.Len(t, shows, 1, "anime, a far-off episode and a poster-less show are left out")
	drama := shows[0]
	assert.Equal(t, "Drama", drama.Hit.Title)
	assert.Equal(t, &OnAirChannel{Name: "HBO", LogoURL: ptr("https://image.tmdb.org/t/p/w92/hbo.png")}, drama.Channel)
	assert.Equal(t, "HBO", *drama.Hit.Network)
	assert.Equal(t, OnAirEpisode{Season: 2, Number: 5, Name: ptr("Five"), AirsAt: listedDay("2026-10-22")}, drama.Next)
	assert.Equal(t, "81189", drama.Hit.IDs.TVDB)
	assert.Equal(t, "tt1", drama.Hit.IDs.IMDB)
	require.Len(t, drama.Providers, 1, "a region with no streaming services is dropped")
	us := drama.Providers["US"]
	assert.Equal(t, []string{"Hulu", "Max"}, []string{us.Streaming[0].Name, us.Streaming[1].Name}, "by JustWatch's display priority")
}

func TestGroupOnAir(t *testing.T) {
	var entries []channelEntry
	for _, s := range []OnAirShow{
		onAirShow("B", "1", ptr("Netflix"), "2026-10-23", nil),
		onAirShow("Lost", "2", nil, "2026-10-21", nil),
		onAirShow("A", "3", ptr("Netflix"), "2026-10-21", nil),
		onAirShow("C", "4", ptr("BBC One"), "2026-10-22", nil),
		onAirShow("D", "5", ptr("ABC"), "2026-10-22", nil),
	} {
		entries = append(entries, channelEntry{channel: s.Channel, entry: OnAirEntry{Item: DiscoverItem{Hit: s.Hit}, Next: s.Next}})
	}
	groups := GroupOnAir(entries)
	var names []string
	for _, g := range groups {
		names = append(names, g.Channel.Name)
	}
	assert.Equal(t, []string{"Netflix", "ABC", "BBC One", "Other"}, names)
	assert.Equal(t, []string{"A", "B"}, []string{groups[0].Shows[0].Item.Hit.Title, groups[0].Shows[1].Item.Hit.Title})
}

func TestStreamsOnLeavesOutTheChannelAndResellers(t *testing.T) {
	var providers []WatchProvider
	for _, n := range []string{"Netflix", "Netflix Standard with Ads", "Hulu", "Max Amazon Channel", "Hulu", "Max", "Peacock", "Paramount Plus"} {
		providers = append(providers, WatchProvider{Name: n})
	}
	var names []string
	for _, p := range StreamsOn(providers, &OnAirChannel{Name: "Netflix"}) {
		names = append(names, p.Name)
	}
	assert.Equal(t, []string{"Hulu", "Max", "Peacock"}, names)
}

func TestTVmazeNextAirTime(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		switch {
		case urlPath(req.URL) == "/lookup/shows" && urlQuery(req.URL).Encode() == "thetvdb=81189":
			return provider.Response{Status: 200, Body: []byte(`{"id":169,"network":{"name":"AMC"}}`)}
		case urlPath(req.URL) == "/shows/169":
			assert.Equal(t, "embed=nextepisode", urlQuery(req.URL).Encode())
			return provider.Response{Status: 200, Body: []byte(`{"id":169,"network":{"name":"AMC"},
			 "_embedded":{"nextepisode":{"season":2,"number":5,"airstamp":"2026-10-23T01:00:00+00:00"}}}`)}
		}
		return provider.Response{Status: 404}
	})
	times := &TVmaze{Client: testClient(stub, "tvmaze")}
	stamp, err := times.NextAirTime(context.Background(), core.ExternalIDs{TVDB: "81189"})
	require.NoError(t, err)
	assert.Equal(t, instant("2026-10-23T01:00:00Z"), *stamp)
	missing, err := times.NextAirTime(context.Background(), core.ExternalIDs{IMDB: "tt404"})
	require.NoError(t, err)
	assert.Nil(t, missing, "not on TVmaze")
}

// stubTiming is exact times by TMDB id; with a gate, every answer waits until it opens.
type stubTiming struct {
	stamps map[string]time.Time
	gate   chan struct{}
}

func (s stubTiming) NextAirTime(ctx context.Context, ids core.ExternalIDs) (*time.Time, error) {
	if s.gate != nil {
		select {
		case <-s.gate:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	stamp, ok := s.stamps[ids.TMDB]
	if !ok {
		return nil, provider.NewError("tvmaze", provider.KindUnavailable)
	}
	return &stamp, nil
}

func TestRefineOnAirTolerance(t *testing.T) {
	shows := []OnAirShow{
		onAirShow("Close", "1", ptr("HBO"), "2026-10-22", nil),
		onAirShow("Far", "2", ptr("HBO"), "2026-10-22", nil),
		onAirShow("Down", "3", ptr("HBO"), "2026-10-22", nil),
	}
	timing := stubTiming{stamps: map[string]time.Time{"1": instant("2026-10-23T01:00:00Z"), "2": instant("2026-11-05T01:00:00Z")}}
	refined := RefineOnAir(context.Background(), shows, timing)
	assert.Equal(t, []bool{true, false, false}, []bool{refined[0].Next.AirTimeKnown, refined[1].Next.AirTimeKnown, refined[2].Next.AirTimeKnown})
	assert.Equal(t, instant("2026-10-23T01:00:00Z"), refined[0].Next.AirsAt)
	assert.Equal(t, listedDay("2026-10-22"), refined[1].Next.AirsAt)
}

func TestOnAirPublishesDatesBeforeExactTimes(t *testing.T) {
	gate := make(chan struct{})
	timing := stubTiming{stamps: map[string]time.Time{"1": instant("2026-10-22T20:00:00Z")}, gate: gate}
	cache := &onAirCache{}
	var fetches atomic.Int32
	shows := []OnAirShow{onAirShow("Drama", "1", ptr("HBO"), "2026-10-22", nil)}
	read := func() *onAirFetched {
		return cache.shows(context.Background(), discoverNow,
			func(context.Context) ([]OnAirShow, error) { fetches.Add(1); return shows, nil },
			func(ctx context.Context, s []OnAirShow) []OnAirShow { return RefineOnAir(ctx, s, timing) })
	}
	first := read()
	require.NotNil(t, first)
	assert.False(t, first.shows[0].Next.AirTimeKnown)
	close(gate)
	known := false
	for range 200 {
		if f := read(); f != nil && f.shows[0].Next.AirTimeKnown {
			known = true
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	assert.True(t, known)
	assert.Equal(t, int32(1), fetches.Load(), "one fetch for the TTL")
}

func TestOnAirFailureIsAnEmptyGuide(t *testing.T) {
	fake := newFake()
	fake.fail(provider.NewError("tmdb", provider.KindUnavailable))
	service := NewDiscoverService(nil, []any{fake}, nil, nil, nil)
	guide, err := service.OnAir(context.Background(), uuid.New(), "US")
	require.NoError(t, err)
	assert.Empty(t, guide.Channels)
}

func TestOnAirMarksOwnedAndListsTheRegionsServices(t *testing.T) {
	env := newRefreshEnv(t)
	owned := env.title(core.MediaShow, "Owned", core.ExternalIDs{TMDB: "4242"})
	env.track(owned.ID, "wishlist")
	var itemID uuid.UUID
	require.NoError(t, env.pool.QueryRow(env.ctx, `SELECT id FROM library_items WHERE title_id = $1`, owned.ID).Scan(&itemID))
	fake := newFake()
	fake.stubOnAir([]OnAirShow{
		onAirShow("Owned", "4242", ptr("Netflix"), "2026-10-22", map[string][]string{"US": {"Netflix", "Hulu"}}),
		onAirShow("New", "x-1", nil, "2026-10-21", nil),
	})
	service := NewDiscoverService(env.store, []any{fake}, nil, nil, nil)
	service.Now = func() time.Time { return discoverNow }
	guide, err := service.OnAir(env.ctx, env.user, "US")
	require.NoError(t, err)
	require.Len(t, guide.Channels, 2)
	assert.Equal(t, "Netflix", guide.Channels[0].Channel.Name)
	assert.Equal(t, "Other", guide.Channels[1].Channel.Name)
	show := guide.Channels[0].Shows[0]
	assert.Equal(t, itemID, *show.Item.LibraryItemID)
	require.Len(t, show.StreamsOn, 1)
	assert.Equal(t, "Hulu", show.StreamsOn[0].Name)
	assert.NotNil(t, show.WatchLink)
	assert.False(t, show.Next.AirTimeKnown)
	assert.Equal(t, 1, show.Next.Season)
	assert.Empty(t, guide.Channels[1].Shows[0].StreamsOn, "no data for the region")
}
