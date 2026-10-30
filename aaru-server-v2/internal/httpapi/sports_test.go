package httpapi

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/sports"
	"context"
	"net/http"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeSports is a sports provider that records what it was asked. Test-only.
type fakeSports struct {
	mu         sync.Mutex
	calls      []string
	failing    bool
	latency    time.Duration
	entities   map[string]sports.Entity
	searchHits []sports.Entity
	schedules  map[string][]sports.Event
	days       map[string][]sports.Event
	events     map[string]sports.Event
	liveEvents []sports.Event
	channels   map[string][]sports.Broadcast
}

func (f *fakeSports) asked() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.calls)
}

func (f *fakeSports) fail(v bool) { f.mu.Lock(); f.failing = v; f.mu.Unlock() }

func (f *fakeSports) delay(d time.Duration) { f.mu.Lock(); f.latency = d; f.mu.Unlock() }

func (f *fakeSports) record(call string) error {
	f.mu.Lock()
	f.calls = append(f.calls, call)
	fails, wait := f.failing, f.latency
	f.mu.Unlock()
	if wait > 0 {
		time.Sleep(wait)
	}
	if fails {
		return provider.NewError("thesportsdb", provider.KindUnavailable)
	}
	return nil
}

func (f *fakeSports) Search(_ context.Context, kind sports.EntityKind, query string) ([]sports.Entity, error) {
	if err := f.record("search:" + string(kind) + ":" + query); err != nil {
		return nil, err
	}
	out := []sports.Entity{}
	for _, e := range f.searchHits {
		if e.Kind == kind {
			out = append(out, e)
		}
	}
	return out, nil
}

func (f *fakeSports) Lookup(_ context.Context, kind sports.EntityKind, id string) (*sports.Entity, error) {
	if err := f.record("lookup:" + string(kind) + ":" + id); err != nil {
		return nil, err
	}
	if e, ok := f.entities[string(kind)+":"+id]; ok {
		return &e, nil
	}
	return nil, nil
}

func (f *fakeSports) Schedule(_ context.Context, direction sports.ScheduleDirection, kind sports.EntityKind, id string) ([]sports.Event, error) {
	key := string(direction) + ":" + string(kind) + ":" + id
	if err := f.record("schedule:" + key); err != nil {
		return nil, err
	}
	return f.schedules[key], nil
}

func (f *fakeSports) Events(_ context.Context, day, leagueID string) ([]sports.Event, error) {
	if err := f.record("day:" + leagueID + ":" + day); err != nil {
		return nil, err
	}
	return f.days[leagueID+":"+day], nil
}

func (f *fakeSports) Event(_ context.Context, id string) (*sports.Event, error) {
	if err := f.record("event:" + id); err != nil {
		return nil, err
	}
	if e, ok := f.events[id]; ok {
		return &e, nil
	}
	return nil, nil
}

func (f *fakeSports) Live(context.Context) ([]sports.Event, error) {
	if err := f.record("live"); err != nil {
		return nil, err
	}
	return f.liveEvents, nil
}

func (f *fakeSports) Broadcasts(_ context.Context, eventID string) ([]sports.Broadcast, error) {
	if err := f.record("tv:" + eventID); err != nil {
		return nil, err
	}
	return f.channels[eventID], nil
}

func sp(s string) *string { return &s }

var (
	arsenal = sports.Entity{
		Kind: sports.KindTeam, ID: "133604", Name: "Arsenal", Sport: "Soccer",
		BadgeURL: sp("https://r2.thesportsdb.com/arsenal.png"), Country: sp("England"), LeagueID: sp("4328"),
	}
	pereira = sports.Entity{
		Kind: sports.KindPlayer, ID: "34215679", Name: "Alex Pereira", Sport: "Fighting", TeamID: sp("135481"),
		TeamName: sp("UFC Heavyweight"),
	}
	heavyweight = sports.Entity{Kind: sports.KindTeam, ID: "135481", Name: "UFC Heavyweight", Sport: "Fighting", LeagueID: sp("4443")}
	nba         = sports.Entity{Kind: sports.KindLeague, ID: "4387", Name: "NBA", Sport: "Basketball", LeagueID: sp("4387")}
)

func sportsProvider() *fakeSports {
	f := &fakeSports{
		entities: map[string]sports.Entity{}, schedules: map[string][]sports.Event{}, days: map[string][]sports.Event{},
		events: map[string]sports.Event{}, channels: map[string][]sports.Broadcast{},
	}
	for _, e := range []sports.Entity{arsenal, pereira, heavyweight, nba} {
		f.entities[string(e.Kind)+":"+e.ID] = e
	}
	return f
}

func withSports(fake *fakeSports) func(*Deps) {
	return func(d *Deps) {
		d.Sports = sports.NewService(&sports.Store{Q: sqlc.New(d.Pool), Pool: d.Pool}, fake)
	}
}

func instant(s string) *time.Time {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		panic(err)
	}
	return &t
}

func sampleMatch(id, home, away, league, at string, status sports.EventStatus, homeScore, awayScore *int) sports.Event {
	if league == "" {
		league = "4328"
	}
	if status == "" {
		status = sports.StatusScheduled
	}
	return sports.Event{
		ID: id, Sport: "Soccer", Name: "Team " + home + " vs Team " + away, LeagueID: sp(league), League: sp("League " + league),
		Home:     &sports.Side{ID: sp(home), Name: "Team " + home, Score: homeScore},
		Away:     &sports.Side{ID: sp(away), Name: "Team " + away, Score: awayScore},
		StartsAt: instant(at), Day: at[:10], Status: status,
	}
}

func ip(i int) *int { return &i }

func TestSportsOffWithoutAProvider(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	settings := decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/sport-settings", bearer, nil))
	assert.Equal(t, false, settings["available"])
	picks := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/suggested", bearer, nil))
	assert.Equal(t, true, picks["unavailable"])
	assert.Len(t, picks["items"], len(sports.Suggested()))
	favorites := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/favorites", bearer, nil))
	assert.Equal(t, true, favorites["unavailable"])
	search := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/search?q=arsenal", bearer, nil))
	assert.Equal(t, true, search["unavailable"])
	schedule := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/schedule?date=2026-10-24", bearer, nil))
	assert.Equal(t, true, schedule["unavailable"])
	follow := h.do(http.MethodPut, "/v1/me/sport-follows/team/133604", bearer, nil)
	assert.Equal(t, http.StatusServiceUnavailable, follow.Code)
	assert.Equal(t, "sports_unavailable", decode[map[string]any](t, follow)["code"])
	_, err := h.server.Sports.PublicEvent(context.Background(), "42")
	assert.ErrorIs(t, err, sports.ErrSportsOff)
}

func TestFollowingKeepsASnapshot(t *testing.T) {
	fake := sportsProvider()
	h := newHarness(t, withSports(fake))
	_, bearer := h.signIn()
	team := decode[map[string]any](t, h.do(http.MethodPut, "/v1/me/sport-follows/team/133604", bearer, nil))
	assert.Equal(t, "Arsenal", team["name"])
	assert.Equal(t, true, team["following"])
	assert.Equal(t, "4328", team["leagueId"])

	fighter := decode[map[string]any](t, h.do(http.MethodPut, "/v1/me/sport-follows/player/34215679", bearer, nil))
	assert.Equal(t, "135481", fighter["teamId"])
	assert.Equal(t, "4443", fighter["leagueId"], "the division's league: UFC")

	assert.Equal(t, http.StatusOK, h.do(http.MethodPut, "/v1/me/sport-follows/team/133604", bearer, nil).Code, "following twice is fine")
	unknown := h.do(http.MethodPut, "/v1/me/sport-follows/team/999", bearer, nil)
	assert.Equal(t, http.StatusNotFound, unknown.Code)
	assert.Equal(t, "The sports provider does not know that one.", decode[map[string]any](t, unknown)["message"])
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodPut, "/v1/me/sport-follows/team/abc", bearer, nil).Code)

	list := decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/sport-follows", bearer, nil))["items"].([]any)
	var ids []string
	for _, item := range list {
		ids = append(ids, item.(map[string]any)["id"].(string))
	}
	assert.Equal(t, []string{"133604", "34215679"}, ids)

	fake.fail(true)
	offline := decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/sport-follows", bearer, nil))["items"].([]any)
	assert.Equal(t, "https://r2.thesportsdb.com/arsenal.png", offline[0].(map[string]any)["badgeUrl"], "the snapshot renders while the provider is down")
	fake.fail(false)

	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/me/sport-follows/team/133604", bearer, nil).Code)
	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/me/sport-follows/team/133604", bearer, nil).Code)
	assert.Len(t, decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/sport-follows", bearer, nil))["items"], 1)
}

func TestAtTheLimitANewFollowIsRefused(t *testing.T) {
	h := newHarness(t, withSports(sportsProvider()))
	userID, _ := h.signIn()
	store := h.server.Sports.Store
	ctx := context.Background()
	first, err := store.Follow(ctx, arsenal, userID, 1, time.Now())
	require.NoError(t, err)
	second, err := store.Follow(ctx, nba, userID, 1, time.Now())
	require.NoError(t, err)
	refresh, err := store.Follow(ctx, arsenal, userID, 1, time.Now())
	require.NoError(t, err)
	assert.True(t, first && !second && refresh)
}

func TestSportFavoritesLiveNextAndLast(t *testing.T) {
	fake := sportsProvider()
	now := *instant("2026-10-24T15:00:00Z")
	fake.schedules["next:team:133604"] = []sports.Event{
		sampleMatch("live1", "133604", "133615", "", "2026-10-24T14:00:00Z", "", nil, nil),
		sampleMatch("n2", "133601", "133604", "", "2026-11-01T15:00:00Z", "", nil, nil),
	}
	fake.schedules["previous:team:133604"] = []sports.Event{
		sampleMatch("p1", "133604", "1", "", "2026-10-04T15:00:00Z", "", ip(3), ip(0)),
		sampleMatch("p2", "2", "133604", "", "2026-10-18T15:00:00Z", "", ip(1), ip(1)),
	}
	line := sampleMatch("live1", "133604", "133615", "", "2026-10-24T14:00:00Z", sports.StatusLive, ip(1), ip(0))
	line.Progress = sp("67")
	fake.liveEvents = []sports.Event{line}
	card := now.Add(time.Hour)
	fake.schedules["next:league:4443"] = []sports.Event{{
		ID: "ufc333", Sport: "Fighting", Name: "UFC 333", LeagueID: sp("4443"), League: sp("UFC"), StartsAt: &card,
		Day: "2026-10-24", Status: sports.StatusScheduled,
	}}
	h := newHarness(t, withSports(fake))
	userID, _ := h.signIn()
	service := h.server.Sports
	service.Now = func() time.Time { return now }
	ctx := context.Background()
	_, err := service.Follow(ctx, sports.KindTeam, "133604", userID)
	require.NoError(t, err)
	_, err = service.Follow(ctx, sports.KindPlayer, "34215679", userID)
	require.NoError(t, err)
	favorites, err := service.Favorites(ctx, userID)
	require.NoError(t, err)
	assert.False(t, favorites.Unavailable)
	byKind := map[sports.EntityKind]sports.Favorite{}
	for _, item := range favorites.Items {
		byKind[item.Entity.Kind] = item
	}
	team := byKind[sports.KindTeam]
	require.Len(t, team.Live, 1)
	assert.Equal(t, "live1", team.Live[0].ID)
	assert.Equal(t, "67", *team.Live[0].Progress)
	assert.Equal(t, 1, *team.Live[0].Home.Score)
	assert.Equal(t, "n2", team.Next.ID, "the game being played is live, not next")
	assert.Equal(t, "p2", team.Last.ID, "the most recent result")
	assert.False(t, team.Pending)
	fighter := byKind[sports.KindPlayer]
	assert.Equal(t, "ufc333", fighter.Next.ID, "a fighter's fixtures are the promotion's cards")
	assert.Contains(t, fake.asked(), "schedule:next:league:4443")

	calls := len(fake.asked())
	_, err = service.Favorites(ctx, userID)
	require.NoError(t, err)
	assert.Len(t, fake.asked(), calls, "everything is cached")
}

func TestSlowSportFavoritesArePendingThenReady(t *testing.T) {
	fake := sportsProvider()
	fake.schedules["next:team:133604"] = []sports.Event{sampleMatch("n1", "133604", "2", "", "2099-01-01T15:00:00Z", "", nil, nil)}
	h := newHarness(t, withSports(fake))
	userID, _ := h.signIn()
	service := h.server.Sports
	service.Patience = 100 * time.Millisecond
	ctx := context.Background()
	_, err := service.Follow(ctx, sports.KindTeam, "133604", userID)
	require.NoError(t, err)
	fake.delay(400 * time.Millisecond)
	first, err := service.Favorites(ctx, userID)
	require.NoError(t, err)
	assert.True(t, first.Items[0].Pending)
	assert.Nil(t, first.Items[0].Next)
	time.Sleep(700 * time.Millisecond)
	second, err := service.Favorites(ctx, userID)
	require.NoError(t, err)
	assert.False(t, second.Items[0].Pending)
	assert.Equal(t, "n1", second.Items[0].Next.ID)
}

func TestSportScheduleOneLocalDay(t *testing.T) {
	fake := sportsProvider()
	// Lisbon is UTC+1 on 2026-10-24 (summer time ends the next day): the local day runs from
	// 23:00Z on the 23rd to 23:00Z on the 24th.
	fake.days["4328:2026-10-23"] = []sports.Event{
		sampleMatch("late", "133604", "5", "", "2026-10-23T23:30:00Z", "", nil, nil),
		sampleMatch("before", "6", "7", "", "2026-10-23T20:00:00Z", "", nil, nil),
	}
	fake.days["4328:2026-10-24"] = []sports.Event{
		sampleMatch("noon", "8", "9", "", "2026-10-24T12:00:00Z", "", nil, nil),
		sampleMatch("after", "8", "9", "", "2026-10-24T23:30:00Z", "", nil, nil),
	}
	fake.days["4387:2026-10-24"] = []sports.Event{{
		ID: "nba1", Sport: "Basketball", Name: "Lakers vs Celtics", LeagueID: sp("4387"), League: sp("NBA"),
		StartsAt: instant("2026-10-24T01:00:00Z"), Day: "2026-10-24", Status: sports.StatusScheduled,
	}}
	fake.schedules["next:team:133604"] = []sports.Event{sampleMatch("cup", "133604", "3", "4480", "2026-10-24T19:00:00Z", "", nil, nil)}
	h := newHarness(t, withSports(fake))
	_, bearer := h.signIn()
	h.do(http.MethodPut, "/v1/me/sport-follows/team/133604", bearer, nil)
	h.do(http.MethodPut, "/v1/me/sport-follows/league/4387", bearer, nil)
	day := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/schedule?date=2026-10-24&tz=Europe/Lisbon", bearer, nil))
	assert.Equal(t, false, day["pending"])
	groups := day["groups"].([]any)
	var leagues []string
	for _, g := range groups {
		leagues = append(leagues, g.(map[string]any)["leagueId"].(string))
	}
	assert.Equal(t, []string{"4328", "4480", "4387"}, leagues, "leagues with a followed team first, then by name")
	premier := groups[0].(map[string]any)["events"].([]any)
	var ids []string
	for _, e := range premier {
		ids = append(ids, e.(map[string]any)["id"].(string))
	}
	assert.Equal(t, []string{"late", "noon"}, ids, "only the local day, in order")
	assert.Equal(t, true, premier[0].(map[string]any)["isFavorite"])
	assert.Contains(t, fake.asked(), "day:4328:2026-10-23")
	assert.Contains(t, fake.asked(), "day:4328:2026-10-24")

	assert.Equal(t, http.StatusUnprocessableEntity, h.do(http.MethodGet, "/v1/sports/schedule?date=2026-02-30", bearer, nil).Code)
	assert.Equal(t, http.StatusUnprocessableEntity, h.do(http.MethodGet, "/v1/sports/schedule?date=2026-10-24&tz=Mars/Base", bearer, nil).Code)
}

func TestSportEventWhereToWatch(t *testing.T) {
	fake := sportsProvider()
	fake.events["42"] = sampleMatch("42", "133604", "133615", "", "2026-10-18T14:00:00Z", "", ip(2), ip(0))
	fake.channels["42"] = []sports.Broadcast{
		{Channel: "Sport TV1", Country: sp("Portugal")},
		{Channel: "Sky Sports", Country: sp("United Kingdom")},
		{Channel: "Peacock", Country: sp("USA")},
	}
	h := newHarness(t, withSports(fake))
	_, bearer := h.signIn()
	detail := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/events/42", bearer, nil))
	assert.Equal(t, []any{}, detail["inYourCountry"], "no country chosen yet")
	assert.Len(t, detail["elsewhere"], 3)
	assert.Equal(t, "finished", detail["event"].(map[string]any)["status"], "a past event with a score is finished")

	saved := decode[map[string]any](t, h.do(http.MethodPut, "/v1/me/sport-settings", bearer, map[string]any{"watchCountryCode": "us"}))
	assert.Equal(t, "US", saved["watchCountryCode"])
	assert.Equal(t, true, saved["available"])
	detail = decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/events/42", bearer, nil))
	channels := func(key string) []string {
		var out []string
		for _, b := range detail[key].([]any) {
			out = append(out, b.(map[string]any)["channel"].(string))
		}
		return out
	}
	assert.Equal(t, []string{"Peacock"}, channels("inYourCountry"), "USA matches US")
	assert.Equal(t, []string{"Sport TV1", "Sky Sports"}, channels("elsewhere"))

	assert.Equal(t, http.StatusUnprocessableEntity, h.do(http.MethodPut, "/v1/me/sport-settings", bearer, map[string]any{"watchCountryCode": "USA"}).Code)
	cleared := decode[map[string]any](t, h.do(http.MethodPut, "/v1/me/sport-settings", bearer, map[string]any{}))
	assert.NotContains(t, cleared, "watchCountryCode")
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/sports/events/7", bearer, nil).Code)
}

func TestSportSearchAllThreeKindsInOrder(t *testing.T) {
	fake := sportsProvider()
	fake.searchHits = []sports.Entity{arsenal, {Kind: sports.KindLeague, ID: "1", Name: "Arsenal League", Sport: "Soccer"}}
	h := newHarness(t, withSports(fake))
	_, bearer := h.signIn()
	h.do(http.MethodPut, "/v1/me/sport-follows/team/133604", bearer, nil)
	found := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/search?q=Arsenal", bearer, nil))["items"].([]any)
	require.Len(t, found, 2)
	assert.Equal(t, "league", found[0].(map[string]any)["kind"])
	assert.Equal(t, "team", found[1].(map[string]any)["kind"])
	assert.Equal(t, true, found[1].(map[string]any)["following"])
	assert.Equal(t, false, found[0].(map[string]any)["following"])
	assert.Equal(t, http.StatusUnprocessableEntity, h.do(http.MethodGet, "/v1/sports/search?q=a", bearer, nil).Code)
	teamsOnly := decode[map[string]any](t, h.do(http.MethodGet, "/v1/sports/search?q=Arsenal&kind=team", bearer, nil))["items"].([]any)
	assert.Len(t, teamsOnly, 1)
}

func TestAPublicSportEventNeedsNoUserAndSharesTheCache(t *testing.T) {
	fake := sportsProvider()
	fake.events["42"] = sampleMatch("42", "133604", "133615", "", "2026-10-18T14:00:00Z", "", ip(2), ip(1))
	h := newHarness(t, withSports(fake))
	ctx := context.Background()
	event, err := h.server.Sports.PublicEvent(ctx, "42")
	require.NoError(t, err)
	require.NotNil(t, event)
	assert.Equal(t, 2, *event.Home.Score)
	assert.Equal(t, 1, *event.Away.Score)
	assert.Equal(t, sports.StatusFinished, event.Status, "a past event with a score is finished")
	_, err = h.server.Sports.PublicEvent(ctx, "42")
	require.NoError(t, err)
	count := 0
	for _, call := range fake.asked() {
		if call == "event:42" {
			count++
		}
	}
	assert.Equal(t, 1, count, "the second open is served from the cache")
	missing, err := h.server.Sports.PublicEvent(ctx, "999")
	require.NoError(t, err)
	assert.Nil(t, missing)
}
