package imports

import (
	"aaru-go-api/internal/billing"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/stremioapi"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// StremioImportTests.mapper
func TestStremioItemsMapToRows(t *testing.T) {
	item := func(raw string) stremioapi.LibraryItem {
		t.Helper()
		it, ok := stremioapi.DecodeLibraryItem([]byte(raw))
		require.True(t, ok, raw)
		return it
	}
	rows := StremioRows([]stremioapi.LibraryItem{
		item(`{"_id":"tt1","type":"movie","name":"tt1","removed":false,"temp":false,"state":{"timesWatched":1,"lastWatched":"2024-05-01T20:00:00.000Z"}}`),
		item(`{"_id":"tt2","type":"movie","name":"tt2","removed":false,"temp":false,"state":{"timeOffset":1200}}`),
		item(`{"_id":"tt3","type":"movie","name":"tt3","removed":false,"temp":false,"state":{}}`),
		item(`{"_id":"tt4","type":"movie","name":"tt4","removed":true,"temp":false,"state":{}}`),
		item(`{"_id":"tt5","type":"series","name":"tt5","removed":true,"temp":true,"state":{"watched":"tt5:1:1:1:eJxjBQAABgAG"}}`),
		item(`{"_id":"tt6","type":"movie","name":"tt6","removed":true,"temp":true,"state":{}}`),
		item(`{"_id":"kitsu:7","type":"series","name":"kitsu:7","removed":false,"temp":false,"state":{"timeOffset":10}}`),
		item(`{"_id":"tt8","type":"channel","name":"tt8","removed":false,"temp":false,"state":{}}`),
	})
	var keys []string
	var statuses []core.LibraryStatus
	for _, r := range rows {
		keys, statuses = append(keys, *r.SourceKey), append(statuses, *r.Status)
	}
	assert.Equal(t, []string{"tt1", "tt2", "tt3", "tt5", "kitsu:7"}, keys)
	assert.Equal(t, []core.LibraryStatus{
		core.StatusFinished, core.StatusInProgress, core.StatusWishlist, core.StatusInProgress, core.StatusInProgress,
	}, statuses)
	assert.Equal(t, time.Date(2024, 5, 1, 20, 0, 0, 0, time.UTC), *rows[0].FinishedAt)
	assert.Equal(t, "tt5:1:1:1:eJxjBQAABgAG", *rows[3].StremioWatched)
	assert.Equal(t, "tt5", rows[3].IDs.IMDB)
	assert.Equal(t, "Stremio lists this under an add-on's own id (kitsu), not an IMDb id. Add it by hand.", *rows[4].Unsupported)
	assert.Empty(t, rows[4].IDs.IMDB)

	_, ok := stremioapi.DecodeLibraryItem([]byte(`{"_id":42,"type":"movie"}`))
	assert.False(t, ok, "an odd item is dropped, not the import")
}

// CaptureTests.month: capture month boundaries are UTC.
func TestCaptureMonthAndDayBoundariesAreUTC(t *testing.T) {
	date, err := time.Parse(time.RFC3339, "2026-10-31T23:30:00-02:00")
	require.NoError(t, err)
	start, next := billing.MonthStart(date)
	assert.Equal(t, time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC), start)
	assert.Equal(t, time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC), next)
	assert.Equal(t, time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC), DayStart(date))
}

func TestCapturePlannedSaysWhatIsReady(t *testing.T) {
	id := uuid.New()
	msg := capturePlanned(core.ImportJob{ID: id, Stats: core.ImportStats{Created: 5, Updated: 1, Skipped: 1, Unmatched: 2}})
	assert.Equal(t, "Your capture is ready to review", msg.Title)
	assert.Equal(t, "7 ready · 2 need a pick", msg.Body)
	assert.Equal(t, map[string]string{"importId": strings.ToUpper(id.String())}, msg.Payload)
	assert.Equal(t, "1 needs a pick", capturePlanned(core.ImportJob{Stats: core.ImportStats{Unmatched: 1}}).Body)
	assert.Equal(t, "Open it to see what Aaru found.", capturePlanned(core.ImportJob{}).Body)
}

func TestCaptureContentRefusals(t *testing.T) {
	code := func(req CaptureRequest) string {
		t.Helper()
		_, _, err := captureContent(req)
		require.Error(t, err)
		return err.Error()
	}
	assert.Equal(t, "422 validation_failed: There is nothing to read.", code(CaptureRequest{Text: new("  \n ")}))
	long := make([]rune, MaxCaptureText+1)
	for i := range long {
		long[i] = 'é'
	}
	assert.Contains(t, code(CaptureRequest{Text: new(string(long))}), "413 capture_too_large: That is more text than a capture reads.")
	assert.Equal(t, "415 capture_image_type: Send the image as a JPEG, PNG, GIF or WebP.", code(CaptureRequest{Image: []byte{1}, MediaType: "image/bmp"}))
	rows, input, err := captureContent(CaptureRequest{Link: new(" https://www.themoviedb.org/movie/603 ")})
	require.NoError(t, err)
	assert.Nil(t, input)
	require.Len(t, rows, 1)
	assert.Equal(t, core.StatusWishlist, *rows[0].Status)
	assert.Equal(t, "https://www.themoviedb.org/movie/603", *rows[0].SourceKey)
}
