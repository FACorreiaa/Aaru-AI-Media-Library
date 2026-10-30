package imports

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AnimeListImportTests' "AniList: a public list becomes rows with both ids; a private list is
// notFound", against a stub transport.
func TestAniListRows(t *testing.T) {
	stub := provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
		body := string(req.Body)
		switch {
		case strings.Contains(body, "type: MANGA"):
			return &provider.Response{Status: 200, Body: []byte(`{"data":{"MediaListCollection":{"lists":[{"entries":[
  {"status":"CURRENT","progress":112,"progressVolumes":12,"score":9,
   "completedAt":{"year":null,"month":null,"day":null},
   "media":{"id":30002,"idMal":2,"format":"MANGA","chapters":null,"volumes":null,
            "title":{"romaji":"Berserk","english":null},"startDate":{"year":1989}}}
]}]}}}`)}, nil
		case strings.Contains(body, `"hidden"`):
			return &provider.Response{Status: 404, Body: []byte(`{"data":null,"errors":[{"message":"Private User"}]}`)}, nil
		}
		return &provider.Response{Status: 200, Body: []byte(`{"data":{"MediaListCollection":{"lists":[{"entries":[
  {"status":"CURRENT","progress":3,"score":8.5,
   "completedAt":{"year":null,"month":null,"day":null},
   "media":{"id":154587,"idMal":52991,"format":"TV","episodes":28,
            "title":{"romaji":"Sousou no Frieren","english":"Frieren"},"startDate":{"year":2023}}},
  {"status":"COMPLETED","progress":0,"score":0,"completedAt":{"year":2021,"month":3,"day":4},
   "media":{"id":21,"idMal":null,"format":"MOVIE","episodes":1,
            "title":{"romaji":"X","english":null},"startDate":{"year":2001}}}
]}]}}}`)}, nil
	})
	client := provider.NewClient("anilist", stub, provider.NewPacer(1000, 100))
	client.Sleep = func(context.Context, time.Duration) error { return nil }
	reader := AniListRows{AniList: &catalog.AniList{Client: client}}

	rows, err := reader.ListRows(context.Background(), "someone")
	require.NoError(t, err)
	require.Len(t, rows, 3)
	assert.Equal(t, []string{"154587", "21", "30002"}, []string{rows[0].IDs.AniList, rows[1].IDs.AniList, rows[2].IDs.AniList})
	assert.Equal(t, "52991", rows[0].IDs.MAL)
	assert.Equal(t, "Frieren", rows[0].Title)
	assert.Equal(t, ptr(2023), rows[0].Year)
	assert.Equal(t, pzStatus(core.StatusInProgress), rows[0].Status)
	assert.Equal(t, ptr(8.5), rows[0].Rating)
	assert.Len(t, rows[0].Watched, 3)
	assert.Equal(t, core.MediaMovie, rows[1].Type)
	assert.Equal(t, pzStatus(core.StatusFinished), rows[1].Status)
	assert.Nil(t, rows[1].Rating)
	assert.Equal(t, catalog.ParseDay(ptr("2021-03-04")), rows[1].FinishedAt)
	assert.Equal(t, core.MediaManga, rows[2].Type)
	assert.Equal(t, "2", rows[2].IDs.MAL)
	assert.Equal(t, pzStatus(core.StatusInProgress), rows[2].Status)
	assert.Equal(t, ptr(112), rows[2].MangaChapter)
	assert.Equal(t, ptr(12), rows[2].MangaVolume)
	assert.Nil(t, rows[2].Watched)
	assert.Equal(t, ptr("anilist:154587"), rows[0].SourceKey)

	_, err = reader.ListRows(context.Background(), "hidden")
	_, isProvider := provider.AsError(err)
	assert.True(t, isProvider, "%v", err)
	assert.True(t, provider.IsNotFound(err), "a private list is not found")
}
