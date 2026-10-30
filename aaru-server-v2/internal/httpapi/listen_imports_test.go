package httpapi

// ListenImportTests.swift (MUS-004) end to end: a listening history is staged, counted, applied
// into the listening log, counted on its own days in Insights, earns no points, and undoes in one
// step.

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// listenImpStarted is the same play three ways: Spotify's end time, and a scrobbler's start time.
var listenImpStarted = time.Now().Add(-3 * 24 * time.Hour).Truncate(time.Second).UTC()

var listenImpEnded = listenImpStarted.Add(240 * time.Second)

type listenImpPlay struct {
	track  string
	ended  time.Time
	played int
}

func listenImpSpotifyFile(t *testing.T, plays ...listenImpPlay) []byte {
	t.Helper()
	out := make([]map[string]any, 0, len(plays))
	for _, p := range plays {
		out = append(out, map[string]any{
			"ts": p.ended.Format(time.RFC3339), "ms_played": p.played,
			"master_metadata_track_name": p.track, "master_metadata_album_artist_name": "Radiohead",
			"master_metadata_album_album_name": "OK Computer", "spotify_track_uri": "spotify:track:x",
			"episode_name": nil, "ip_addr": "203.0.113.9",
		})
	}
	data, err := json.Marshal(out)
	require.NoError(t, err)
	return data
}

func listenImpUpload(e *libEnv, data []byte, source string) *httpResult {
	rec := e.upload("/v1/imports/csv?source="+source+"&filename=Streaming_History_Audio_2024.json", "application/octet-stream", data)
	return &httpResult{status: rec.Code, body: rec.Body.Bytes()}
}

type httpResult struct {
	status int
	body   []byte
}

func (r *httpResult) json(t *testing.T) map[string]any {
	t.Helper()
	var v map[string]any
	require.NoError(t, json.Unmarshal(r.body, &v), string(r.body))
	return v
}

// listenImpPlan runs the user's import worker until the job leaves the queue, and returns it.
func listenImpPlan(e *libEnv, id string) map[string]any {
	e.t.Helper()
	e.runImports()
	job, _ := e.importDetail(id)
	return job
}

// listenImpLog is the user's listening log: tracks, oldest first.
func listenImpLog(e *libEnv) []string {
	e.t.Helper()
	rows, err := e.pool.Query(context.Background(), `SELECT track FROM listens WHERE user_id = $1 ORDER BY listened_at`, e.user)
	require.NoError(e.t, err)
	defer rows.Close()
	var out []string
	for rows.Next() {
		var track string
		require.NoError(e.t, rows.Scan(&track))
		out = append(out, track)
	}
	require.NoError(e.t, rows.Err())
	return out
}

// listenImpLive stores a live scrobble, as the ListenBrainz ingest would.
func listenImpLive(e *libEnv, at time.Time, artist, track string, durationMs int) {
	e.t.Helper()
	_, err := e.pool.Exec(context.Background(), `INSERT INTO listens (id, user_id, listened_at, artist, track, track_key, duration_ms, source)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'live')`, uuid.New(), e.user, at, artist, track, imports.TrackKey(artist, track), durationMs)
	require.NoError(e.t, err)
}

func listenImpStats(t *testing.T, job map[string]any) map[string]float64 {
	t.Helper()
	out := map[string]float64{}
	for k, v := range job["stats"].(map[string]any) {
		out[k] = v.(float64)
	}
	return out
}

func listenImpMusicListens(e *libEnv) float64 {
	e.t.Helper()
	week := e.json(http.MethodGet, "/v1/me/stats?span=last7", nil)
	music, _ := week["music"].(map[string]any)
	n, _ := music["listens"].(float64)
	return n
}

func listenImpHasBadge(e *libEnv, badge string) bool {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM user_badges WHERE user_id = $1 AND badge = $2`, e.user, badge).Scan(&n))
	return n > 0
}

func TestListenImportSpotifyPlanApplyUndo(t *testing.T) {
	e := newLibEnv(t)
	// A scrobbler already sent the first play, live, at its start.
	listenImpLive(e, listenImpStarted, "Radiohead", "Airbag", 284_000)
	file := listenImpSpotifyFile(t,
		listenImpPlay{"Airbag", listenImpEnded, 240_000},
		listenImpPlay{"Paranoid Android", listenImpEnded.Add(400 * time.Second), 383_000},
		listenImpPlay{"Subterranean Homesick Alien", listenImpEnded.Add(800 * time.Second), 267_000},
		listenImpPlay{"Exit Music", listenImpEnded.Add(900 * time.Second), 9000},
	)
	created := listenImpUpload(e, file, "auto")
	require.Equal(t, http.StatusAccepted, created.status, string(created.body))
	id := created.json(t)["id"].(string)
	assert.Equal(t, "spotify_json", created.json(t)["source"])

	job := listenImpPlan(e, id)
	assert.Equal(t, "planned", job["state"])
	assert.InDelta(t, 3, job["rowsTotal"], 0)
	stats := listenImpStats(t, job)
	assert.InDelta(t, 2, stats["created"], 0, "two plays are new")
	assert.InDelta(t, 1, stats["skipped"], 0, "the live scrobble of the same play is not counted twice")
	assert.InDelta(t, 1, stats["ignored"], 0, "a 9 s play is not a listen")
	assert.Len(t, listenImpLog(e), 1, "nothing is written before approval")

	applied := e.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	assert.Equal(t, "succeeded", applied["state"])
	assert.InDelta(t, 2, listenImpStats(t, applied)["created"], 0)
	assert.InDelta(t, 3, applied["rowsTotal"], 0, "the counts outlive the staging")
	assert.Nil(t, applied["actionId"], "a listen is not a journaled library write")
	assert.Len(t, listenImpLog(e), 3)
	assert.Equal(t, http.StatusConflict, e.send(http.MethodPost, "/v1/imports/"+id+"/apply", nil).Code, "applies once")

	assert.InDelta(t, 3, listenImpMusicListens(e), 0, "imported listens count on their day")
	var points int
	require.NoError(t, e.pool.QueryRow(context.Background(),
		`SELECT coalesce(sum(points), 0)::int FROM points_events WHERE user_id = $1`, e.user).Scan(&points))
	assert.Zero(t, points, "no points for a backlog")
	assert.True(t, listenImpHasBadge(e, "first_listen"), "music badges count imported listens")

	undo := e.send(http.MethodPost, "/v1/imports/"+id+"/undo", nil)
	assert.Equal(t, http.StatusNoContent, undo.Code, undo.Body.String())
	assert.Equal(t, []string{"Airbag"}, listenImpLog(e), "undo removes only what the import wrote")
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/imports/"+id, nil).Code, "the import goes with it")
	assert.InDelta(t, 1, listenImpMusicListens(e), 0)
	assert.True(t, listenImpHasBadge(e, "first_listen"), "the live listen still holds its badge")
}

func TestListenImportRefusals(t *testing.T) {
	e := newLibEnv(t)
	file := listenImpSpotifyFile(t, listenImpPlay{"Airbag", listenImpEnded, 240_000})
	id := e.uploadJob("/v1/imports/csv?source=spotify", "application/octet-stream", file)
	undo := e.send(http.MethodPost, "/v1/imports/"+id+"/undo", nil)
	assert.Equal(t, http.StatusConflict, undo.Code)
	assert.Equal(t, "import_not_applied", decode[map[string]any](t, undo)["code"])

	wrong := listenImpUpload(e, file, "imdb")
	assert.Equal(t, http.StatusUnprocessableEntity, wrong.status)
	assert.Equal(t, "Only Spotify and YouTube history are JSON. Send other exports as CSV or XML.", wrong.json(t)["message"])

	csv := e.upload("/v1/imports/csv?source=auto", "text/csv", file)
	assert.Equal(t, http.StatusUnprocessableEntity, csv.Code, "JSON sent as a CSV says how to send it")

	empty := listenImpUpload(e, listenImpSpotifyFile(t, listenImpPlay{"Short", listenImpEnded, 1000}), "auto")
	assert.Equal(t, http.StatusUnprocessableEntity, empty.status, "a file with no music plays")
	assert.Equal(t, "That file has no music plays to import.", empty.json(t)["message"])

	zip := listenImpUpload(e, []byte("PK\x03\x04rest"), "auto")
	assert.Equal(t, http.StatusUnprocessableEntity, zip.status)
	assert.Equal(t, map[string]any{"file": "This is a .zip file. Unzip it and add each Streaming_History_Audio file, one at a time."},
		zip.json(t)["details"])

	lastFM := e.send(http.MethodPost, "/v1/imports/lastfm", map[string]any{"username": "rj"})
	assert.Equal(t, http.StatusServiceUnavailable, lastFM.Code, "no Last.fm key, no Last.fm import")
	body := decode[map[string]any](t, lastFM)
	assert.Equal(t, "lastfm_unavailable", body["code"])
	assert.Equal(t, "Last.fm import is not set up on this server yet.", body["message"])
}

func TestListenImportTooLarge(t *testing.T) {
	e := newLibEnv(t)
	big := make([]byte, imports.MaxListenUploadBytes+1)
	rec := e.upload("/v1/imports/csv?source=spotify", "application/octet-stream", big)
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "file_too_large", decode[map[string]any](t, rec)["code"])
}

// listenImpHistory is a listening history that hands over fixed pages and remembers where it was
// asked to stop.
type listenImpHistory struct {
	mu         sync.Mutex
	pages      [][]imports.NewListen
	missing    bool
	sinceAsked []*time.Time
}

func (h *listenImpHistory) Read(_ context.Context, _ string, since *time.Time, _ time.Time, page func(imports.ListenHistoryPage) error) error {
	h.mu.Lock()
	h.sinceAsked = append(h.sinceAsked, since)
	h.mu.Unlock()
	if h.missing {
		return provider.NewError("listenbrainz", provider.KindNotFound)
	}
	for _, listens := range h.pages {
		if err := page(imports.ListenHistoryPage{Listens: listens}); err != nil {
			return err
		}
	}
	return nil
}

func TestListenImportAccount(t *testing.T) {
	e := newLibEnv(t)
	ctx := context.Background()
	newest := listenImpStarted.Add(600 * time.Second)
	reader := &listenImpHistory{pages: [][]imports.NewListen{
		{{ListenedAt: newest, Artist: "Burial", Track: "Archangel"}},
		{{ListenedAt: listenImpStarted, Artist: "Burial", Track: "Near Dark"}},
	}}
	svc := e.server.Imports
	svc.ListenHistory = map[core.ImportSource]imports.ListenHistoryReader{core.SourceListenBrainz: reader}

	bad, err := svc.CreateListenAccountImport(ctx, e.user, core.SourceListenBrainz, "a\nb")
	require.Error(t, err, bad.ID)
	assert.Contains(t, err.Error(), "Enter your ListenBrainz username.")

	created := e.send(http.MethodPost, "/v1/imports/listenbrainz", map[string]any{"username": " @someone "})
	require.Equal(t, http.StatusAccepted, created.Code, created.Body.String())
	job := decode[map[string]any](t, created)
	assert.Equal(t, "someone", job["filename"])
	planned := listenImpPlan(e, job["id"].(string))
	assert.Equal(t, "planned", planned["state"])
	assert.InDelta(t, 2, listenImpStats(t, planned)["created"], 0)
	assert.Equal(t, []*time.Time{nil}, reader.sinceAsked)
	e.json(http.MethodPost, "/v1/imports/"+job["id"].(string)+"/apply", nil)

	again, err := svc.CreateListenAccountImport(ctx, e.user, core.SourceListenBrainz, "SOMEONE")
	require.NoError(t, err)
	replanned := listenImpPlan(e, again.ID.String())
	require.Len(t, reader.sinceAsked, 2)
	require.NotNil(t, reader.sinceAsked[1])
	assert.True(t, newest.Equal(*reader.sinceAsked[1]), "from the newest one")
	assert.InDelta(t, 0, listenImpStats(t, replanned)["created"], 0, "the same plays are not new")
	assert.InDelta(t, 2, listenImpStats(t, replanned)["skipped"], 0)

	svc.ListenHistory = map[core.ImportSource]imports.ListenHistoryReader{core.SourceListenBrainz: &listenImpHistory{missing: true}}
	missing, err := svc.CreateListenAccountImport(ctx, e.user, core.SourceListenBrainz, "nobody")
	require.NoError(t, err)
	failed := listenImpPlan(e, missing.ID.String())
	assert.Equal(t, "failed", failed["state"])
	assert.Equal(t, "ListenBrainz has no user “nobody”. Check the username, then import again.", failed["errorSummary"])

	svc.ListenHistory = map[core.ImportSource]imports.ListenHistoryReader{core.SourceListenBrainz: &listenImpHistory{}}
	nothing, err := svc.CreateListenAccountImport(ctx, e.user, core.SourceListenBrainz, "someone")
	require.NoError(t, err)
	none := listenImpPlan(e, nothing.ID.String())
	assert.Equal(t, "failed", none["state"])
	assert.Equal(t, "Nothing new on ListenBrainz since your last import of someone.", none["errorSummary"])
}

func TestListenImportUndoRefusesLibraryImport(t *testing.T) {
	e := newLibEnv(t)
	now := time.Now().UTC()
	job := core.ImportJob{
		ID: uuid.New(), UserID: e.user, Source: core.SourceIMDbCSV, State: core.JobSucceeded, CreatedAt: now, UpdatedAt: now,
	}
	require.NoError(t, e.server.Imports.Store.Insert(context.Background(), job, nil))
	undo := e.send(http.MethodPost, "/v1/imports/"+job.ID.String()+"/undo", nil)
	assert.Equal(t, http.StatusConflict, undo.Code)
	assert.Equal(t, "import_not_listens", decode[map[string]any](t, undo)["code"])
}

func TestListenImportBigApply(t *testing.T) {
	e := newLibEnv(t)
	ctx := context.Background()
	base := time.Now().Add(-400 * 24 * time.Hour).UTC()
	plays := make([]imports.NewListen, 20000)
	duration := 200_000
	for i := range plays {
		plays[i] = imports.NewListen{
			ListenedAt: base.Add(time.Duration(i) * 200 * time.Second), Artist: fmt.Sprintf("Artist %d", i%300),
			Track: fmt.Sprintf("Track %d", i%2000), DurationMs: &duration,
		}
	}
	name := "big.json"
	now := time.Now().UTC()
	job := core.ImportJob{
		ID: uuid.New(), UserID: e.user, Source: core.SourceSpotifyJSON, State: core.JobQueued, Filename: &name,
		CreatedAt: now, UpdatedAt: now, RowsTotal: len(plays),
	}
	require.NoError(t, e.server.Imports.Store.Insert(ctx, job, nil))
	store := music.NewStore(e.pool)
	require.NoError(t, store.Stage(ctx, plays, job.ID, 0))
	planned := listenImpPlan(e, job.ID.String())
	assert.InDelta(t, 20000, listenImpStats(t, planned)["created"], 0)
	start := time.Now()
	applied, err := store.ApplyStaged(ctx, job.ID, e.user)
	require.NoError(t, err)
	assert.Equal(t, 20000, applied)
	assert.Less(t, time.Since(start), 15*time.Second)
}
