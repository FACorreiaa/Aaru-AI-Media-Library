package mal

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// SCR-005: target and state rules.
func TestTargetAndStateRules(t *testing.T) {
	show := core.Title{Type: core.MediaShow, Title: "X", IDs: core.ExternalIDs{MAL: "9"}}
	assert.Equal(t, []Target{{MalID: "9"}}, Targets(show, nil, nil))
	movie := core.Title{Type: core.MediaMovie, Title: "X", IDs: core.ExternalIDs{MAL: "9"}}
	assert.Empty(t, Targets(movie, nil, nil))

	total12 := 12
	total24 := 24
	state := func(status core.LibraryStatus, ticks int, total *int, first, airing bool) *EntryState {
		item := core.LibraryItem{UserID: uuid.New(), TitleID: uuid.New(), Status: status}
		return State("1", item, Share{Ticks: ticks, Total: total, IsFirst: first, IsAiring: airing})
	}
	assert.Equal(t, 12, state(core.StatusFinished, 0, &total12, true, false).Episodes, "finished counts every episode")
	airing := state(core.StatusFinished, 1, &total24, false, true)
	assert.Equal(t, Watching, airing.Status, "a season still airing is never completed")
	assert.Equal(t, 1, airing.Episodes)
	assert.Nil(t, state(core.StatusFinished, 0, &total12, false, true), "an unstarted new season stays off MAL")
	assert.Equal(t, PlanToWatch, state(core.StatusWishlist, 0, &total12, true, false).Status)
	assert.Nil(t, state(core.StatusWishlist, 0, &total12, false, false), "a plan does not add every season")
	assert.Nil(t, state(core.StatusInProgress, 0, &total12, false, false), "an unstarted later season stays off MAL")
	assert.Equal(t, Completed, state(core.StatusInProgress, 12, &total12, true, false).Status)
	assert.Equal(t, Dropped, state(core.StatusDropped, 3, &total12, true, false).Status)
	assert.Equal(t, OnHold, state(core.StatusOnHold, 3, &total12, true, false).Status, "on hold is MAL's on hold (LIB-007)")
	assert.Equal(t, 3, state(core.StatusOnHold, 3, &total12, true, false).Episodes)
	assert.Equal(t, Completed, state(core.StatusOnHold, 12, &total12, true, false).Status, "a season watched through is completed")
	assert.Nil(t, state(core.StatusOnHold, 0, &total12, false, false), "an unstarted later season stays off MAL")
}

func decodeEntry(t *testing.T, id, status string, episodes, score int, updated time.Time, mediaType string, total int) ListEntry {
	t.Helper()
	n, _ := strconv.Atoi(id)
	page, err := json.Marshal(map[string]any{"data": []any{map[string]any{
		"node": map[string]any{"id": n, "title": "Frieren", "media_type": mediaType, "num_episodes": total},
		"list_status": map[string]any{
			"status": status, "score": score, "num_episodes_watched": episodes,
			"updated_at": updated.UTC().Format("2006-01-02T15:04:05") + "+00:00",
		},
	}}})
	require.NoError(t, err)
	decoded, err := DecodeListPage(page)
	require.NoError(t, err)
	require.Len(t, decoded.Data, 1)
	return decoded.Data[0]
}

// SCR-010: entries read as IMP-013 reads MAL's export.
func TestRowsAndStates(t *testing.T) {
	now := time.Now()
	onHold := decodeEntry(t, "7", "on_hold", 2, 8, now, "tv", 3)
	row := RowOf(onHold)
	require.NotNil(t, row.Status)
	assert.Equal(t, core.StatusOnHold, *row.Status, "MAL's on hold is Aaru's (LIB-007)")
	assert.Equal(t, true, *row.KnowsOnHold)
	assert.Len(t, row.Watched, 2)
	assert.InDelta(t, 8.0, *row.Rating, 0.001)
	assert.Equal(t, &EntryState{MalID: "7", Status: OnHold, Episodes: 2, Score: 8}, StateOf(onHold))
	assert.WithinDuration(t, now, onHold.ListStatus.UpdatedAt, time.Second, "the +00:00 offset is read")

	planned := RowOf(decodeEntry(t, "8", "plan_to_watch", 0, 0, now, "tv", 3))
	assert.Equal(t, core.StatusWishlist, *planned.Status)
	assert.Nil(t, planned.Rating, "a score of 0 is no score")

	film := RowOf(decodeEntry(t, "9", "completed", 1, 0, now, "movie", 1))
	assert.Equal(t, core.MediaMovie, film.Type)
	assert.Nil(t, film.Watched)
}

func TestFormEncodesOutsideTheUnreservedSet(t *testing.T) {
	assert.Equal(t, "a=x%20y%2Bz&b=https%3A%2F%2Fa.b%2Fc", string(Form([][2]string{{"a", "x y+z"}, {"b", "https://a.b/c"}})))
}

// CAT-023: MAL marks an adult work `nsfw: black`. It is read, so a full read still lists it, and
// becomes a row the merge reports as not matched. `gray` and `white` merge as before.
func TestAdultEntriesAreRowsTheMergeLeavesOut(t *testing.T) {
	entry := func(nsfw any) ListEntry {
		page, err := json.Marshal(map[string]any{"data": []any{map[string]any{
			"node":        map[string]any{"id": 7, "title": "A title", "media_type": "ova", "num_episodes": 2, "nsfw": nsfw},
			"list_status": map[string]any{"status": "completed", "updated_at": "2026-11-13T10:00:00+00:00"},
		}}})
		require.NoError(t, err)
		decoded, err := DecodeListPage(page)
		require.NoError(t, err)
		return decoded.Data[0]
	}
	adult := entry("black")
	assert.True(t, adult.Node.Adult())
	row := RowOf(adult)
	require.NotNil(t, row.Unsupported)
	assert.Equal(t, catalog.AdultReason, *row.Unsupported)
	assert.Equal(t, "7", row.IDs.MAL, "the row still names the entry, so the read can report it")
	assert.NotNil(t, StateOf(adult), "its state is remembered, so it is not read as new every time")

	for _, nsfw := range []any{"white", "gray", nil} {
		e := entry(nsfw)
		assert.False(t, e.Node.Adult(), "%v", nsfw)
		assert.Nil(t, RowOf(e).Unsupported, "%v", nsfw)
	}
}

func TestAnimeListAsksForMALsAdultMark(t *testing.T) {
	var asked string
	transport := provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
		asked = req.URL
		return &provider.Response{Status: 200, Body: []byte(`{"data":[],"paging":{}}`)}, nil
	})
	client := provider.NewClient("mal", transport, provider.NewPacer(1000, 100))
	_, err := (&API{Client: client}).AnimeList(context.Background(), "token", 0, 100)
	require.NoError(t, err)
	u, err := url.Parse(asked)
	require.NoError(t, err)
	assert.Contains(t, strings.Split(u.Query().Get("fields"), ","), "nsfw")
	assert.Equal(t, "true", u.Query().Get("nsfw"), "every entry is read; the mark decides, not MAL's own filter")
}
