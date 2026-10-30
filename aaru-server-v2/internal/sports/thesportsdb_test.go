package sports

import (
	"aaru-go-api/internal/provider"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type stub struct {
	mu       sync.Mutex
	requests []*http.Request
	respond  func(*http.Request) string
	server   *httptest.Server
}

func newStub(t *testing.T, respond func(*http.Request) string) *stub {
	t.Helper()
	s := &stub{respond: respond}
	s.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		s.requests = append(s.requests, r)
		f := s.respond
		s.mu.Unlock()
		_, _ = w.Write([]byte(f(r)))
	}))
	t.Cleanup(s.server.Close)
	return s
}

func (s *stub) asked() []*http.Request {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]*http.Request(nil), s.requests...)
}

func adapter(s *stub) *TheSportsDB {
	return &TheSportsDB{
		Client: provider.NewClient("thesportsdb", provider.NewHTTPTransport(), provider.NewPacer(1000, 100)),
		APIKey: "test-key", BaseURL: s.server.URL,
	}
}

func str(s string) *string { return &s }

func TestSearchSendsTheKeyAsAHeaderAndAnUnderscoredSlug(t *testing.T) {
	s := newStub(t, func(r *http.Request) string {
		if strings.Contains(r.URL.Path, "/player/") {
			return `{"search":[{"idPlayer":"34215679","strPlayer":"Alex Pereira","idTeam":"135481",
			  "strTeam":"UFC Heavyweight","strSport":"Fighting","strCutout":"https://r2.thesportsdb.com/p.png"}]}`
		}
		return `{"search":[{"idTeam":133604,"strTeam":"Arsenal","idLeague":"4328","strSport":"Soccer",
		  "strBadge":"https://r2.thesportsdb.com/b.png","strCountry":"England"},{"strTeam":"no id"}]}`
	})
	teams, err := adapter(s).Search(context.Background(), KindTeam, "  Arsenal  FC ")
	require.NoError(t, err)
	request := s.asked()[0]
	assert.Equal(t, "/api/v2/json/search/team/arsenal_fc", request.URL.Path)
	assert.Equal(t, "test-key", request.Header.Get("X-API-KEY"))
	assert.NotContains(t, request.URL.String(), "test-key", "v2 keeps the key out of the URL")
	assert.Equal(t, []Entity{{
		Kind: KindTeam, ID: "133604", Name: "Arsenal", Sport: "Soccer", BadgeURL: str("https://r2.thesportsdb.com/b.png"),
		Country: str("England"), LeagueID: str("4328"),
	}}, teams, "a number id is read as text; a row without an id is skipped")

	fighters, err := adapter(s).Search(context.Background(), KindPlayer, "Alex Pereira")
	require.NoError(t, err)
	require.Len(t, fighters, 1)
	assert.Equal(t, "135481", *fighters[0].TeamID)
	assert.Equal(t, "Fighting", fighters[0].Sport)
	assert.Equal(t, "https://r2.thesportsdb.com/p.png", *fighters[0].BadgeURL)
}

func TestSchedulesReadScoresTimestampsAndCards(t *testing.T) {
	s := newStub(t, func(*http.Request) string {
		return `{"schedule":[
		  {"idEvent":"1","strEvent":"Arsenal vs Everton","strSport":"Soccer","idLeague":"4328",
		   "strLeague":"English Premier League","idHomeTeam":"133604","strHomeTeam":"Arsenal",
		   "idAwayTeam":"133615","strAwayTeam":"Everton","intHomeScore":"2","intAwayScore":"0",
		   "strTimestamp":"2026-10-18T14:00:00","dateEvent":"2026-10-18","strStatus":"Match Finished","intRound":"8"},
		  {"idEvent":"2558809","strEvent":"UFC 333 Volkanovski vs Evloev","strSport":"Fighting","idLeague":"4443",
		   "strLeague":"UFC","idHomeTeam":null,"strHomeTeam":null,"strTimestamp":"2026-10-24T16:00:00+00:00",
		   "dateEvent":"2026-10-24","strStatus":"","strPoster":"https://r2.thesportsdb.com/poster.jpg"}
		]}`
	})
	events, err := adapter(s).Schedule(context.Background(), Previous, KindTeam, "133604")
	require.NoError(t, err)
	assert.Equal(t, "/api/v2/json/schedule/previous/team/133604", s.asked()[0].URL.Path)
	require.Len(t, events, 2)
	match := events[0]
	assert.Equal(t, 2, *match.Home.Score)
	assert.Equal(t, 0, *match.Away.Score)
	assert.Equal(t, StatusFinished, match.Status)
	assert.Equal(t, time.Date(2026, 10, 18, 14, 0, 0, 0, time.UTC), *match.StartsAt)
	assert.Equal(t, "Round 8", *match.Round)
	assert.True(t, match.Involves("133615"))
	card := events[1]
	assert.Nil(t, card.Home)
	assert.Nil(t, card.Away)
	assert.Equal(t, StatusScheduled, card.Status)
	assert.Equal(t, "https://r2.thesportsdb.com/poster.jpg", *card.ImageURL)

	none, err := adapter(s).Schedule(context.Background(), Next, KindPlayer, "1")
	require.NoError(t, err)
	assert.Empty(t, none, "players have no schedule")
}

func TestV1CallsCarryTheKeyInThePath(t *testing.T) {
	s := newStub(t, func(r *http.Request) string {
		if strings.HasSuffix(r.URL.Path, "lookuptv.php") {
			return `{"tvevent":[{"strChannel":"Sky Sports Main Event","strCountry":"United Kingdom",
			  "strLogo":"https://r2.thesportsdb.com/sky.png"},{"strCountry":"Nowhere"}]}`
		}
		return `{"events":null}`
	})
	day, err := adapter(s).Events(context.Background(), "2026-10-24", "4328")
	require.NoError(t, err)
	assert.Empty(t, day, "TheSportsDB says null for an empty day")
	first := s.asked()[0]
	assert.Equal(t, "/api/v1/json/test-key/eventsday.php", first.URL.Path)
	assert.Equal(t, "d=2026-10-24&l=4328", first.URL.RawQuery)
	channels, err := adapter(s).Broadcasts(context.Background(), "42")
	require.NoError(t, err)
	assert.Equal(t, []Broadcast{{
		Channel: "Sky Sports Main Event", Country: str("United Kingdom"), LogoURL: str("https://r2.thesportsdb.com/sky.png"),
	}}, channels)
}

func TestLivescoresBecomeEventsWithTheClock(t *testing.T) {
	body := `{"livescore":[
	  {"idEvent":"9","strSport":"Soccer","idLeague":"4328","strLeague":"English Premier League",
	   "idHomeTeam":"133604","strHomeTeam":"Arsenal","idAwayTeam":"133615","strAwayTeam":"Everton",
	   "intHomeScore":1,"intAwayScore":"1","strStatus":"2H","strProgress":"67","dateEvent":"2026-10-24"},
	  {"idEvent":"10","strHomeTeam":"A","strAwayTeam":"B","strStatus":"","strProgress":"NS",
	   "dateEvent":"2026-10-24"}
	]}`
	s := newStub(t, func(*http.Request) string { return body })
	live, err := adapter(s).Live(context.Background())
	require.NoError(t, err)
	assert.Equal(t, "/api/v2/json/livescore/all", s.asked()[0].URL.Path)
	require.Len(t, live, 2)
	assert.Equal(t, StatusLive, live[0].Status)
	assert.Equal(t, "67", *live[0].Progress)
	assert.Equal(t, 1, *live[0].Home.Score)
	assert.Equal(t, 1, *live[0].Away.Score)
	assert.Equal(t, StatusScheduled, live[1].Status, "a blank status falls back to the clock: NS")

	body = `{"livescore":"No data found"}`
	none, err := adapter(s).Live(context.Background())
	require.NoError(t, err)
	assert.Empty(t, none)
}

func TestStatusesMapToFive(t *testing.T) {
	cases := []struct {
		text, postponed *string
		want            EventStatus
	}{
		{nil, nil, StatusScheduled},
		{str("Not Started"), nil, StatusScheduled},
		{str("FT"), nil, StatusFinished},
		{str("Match Finished"), nil, StatusFinished},
		{str("AET"), nil, StatusFinished},
		{str("PST"), nil, StatusPostponed},
		{str("NS"), str("yes"), StatusPostponed},
		{str("CANC"), nil, StatusCancelled},
		{str("Abandoned"), nil, StatusCancelled},
		{str("HT"), nil, StatusLive},
		{str("Q3"), nil, StatusLive},
	}
	for _, c := range cases {
		assert.Equal(t, c.want, Status(c.text, c.postponed))
	}
}
