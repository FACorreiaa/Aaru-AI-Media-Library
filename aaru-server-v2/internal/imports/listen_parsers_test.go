package imports

// ListenImportParserTests.swift: listening history files and pages read into listens, with what is
// left out counted.

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var listenTestNow = time.Unix(1_800_000_000, 0).UTC()

func listenSpotifyPlay(ended string, played int, track, artist, episode *string) map[string]any {
	return map[string]any{
		"ts": ended, "platform": "ios", "ms_played": played, "conn_country": "PT", "ip_addr": "203.0.113.9",
		"master_metadata_album_album_name": "OK Computer",
		"spotify_track_uri":                "spotify:track:6LgJvl0Xdtc73RJ1mmpotq",
		"reason_start":                     "trackdone", "reason_end": "trackdone", "shuffle": false, "skipped": false,
		"master_metadata_track_name": track, "master_metadata_album_artist_name": artist, "episode_name": episode,
	}
}

func listenJSON(t *testing.T, v any) []byte {
	t.Helper()
	data, err := json.Marshal(v)
	require.NoError(t, err)
	return data
}

func sp(s string) *string { return &s }

func TestListenSpotifyHistory(t *testing.T) {
	radiohead := sp("Radiohead")
	audiobook := listenSpotifyPlay("2024-03-01T10:10:00Z", 600_000, nil, nil, nil)
	audiobook["audiobook_title"] = "Dune"
	data := listenJSON(t, []any{
		listenSpotifyPlay("2024-03-01T10:04:44Z", 284_000, sp("Airbag"), radiohead, nil),
		listenSpotifyPlay("2024-03-01T10:05:10Z", 12000, sp("Paranoid Android"), radiohead, nil),
		listenSpotifyPlay("2024-03-01T11:00:00Z", 1_800_000, nil, nil, sp("A podcast")),
		audiobook,
	})
	source, err := DetectListenFile(data)
	require.NoError(t, err)
	assert.Equal(t, core.SourceSpotifyJSON, source)
	page, err := ParseSpotifyHistory(data, listenTestNow)
	require.NoError(t, err)
	assert.Equal(t, 3, page.Ignored)
	require.Len(t, page.Listens, 1)
	l := page.Listens[0]
	assert.Equal(t, time.Unix(1_709_287_200, 0).UTC(), l.ListenedAt, "10:04:44 − 4:44 = 10:00:00")
	assert.Equal(t, "Radiohead", l.Artist)
	assert.Equal(t, "Airbag", l.Track)
	assert.Equal(t, sp("OK Computer"), l.Album)
	assert.Equal(t, 284_000, *l.DurationMs)
	assert.Equal(t, sp("6LgJvl0Xdtc73RJ1mmpotq"), l.SpotifyID)
	assert.Equal(t, sp("Spotify"), l.MusicService)
	assert.Nil(t, l.OriginURL, "nothing else from the file")
	assert.Nil(t, l.Client, "nothing else from the file")
}

func TestListenSpotifyRefusals(t *testing.T) {
	basic := listenJSON(t, []any{map[string]any{
		"endTime": "2024-03-01 10:04", "artistName": "Radiohead", "trackName": "Airbag", "msPlayed": 284_000,
	}})
	for _, data := range [][]byte{basic, []byte("PK\x03\x04rest"), []byte("[]")} {
		_, err := DetectListenFile(data)
		var format *FormatError
		assert.True(t, errors.As(err, &format), string(data))
	}
}

func listenTakeout(header string, title *string, channel *string, link *string, advert bool) map[string]any {
	entry := map[string]any{"header": header, "time": "2024-05-02T21:15:07.123Z", "products": []string{"YouTube"}}
	if title != nil {
		entry["title"] = *title
	}
	if link != nil {
		entry["titleUrl"] = *link
	}
	if channel != nil {
		entry["subtitles"] = []any{map[string]any{"name": *channel, "url": "https://www.youtube.com/channel/UC1"}}
	}
	if advert {
		entry["details"] = []any{map[string]any{"name": "From Google Ads"}}
	}
	return entry
}

func TestListenTakeoutMusicOnly(t *testing.T) {
	music := sp("https://music.youtube.com/watch?v=abc")
	data := listenJSON(t, []any{
		listenTakeout("YouTube Music", sp("Watched Teardrop"), sp("Massive Attack - Topic"), music, false),
		listenTakeout("YouTube Music", sp("Watched Karma Police"), sp("RadioheadVEVO"), music, false),
		listenTakeout("YouTube", sp("Watched Archangel"), sp("Burial - Topic"), sp("https://www.youtube.com/watch?v=x1"), false),
		listenTakeout("YouTube", sp("Watched How to bake bread"), sp("A Baker"), sp("https://www.youtube.com/watch?v=x2"), false),
		listenTakeout("YouTube", sp("Watched An advert"), sp("Brand - Topic"), music, true),
		listenTakeout("YouTube Music", sp("Watched a video that has been removed"), nil, nil, false),
		listenTakeout("YouTube Music", sp("Watched https://music.youtube.com/watch?v=gone"), sp("Someone - Topic"), music, false),
	})
	source, err := DetectListenFile(data)
	require.NoError(t, err)
	assert.Equal(t, core.SourceYouTubeTakeout, source)
	page, err := ParseYouTubeTakeout(data, listenTestNow)
	require.NoError(t, err)
	var artists, tracks, services []string
	for _, l := range page.Listens {
		artists = append(artists, l.Artist)
		tracks = append(tracks, l.Track)
		services = append(services, *l.MusicService)
		assert.Nil(t, l.DurationMs, "no length: the 30 s window")
	}
	assert.Equal(t, []string{"Massive Attack", "Radiohead", "Burial"}, artists)
	assert.Equal(t, []string{"Teardrop", "Karma Police", "Archangel"}, tracks)
	assert.Equal(t, []string{"YouTube Music", "YouTube Music", "YouTube"}, services)
	assert.Equal(t, sp("https://www.youtube.com/watch?v=x1"), page.Listens[2].OriginURL)
	assert.Equal(t, int64(1_714_684_507), page.Listens[0].ListenedAt.Unix())
	assert.Equal(t, 4, page.Ignored)
}

func TestListenTakeoutOtherLanguage(t *testing.T) {
	songs := []string{"Teardrop", "Angel", "Inertia Creeps", "Archangel", "Near Dark"}
	videos := []string{"Como fazer pão", "Receita de bacalhau", "Notícias da manhã", "Golos da jornada", "Viagem a Lisboa"}
	link := sp("https://music.youtube.com/watch?v=abc")
	var entries []any
	for _, s := range songs {
		entries = append(entries, listenTakeout("YouTube Music", sp("Assistiu a "+s), sp("Artista - Topic"), link, false))
	}
	for _, v := range videos {
		entries = append(entries, listenTakeout("YouTube", sp("Assistiu a "+v), sp("Um canal"), link, false))
	}
	page, err := ParseYouTubeTakeout(listenJSON(t, entries), listenTestNow)
	require.NoError(t, err)
	var tracks []string
	for _, l := range page.Listens {
		tracks = append(tracks, l.Track)
	}
	assert.Equal(t, songs, tracks, "the verb comes from every title, videos too")
	assert.Equal(t, len(videos), page.Ignored)

	few, err := ParseYouTubeTakeout(listenJSON(t, entries[:3]), listenTestNow)
	require.NoError(t, err)
	assert.Equal(t, 3, few.Ignored, "too few titles to tell the verb")
}

func TestListenLastFMPage(t *testing.T) {
	body := `{"recenttracks":{"track":[
	  {"artist":{"mbid":"","#text":"Burial"},"album":{"mbid":"","#text":"Untrue"},"name":"Archangel","mbid":"",
	   "@attr":{"nowplaying":"true"}},
	  {"artist":{"mbid":"a74b1b7f-71a5-4011-9441-d0b5e4122711","#text":"Radiohead"},
	   "album":{"mbid":"b1392450-e666-3926-a536-22c65f834433","#text":"OK Computer"},"name":"Airbag",
	   "mbid":"8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b","date":{"uts":"1700000000","#text":"14 Nov 2023, 22:13"}}
	],"@attr":{"user":"rj","totalPages":"1","page":"1","perPage":"200","total":"1"}}}`
	var decoded lastFMPageBody
	require.NoError(t, json.Unmarshal([]byte(body), &decoded))
	page := lastFMPage(decoded.RecentTracks.Tracks, listenTestNow)
	assert.Equal(t, 0, page.Ignored, "a track playing now is not left out, it is not yet a scrobble")
	require.Len(t, page.Listens, 1)
	l := page.Listens[0]
	assert.Equal(t, time.Unix(1_700_000_000, 0).UTC(), l.ListenedAt)
	assert.Equal(t, sp("a74b1b7f-71a5-4011-9441-d0b5e4122711"), l.ArtistMBID)
	assert.Equal(t, sp("b1392450-e666-3926-a536-22c65f834433"), l.ReleaseMBID)
	assert.Equal(t, sp("8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b"), l.RecordingMBID)
	assert.Equal(t, sp("Last.fm"), l.Client)

	single := `{"recenttracks":{"track":{"artist":{"#text":"Burial"},"name":"Archangel","date":{"uts":"1700000100"}},
	 "@attr":{"totalPages":"1"}}}`
	var one lastFMPageBody
	require.NoError(t, json.Unmarshal([]byte(single), &one))
	assert.Len(t, one.RecentTracks.Tracks, 1)
}

// listenStub is a provider transport that answers with respond and records every URL asked.
type listenStub struct {
	mu      sync.Mutex
	urls    []string
	respond func(u *url.URL) (int, string)
}

func (s *listenStub) transport() provider.Transport {
	return provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
		s.mu.Lock()
		s.urls = append(s.urls, req.URL)
		respond := s.respond
		s.mu.Unlock()
		u, err := url.Parse(req.URL)
		if err != nil {
			return nil, err
		}
		status, body := respond(u)
		return &provider.Response{Status: status, Body: []byte(body)}, nil
	})
}

func TestListenLastFMReader(t *testing.T) {
	stub := &listenStub{respond: func(u *url.URL) (int, string) {
		page := u.Query().Get("page")
		uts := 1_700_000_100
		if page == "1" {
			uts = 1_700_000_200
		}
		return 200, fmt.Sprintf(`{"recenttracks":{"track":[{"artist":{"#text":"Burial"},"name":"Track %s","date":{"uts":"%d"}}],
		 "@attr":{"totalPages":"2"}}}`, page, uts)
	}}
	reader := &LastFMHistory{
		Client: NewLastFMClient(stub.transport(), provider.NewPacer(1000, 100)), APIKey: "test-key", UserAgent: "Aaru tests",
	}
	since := time.Unix(1_600_000_000, 0)
	var tracks []string
	require.NoError(t, reader.Read(context.Background(), "rj", &since, listenTestNow, func(p ListenHistoryPage) error {
		for _, l := range p.Listens {
			tracks = append(tracks, l.Track)
		}
		return nil
	}))
	assert.Equal(t, []string{"Track 1", "Track 2"}, tracks)
	first := stub.urls[0]
	assert.True(t, strings.Contains(first, "from=1600000001") && strings.Contains(first, "to=1800000000") &&
		strings.Contains(first, "user=rj"), first)

	for code, want := range map[int]*provider.Error{
		6:  provider.NewError("lastfm", provider.KindNotFound),
		17: {Provider: "lastfm", Kind: provider.KindRefused, Status: LastFMPrivateListening},
		29: provider.NewError("lastfm", provider.KindUnavailable),
	} {
		stub.mu.Lock()
		stub.respond = func(*url.URL) (int, string) { return 400, fmt.Sprintf(`{"error":%d,"message":"no"}`, code) }
		stub.mu.Unlock()
		err := reader.Read(context.Background(), "rj", nil, listenTestNow, func(ListenHistoryPage) error { return nil })
		assert.ErrorIs(t, err, want, "code %d", code)
	}
	stub.respond = func(*url.URL) (int, string) { return 200, `{"error":17,"message":"no"}` }
	err := reader.Read(context.Background(), "rj", nil, listenTestNow, func(ListenHistoryPage) error { return nil })
	assert.True(t, IsLastFMPrivate(err), "an error answered with a 200")
}

func TestListenBrainzReader(t *testing.T) {
	stub := &listenStub{respond: func(u *url.URL) (int, string) {
		before := u.Query().Get("max_ts")
		listens := "[]"
		if before > "1700000000" {
			listens = `[{"listened_at":1700000500,"track_metadata":{"artist_name":"Burial","track_name":"Archangel",
			  "release_name":"Untrue","additional_info":{"duration_ms":239000,"submission_client":"Pano Scrobbler"},
			  "mbid_mapping":{"recording_mbid":"8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b",
			    "artist_mbids":["9ddce51c-2b75-4b3e-ac8c-1db09e7c89c6"]}}},
			 {"listened_at":1700000000,"track_metadata":{"artist_name":"Burial","track_name":"Near Dark"}},
			 {"listened_at":1699999999,"track_metadata":{"track_name":"No artist"}}]`
		}
		return 200, `{"payload":{"count":3,"listens":` + listens + `}}`
	}}
	reader := &ListenBrainzHistory{
		Client: provider.NewClient("listenbrainz", stub.transport(), provider.NewPacer(1000, 100)), UserAgent: "Aaru tests",
	}
	var tracks []string
	ignored := 0
	var first NewListen
	require.NoError(t, reader.Read(context.Background(), "some user", nil, listenTestNow, func(p ListenHistoryPage) error {
		for _, l := range p.Listens {
			if len(tracks) == 0 {
				first = l
			}
			tracks = append(tracks, l.Track)
		}
		ignored += p.Ignored
		return nil
	}))
	assert.Equal(t, []string{"Archangel", "Near Dark"}, tracks)
	assert.Equal(t, 1, ignored)
	require.Len(t, stub.urls, 2)
	assert.Contains(t, stub.urls[0], "/1/user/some%20user/listens")
	assert.Contains(t, stub.urls[0], "max_ts=1800000001")
	assert.Contains(t, stub.urls[1], "max_ts=1699999999")
	assert.NotContains(t, stub.urls[0], "min_ts")
	assert.Equal(t, 239000, *first.DurationMs)
	assert.Equal(t, sp("Pano Scrobbler"), first.Client)
	assert.Equal(t, sp("8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b"), first.RecordingMBID)
	assert.Equal(t, sp("9ddce51c-2b75-4b3e-ac8c-1db09e7c89c6"), first.ArtistMBID)
}

func TestListenBrainzMapping(t *testing.T) {
	body := `{"payload":{"listens":[{"listened_at":1700000500,"track_metadata":{"artist_name":"Burial",
	 "track_name":"Archangel","additional_info":{"recording_mbid":"11111111-1111-1111-1111-111111111111"},
	 "mbid_mapping":{"recording_mbid":"8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b",
	 "release_mbid":"22222222-2222-2222-2222-222222222222"}}}]}}`
	page, oldest, err := listenBrainzHistoryPage([]byte(body), listenTestNow)
	require.NoError(t, err)
	require.Len(t, page.Listens, 1)
	l := page.Listens[0]
	assert.Equal(t, sp("11111111-1111-1111-1111-111111111111"), l.RecordingMBID, "what was sent wins")
	assert.Equal(t, sp("22222222-2222-2222-2222-222222222222"), l.ReleaseMBID)
	assert.Equal(t, sp("ListenBrainz"), l.Client)
	require.NotNil(t, oldest)
	assert.Equal(t, int64(1_700_000_500), *oldest)
}

func TestListenTrackKeyFolds(t *testing.T) {
	assert.Equal(t, "radiohead\u001fairbag", TrackKey("  RADIOHEAD ", "Airbag"))
	assert.Equal(t, TrackKey("Ｒａｄｉｏｈｅａｄ", "Paranoid   Android"), TrackKey("radiohead", "paranoid android"),
		"width and spaces fold")
	assert.Nil(t, listenMBID(sp("not-a-uuid")))
	assert.Nil(t, listenMBID(sp("8f2e5e5c8b0e4f2b9a8d2a5c7f1e2d3b")), "only the 36-character form")
	assert.Equal(t, sp("8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b"), listenMBID(sp("8F2E5E5C-8B0E-4F2B-9A8D-2A5C7F1E2D3B")))
}
