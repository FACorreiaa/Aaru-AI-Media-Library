package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/scrobble"
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// NowPlayingTests+Plays.swift (SCR-009): tracks and videos beside library episodes, in one activity.

func ptr[T any](v T) *T { return &v }

func trackListen(name string, durationMs *int, origin *string) music.NewListen {
	return music.NewListen{
		ListenedAt: time.Now(), Artist: "Artist", Track: name, DurationMs: durationMs, OriginURL: origin,
		Client: ptr("Web Scrobbler"), MusicService: ptr("YouTube Music"),
	}
}

func videoPlay(id string, state scrobble.State, now time.Time) scrobble.LivePlay {
	return scrobble.VideoPlay(scrobble.VideoReport{
		ID: id, Title: "A video", Channel: ptr("A channel"), State: state, PositionMs: 30000, DurationMs: 600_000,
	}, now)
}

func kinds(items []core.NowPlayingActivityItem) []core.NowPlayingKind {
	out := []core.NowPlayingKind{}
	for _, it := range items {
		out = append(out, it.Kind)
	}
	return out
}

func TestLiveSetOrderEpisodesAndVideosFirstThenTracksThreeAtMostNoDoubleVideo(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	show := core.Title{ID: uuid.New(), Type: core.MediaShow, Title: "Andor"}
	ep := key(1, 1)
	session := scrobble.OpenSession{
		ID: uuid.New(), Source: scrobble.SourceStremio, ExternalRef: "tt1:1:1", TitleID: show.ID,
		LibraryItemID: ptr(uuid.New()), Episode: &ep, RuntimeMinutes: ptr(50), State: scrobble.Playing,
		DurationMs: 3_000_000, UpdatedAt: now.Add(-time.Minute),
	}
	notInLibrary := session
	notInLibrary.ID = uuid.New()
	notInLibrary.LibraryItemID = nil
	song := scrobble.TrackPlay(trackListen("Song", ptr(200_000), nil), now.Add(-10*time.Second))
	clip := videoPlay("dQw4w9WgXcQ", scrobble.Playing, now.Add(-30*time.Second))
	heard := scrobble.TrackPlay(trackListen("Same clip", ptr(200_000), ptr("https://www.youtube.com/watch?v=dQw4w9WgXcQ")), now.Add(-5*time.Second))
	set := scrobble.ComputeLiveSet([]scrobble.SessionTitle{{Session: session, Title: show}, {Session: notInLibrary, Title: show}},
		[]scrobble.LivePlay{song, clip, heard}, now)
	var items []core.NowPlayingActivityItem
	var titles []string
	for _, e := range set {
		items = append(items, e.ActivityItem())
		titles = append(titles, e.ActivityItem().Title)
	}
	assert.Equal(t, []core.NowPlayingKind{"video", "episode", "track"}, kinds(items))
	assert.Equal(t, []string{"A video", "Andor", "Song"}, titles)

	expired := song
	expired.ExpiresAt = now
	assert.Empty(t, scrobble.ComputeLiveSet(nil, []scrobble.LivePlay{expired}, now))
	assert.Len(t, scrobble.ComputeLiveSet([]scrobble.SessionTitle{{Session: session, Title: show}},
		[]scrobble.LivePlay{song, clip, scrobble.TrackPlay(trackListen("Two", ptr(200_000), nil), now)}, now), 3)
}

func TestLiveActivityChangesOnlyWhenWhatItShowsChanges(t *testing.T) {
	start := time.Unix(1_000_000, 0)
	ends := core.ReferenceTime{Time: start.Add(600 * time.Second)}
	item := core.NowPlayingActivityItem{ID: "a", Kind: "video", Title: "A video", StartedAt: core.ReferenceTime{Time: start}, EndsAt: &ends}
	state := func(i core.NowPlayingActivityItem) core.NowPlayingActivityState {
		return core.NowPlayingActivityState{Items: []core.NowPlayingActivityItem{i}}
	}
	later := item
	later.StartedAt = core.ReferenceTime{Time: start.Add(2 * time.Second)}
	later.EndsAt = &core.ReferenceTime{Time: start.Add(602 * time.Second)}
	assert.False(t, scrobble.Differs(state(item), state(later)), "a heartbeat")
	seeked := item
	seeked.EndsAt = &core.ReferenceTime{Time: start.Add(900 * time.Second)}
	assert.True(t, scrobble.Differs(state(item), state(seeked)))
	paused := item
	paused.PausedAt = &core.ReferenceTime{Time: start}
	assert.True(t, scrobble.Differs(state(item), state(paused)))
	next := item
	next.ID = "b"
	assert.True(t, scrobble.Differs(state(item), state(next)))
}

func (e *nowPlayingEnv) play(p scrobble.LivePlay) {
	e.t.Helper()
	require.NoError(e.t, e.server.Scrobble.Play(context.Background(), p, e.caller))
}

func TestNowPlayingASongJoinsTheEpisodeIsReplacedByTheNextAndLeavesWhenItEnds(t *testing.T) {
	env := newNowPlayingEnv(t)
	tmdb := env.stubShow("Slow Horses", catalog.StatusReturning, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	assert.Equal(t, http.StatusNoContent, env.registerToken("start", liveToken()))
	env.report(numbered(tmdb, 1, scrobble.ActionStart, 0, 3_000_000), env.caller)
	assert.Equal(t, http.StatusNoContent, env.registerToken("update", liveToken()))
	pushed := len(env.apns.pushes())

	now := time.Now()
	env.play(scrobble.TrackPlay(trackListen("First", ptr(200_000), nil), now))
	joined := env.apns.last(t)
	assert.Len(t, env.apns.pushes(), pushed+1)
	assert.Equal(t, push.LiveActivityUpdate, joined.push.Event)
	items := content(joined.push).Items
	assert.Equal(t, []core.NowPlayingKind{"episode", "track"}, kinds(items))
	first := items[len(items)-1]
	assert.Equal(t, "First", first.Title)
	assert.Equal(t, "Artist", *first.Subtitle)
	assert.Equal(t, "YouTube Music", *first.Service)

	// The same track again is no change; the next track is a new row.
	env.play(scrobble.TrackPlay(trackListen("First", ptr(200_000), nil), now))
	assert.Len(t, env.apns.pushes(), pushed+1)
	env.play(scrobble.TrackPlay(trackListen("Second", ptr(200_000), nil), now))
	secondItems := content(env.apns.last(t).push).Items
	second := secondItems[len(secondItems)-1]
	assert.Equal(t, "Second", second.Title)
	assert.NotEqual(t, first.ID, second.ID)

	reply := env.json(http.MethodGet, "/v1/me/now-playing", nil)
	list := reply["items"].([]any)
	var replyKinds []any
	for _, it := range list {
		replyKinds = append(replyKinds, it.(map[string]any)["kind"])
	}
	assert.Equal(t, []any{"episode", "track"}, replyKinds)
	last := list[len(list)-1].(map[string]any)
	assert.Equal(t, "listenbrainz", last["source"])
	assert.Equal(t, "Second", last["name"])
	assert.Contains(t, reply, "nowPlaying", "older clients still get the episode")

	// The track ends with nothing after it: the sweep takes its row away.
	env.sweep(now.Add(200*time.Second + scrobble.TrackGrace + time.Second))
	assert.Equal(t, []core.NowPlayingKind{"episode"}, kinds(content(env.apns.last(t).push).Items))
}

func TestNowPlayingAVideoAloneStartsPausesAndEndsTheActivity(t *testing.T) {
	env := newNowPlayingEnv(t)
	assert.Equal(t, http.StatusNoContent, env.registerToken("start", liveToken()))
	env.play(videoPlay("dQw4w9WgXcQ", scrobble.Playing, time.Now()))
	started := env.apns.last(t)
	assert.Equal(t, push.LiveActivityStart, started.push.Event)
	assert.Equal(t, "A video · A channel", started.push.AlertBody)
	assert.Equal(t, "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg", *content(started.push).Items[0].ArtworkURL)
	assert.Equal(t, http.StatusNoContent, env.registerToken("update", liveToken()))

	env.play(videoPlay("dQw4w9WgXcQ", scrobble.Paused, time.Now()))
	assert.NotNil(t, content(env.apns.last(t).push).Items[0].PausedAt)
	require.NoError(t, env.server.Scrobble.StopPlay(context.Background(), scrobble.PlayVideo, env.caller))
	assert.Equal(t, push.LiveActivityEnd, env.apns.last(t).push.Event)
	assert.Empty(t, env.json(http.MethodGet, "/v1/me/now-playing", nil)["items"])
}

func TestLiveActivitySweepClaimsADueUserOnce(t *testing.T) {
	env := newNowPlayingEnv(t)
	store, ctx := env.server.Scrobble.Store, context.Background()
	_, err := store.LiveActivityState(ctx, env.user)
	require.NoError(t, err)
	now := time.Now()
	require.NoError(t, store.ScheduleLiveActivityCheck(ctx, env.user, now))
	require.NoError(t, store.ScheduleLiveActivityCheck(ctx, env.user, now.Add(time.Minute)))
	claimed, err := store.ClaimDueLiveActivityChecks(ctx, now, 10)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{env.user}, claimed, "a later check never pushes back an earlier one")
	claimed, err = store.ClaimDueLiveActivityChecks(ctx, now, 10)
	require.NoError(t, err)
	assert.Empty(t, claimed)
}

func TestVideoScrobbleBodyIsYouTubesIDANameAndADuration(t *testing.T) {
	body, err := scrobble.ParseBody([]byte(`{"source":"youtube","ref":"dQw4w9WgXcQ","video":{"id":"dQw4w9WgXcQ","title":" A video "},
	 "progress":50,"durationMs":600000}`))
	require.NoError(t, err)
	good, err := body.VideoPlay(scrobble.ActionStart, time.Now())
	require.NoError(t, err)
	assert.Equal(t, "A video", good.Title)
	assert.Nil(t, good.Subtitle)
	assert.Equal(t, int64(300_000), good.PositionMs)
	clip := `"video":{"id":"dQw4w9WgXcQ","title":"x"},"progress":1`
	for _, bad := range []string{
		`{"source":"youtube","ref":"short","video":{"id":"short","title":"x"},"progress":1,"durationMs":1}`,
		`{"source":"netflix","ref":"dQw4w9WgXcQ",` + clip + `,"durationMs":1}`,
		`{"source":"youtube","ref":"dQw4w9WgXcQ",` + clip + `}`,
		`{"source":"youtube","ref":"other",` + clip + `,"durationMs":1}`,
	} {
		b, err := scrobble.ParseBody([]byte(bad))
		if err == nil {
			_, err = b.VideoPlay(scrobble.ActionStart, time.Now())
		}
		var invalid *scrobble.InvalidError
		assert.True(t, errors.As(err, &invalid), bad)
	}
}
