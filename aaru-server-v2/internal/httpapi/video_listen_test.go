package httpapi

import (
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/scrobble"
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// VideoListenTests.swift (SCR-011): a YouTube music video the extension reports becomes one live listen
// once heard, and a music scrobbler's listen of the same video is the same play.

func teardropBody(t *testing.T, progress float64, durationMs int64, isMusic bool) scrobble.Body {
	t.Helper()
	track := ""
	if isMusic {
		track = `,"music":{"artist":" Massive Attack ","track":"Teardrop"}`
	}
	b, err := scrobble.ParseBody(fmt.Appendf(nil, `{"source":"youtube","ref":"u7K72X4eo_s","video":{"id":"u7K72X4eo_s","title":"Teardrop",
	 "channel":"Massive Attack - Topic"%s},"progress":%v,"durationMs":%d}`, track, progress, durationMs))
	require.NoError(t, err)
	return b
}

func TestVideoListenHeardIsHalfOrFourMinutesOfAVideoOf30sOrMore(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	heard := func(progress float64, durationMs int64, isMusic bool) *music.NewListen {
		l, err := teardropBody(t, progress, durationMs, isMusic).VideoListen(now)
		require.NoError(t, err)
		return l
	}
	assert.Nil(t, heard(30, 330_000, true), "99 s of 330 s")
	listen := heard(60, 330_000, true)
	require.NotNil(t, listen)
	assert.Equal(t, now.Add(-198*time.Second), listen.ListenedAt, "dated from when it began")
	assert.Equal(t, "Massive Attack", listen.Artist)
	assert.Equal(t, "Teardrop", listen.Track)
	assert.Equal(t, "https://www.youtube.com/watch?v=u7K72X4eo_s", *listen.OriginURL)
	assert.Equal(t, "Aaru extension", *listen.Client)
	assert.Equal(t, "YouTube", *listen.MusicService)
	assert.NotNil(t, heard(20, 1_200_000, true), "4 min of 20")
	assert.Nil(t, heard(100, 20000, true), "a 20 s clip")
	assert.Nil(t, heard(90, 330_000, false), "not music")
}

func TestVideoIDIsReadFromEveryYouTubeWatchLinkAndNothingElse(t *testing.T) {
	id := func(s string) string {
		if v := music.YouTubeVideoID(s); v != nil {
			return *v
		}
		return ""
	}
	assert.Equal(t, "u7K72X4eo_s", id("https://www.youtube.com/watch?v=u7K72X4eo_s&t=4"))
	assert.Equal(t, "u7K72X4eo_s", id("https://music.youtube.com/watch?v=u7K72X4eo_s"))
	assert.Equal(t, "u7K72X4eo_s", id("https://youtu.be/u7K72X4eo_s"))
	assert.Empty(t, id("https://www.youtube.com/shorts/u7K72X4eo_s"))
	assert.Empty(t, id("https://evil.example/watch?v=u7K72X4eo_s"))
	assert.Empty(t, id("https://www.youtube.com/watch?v=short"))
}

func (e *libEnv) videoReport(action, token string, progress float64, isMusic bool, id string) int {
	e.t.Helper()
	video := map[string]any{"id": id, "title": "Teardrop", "channel": "Massive Attack - Topic"}
	if isMusic {
		video["music"] = map[string]any{"artist": "Massive Attack", "track": "Teardrop"}
	}
	return e.do(http.MethodPost, "/v1/scrobble/"+action, token, map[string]any{
		"source": "youtube", "ref": id, "video": video, "progress": progress, "durationMs": 330_000,
	}).Code
}

func (e *libEnv) listenItems() []any {
	e.t.Helper()
	items, _ := e.json(http.MethodGet, "/v1/me/listens", nil)["items"].([]any)
	return items
}

func TestVideoListenIsOneListenHoweverOftenItReportsAndEarnsPoints(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connect("browser")
	assert.Equal(t, http.StatusOK, env.videoReport("start", token, 10, true, "u7K72X4eo_s"))
	assert.Empty(t, env.listenItems(), "not heard yet")
	assert.Equal(t, http.StatusOK, env.videoReport("start", token, 55, true, "u7K72X4eo_s"))
	assert.Equal(t, http.StatusOK, env.videoReport("pause", token, 70, true, "u7K72X4eo_s"))
	assert.Equal(t, http.StatusOK, env.videoReport("stop", token, 98, true, "u7K72X4eo_s"))
	logged := env.listenItems()
	require.Len(t, logged, 1)
	assert.Equal(t, "Teardrop", logged[0].(map[string]any)["track"])
	points, err := env.server.Gamification.TotalPoints(context.Background(), env.user)
	require.NoError(t, err)
	assert.Positive(t, points)

	assert.Equal(t, http.StatusOK, env.videoReport("start", token, 90, false, "dQw4w9WgXcQ"))
	assert.Len(t, env.listenItems(), 1, "a video that is not music stays a play")
}

func TestVideoListenAndAScrobblersListenOfTheSameVideoAreOnePlay(t *testing.T) {
	env := newLibEnv(t)
	store := env.server.Listens.Store
	// Web Scrobbler spelled it its own way, on YouTube Music's link for the video.
	started := time.Now().Add(-198 * time.Second).Unix() // whole seconds, rounded down
	at := func(offset int64) time.Time { return time.Unix(started+offset, 0) }
	_, err := store.Insert(context.Background(), []music.NewListen{{
		ListenedAt: at(20), Artist: "Massive Attack", Track: "Teardrop (2006 Remaster)", DurationMs: ptr(330_000),
		OriginURL: ptr("https://music.youtube.com/watch?v=u7K72X4eo_s"), Client: ptr("Web Scrobbler"),
	}}, env.user, nil)
	require.NoError(t, err)
	_, token := env.connect("browser")
	assert.Equal(t, http.StatusOK, env.videoReport("start", token, 60, true, "u7K72X4eo_s"))
	logged := env.listenItems()
	require.Len(t, logged, 1, "the extension adds nothing")
	assert.Equal(t, "Teardrop (2006 Remaster)", logged[0].(map[string]any)["track"])

	kept, err := store.Insert(context.Background(), []music.NewListen{{
		ListenedAt: at(400), Artist: "Massive Attack", Track: "Teardrop", DurationMs: ptr(330_000),
		OriginURL: ptr("https://www.youtube.com/watch?v=u7K72X4eo_s"),
	}}, env.user, nil)
	require.NoError(t, err)
	assert.Equal(t, 1, kept, "past the video's length it is another play")
}
