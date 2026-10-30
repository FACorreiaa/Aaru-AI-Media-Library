package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/csv"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ExportTests.swift: `GET /v1/me/export`, the whole account as JSON and a CSV Aaru's own importer
// reads back. Library rows are inserted with SQL (the library area is ported on its own branch).

type exportFixture struct {
	h      *harness
	user   uuid.UUID
	bearer string
}

func newExportFixture(t *testing.T) exportFixture {
	h := newHarness(t)
	user, bearer := h.signIn()
	return exportFixture{h: h, user: user, bearer: bearer}
}

func (f exportFixture) exec(sql string, args ...any) {
	f.h.t.Helper()
	_, err := f.h.pool.Exec(context.Background(), sql, args...)
	require.NoError(f.h.t, err)
}

func (f exportFixture) title(kind, name, tmdb string) uuid.UUID {
	id := uuid.New()
	f.exec(`INSERT INTO titles (id, type, title, year, tmdb) VALUES ($1, $2, $3, 2016, $4)`, id, kind, name, tmdb)
	return id
}

func (f exportFixture) item(title uuid.UUID, status string, added time.Time) uuid.UUID {
	id := uuid.New()
	f.exec(`INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5)`,
		id, f.user, title, status, added)
	return id
}

func TestExportJSON(t *testing.T) {
	f := newExportFixture(t)
	base := time.Now().Add(-time.Hour)
	show := f.item(f.title("show", "Andor", "andor"), "in_progress", base)
	for _, ep := range []int{2, 1} {
		f.exec(`INSERT INTO episode_progress (id, library_item_id, season, episode) VALUES ($1, $2, 1, $3)`, uuid.New(), show, ep)
	}
	arrivalTitle := f.title("movie", "Arrival", "arrival")
	movie := f.item(arrivalTitle, "finished", base.Add(time.Minute))
	f.exec(`UPDATE library_items SET rating = 9, notes = 'Again, "slowly"' WHERE id = $1`, movie)
	list := uuid.New()
	f.exec(`INSERT INTO lists (id, user_id, name, created_at, updated_at) VALUES ($1, $2, 'Sci-fi', now(), now())`, list, f.user)
	f.exec(`INSERT INTO list_items (id, list_id, title_id, position) VALUES ($1, $2, $3, 0)`, uuid.New(), list, arrivalTitle)
	f.exec(`INSERT INTO saved_queries (id, user_id, name, filter, is_pinned) VALUES ($1, $2, 'Owned films', '{"type":"movie","isOwned":true}', true)`,
		uuid.New(), f.user)
	f.exec(`INSERT INTO favorites (user_id, kind, position, title_id) VALUES ($1, 'film', 0, $2)`, f.user, arrivalTitle)
	f.exec(`INSERT INTO avatars (user_id, image) VALUES ($1, '\xffd8'::bytea)`, f.user)
	f.exec(`INSERT INTO listens (id, user_id, listened_at, artist, track, track_key, release_group_mbid, source)
VALUES ($1, $2, now(), 'Radiohead', 'Airbag', 'radiohead|airbag', 'b1392450-e666-3926-a536-22c65f834433', 'live')`,
		uuid.New(), f.user)
	friend := uuid.New()
	f.exec(`INSERT INTO users (id, display_name) VALUES ($1, 'Kim')`, friend)
	f.exec(`INSERT INTO profiles (user_id, handle) VALUES ($1, 'kim')`, friend)
	f.exec(`INSERT INTO social_friendships (user_low, user_high, created_at) VALUES (LEAST($1::uuid, $2::uuid), GREATEST($1::uuid, $2::uuid), now())`,
		f.user, friend)

	rec := f.h.do(http.MethodGet, "/v1/me/export?format=json", f.bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Contains(t, rec.Header().Get("Content-Disposition"), "aaru-export-")
	assert.Contains(t, rec.Header().Get("Content-Disposition"), ".json")

	export := decode[map[string]any](t, rec)
	assert.Equal(t, strings.ToUpper(f.user.String()), export["account"].(map[string]any)["userId"])
	library := export["library"].([]any)
	require.Len(t, library, 2)
	// Oldest added first.
	andor, arrival := library[0].(map[string]any), library[1].(map[string]any)
	assert.Equal(t, strings.ToUpper(show.String()), andor["id"])
	var numbers []float64
	for _, ep := range andor["watchedEpisodes"].([]any) {
		numbers = append(numbers, ep.(map[string]any)["number"].(float64))
	}
	assert.Equal(t, []float64{1, 2}, numbers)
	assert.Equal(t, strings.ToUpper(movie.String()), arrival["id"])
	assert.InDelta(t, 9.0, arrival["rating"], 0)
	assert.Equal(t, `Again, "slowly"`, arrival["notes"])
	assert.NotContains(t, arrival, "watchedEpisodes")

	lists := export["lists"].([]any)
	require.Len(t, lists, 1)
	assert.Equal(t, "Sci-fi", lists[0].(map[string]any)["name"])
	assert.Equal(t, "Arrival", lists[0].(map[string]any)["items"].([]any)[0].(map[string]any)["title"])

	shelf := export["shelves"].([]any)[0].(map[string]any)
	assert.Equal(t, "Owned films", shelf["name"])
	assert.Equal(t, map[string]any{"type": "movie", "owned": true}, shelf["filter"])

	favorites := export["favorites"].(map[string]any)
	assert.Equal(t, "Arrival", favorites["film"].([]any)[0].(map[string]any)["title"])
	assert.Empty(t, favorites["show"])

	assert.Equal(t, base64.StdEncoding.EncodeToString([]byte{0xff, 0xd8}), export["avatarJpeg"])
	friends := export["friends"].([]any)
	require.Len(t, friends, 1)
	assert.Equal(t, "kim", friends[0].(map[string]any)["handle"])
	assert.Empty(t, export["blocked"])
	assert.Empty(t, export["groups"])
	assert.Empty(t, export["groupMessages"])

	listen := export["listens"].([]any)[0].(map[string]any)
	assert.Equal(t, "Airbag", listen["track"])
	assert.Equal(t, "https://coverartarchive.org/release-group/b1392450-e666-3926-a536-22c65f834433/front-250", listen["coverUrl"])
	assert.Equal(t, "album", listen["albumRef"].(map[string]any)["type"])

	sports := export["sports"].(map[string]any)
	assert.Equal(t, []any{}, sports["follows"])
}

func TestExportCSVRoundTripColumns(t *testing.T) {
	f := newExportFixture(t)
	movie := f.item(f.title("movie", "Arrival", "329865"), "finished", time.Date(2026, 3, 4, 23, 30, 0, 0, time.UTC))
	f.exec(`UPDATE library_items SET rating = 8, notes = '=SUM(A1)', finished_at = '2026-03-05T01:00:00Z' WHERE id = $1`, movie)

	rec := f.h.do(http.MethodGet, "/v1/me/export?format=csv", f.bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Contains(t, rec.Header().Get("Content-Disposition"), "aaru-library-")
	assert.Contains(t, rec.Header().Get("Content-Disposition"), ".csv")
	assert.Equal(t, "text/csv", rec.Header().Get("Content-Type"))
	body := rec.Body.String()
	assert.True(t, strings.HasSuffix(body, "\r\n"))
	assert.Contains(t, body, ",329865,", "the TMDB id re-imports from its column")
	assert.Contains(t, body, "'=SUM(A1)", "a formula-looking note is defused for spreadsheets")

	rows, err := csv.NewReader(strings.NewReader(body)).ReadAll()
	require.NoError(t, err)
	require.Len(t, rows, 2)
	assert.Equal(t, []string{
		"Title", "Year", "Type", "Status", "Rating", "Owned", "Finished", "Added", "IMDb ID", "TMDB ID",
		"TVDB ID", "MAL ID", "AniList ID", "ISBN", "MusicBrainz ID", "Watched Episodes", "Notes",
	}, rows[0])
	assert.Equal(t, []string{
		"Arrival", "2016", "movie", "Completed", "8", "", "2026-03-05", "2026-03-04", "", "329865",
		"", "", "", "", "", "", "'=SUM(A1)",
	}, rows[1])
}

func TestExportCSVWatchedEpisodesAndAnime(t *testing.T) {
	f := newExportFixture(t)
	title := f.title("show", "Frieren", "209867")
	f.exec(`UPDATE titles SET is_anime = true WHERE id = $1`, title)
	item := f.item(title, "on_hold", time.Now())
	f.exec(`UPDATE library_items SET rating = 8.5, is_owned = true, notes = 'a, b' WHERE id = $1`, item)
	for _, k := range [][2]int{{1, 10}, {1, 2}, {0, 1}} {
		f.exec(`INSERT INTO episode_progress (id, library_item_id, season, episode) VALUES ($1, $2, $3, $4)`, uuid.New(), item, k[0], k[1])
	}
	rec := f.h.do(http.MethodGet, "/v1/me/export?format=csv", f.bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	rows, err := csv.NewReader(strings.NewReader(rec.Body.String())).ReadAll()
	require.NoError(t, err)
	require.Len(t, rows, 2)
	row := rows[1]
	assert.Equal(t, "anime", row[2])
	assert.Equal(t, "On hold", row[3])
	assert.Equal(t, "8.5", row[4])
	assert.Equal(t, "yes", row[5])
	assert.Equal(t, "S00E01 S01E02 S01E10", row[15])
	assert.Equal(t, "a, b", row[16])
}

func TestExportNeedsSignIn(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodGet, "/v1/me/export", "", nil)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
}
