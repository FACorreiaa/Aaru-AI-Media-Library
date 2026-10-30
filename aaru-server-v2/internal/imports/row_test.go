package imports

import (
	"aaru-go-api/internal/core"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// A row as Swift's synthesized Codable stored it in `import_rows.row` reads back, and is written in
// the same shape: absent optionals left out, dates as seconds since 2001, empty arrays kept apart
// from absent ones.
func TestRowJSONIsSwiftCompatible(t *testing.T) {
	stored := `{"type":"show","title":"Frieren","year":2023,"ids":{"anilist":"154587","mal":"52991"},
		"status":"finished","rating":9,"finishedAt":720000000.5,"lists":["anime"],
		"watched":[{"season":1,"episode":2}],"namedEpisodes":[],"knowsOnHold":true}`
	var row Row
	require.NoError(t, json.Unmarshal([]byte(stored), &row))
	assert.Equal(t, core.MediaShow, row.Type)
	assert.Equal(t, core.ExternalIDs{AniList: "154587", MAL: "52991"}, row.IDs)
	require.NotNil(t, row.FinishedAt)
	assert.Equal(t, time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC).Add(720000000*time.Second+500*time.Millisecond), *row.FinishedAt)
	assert.Equal(t, []core.EpisodeKey{{Season: 1, Episode: 2}}, row.Watched)
	assert.NotNil(t, row.NamedEpisodes)
	assert.Empty(t, row.NamedEpisodes)
	assert.True(t, row.HasProgress())

	encoded, err := json.Marshal(row)
	require.NoError(t, err)
	assert.JSONEq(t, stored, string(encoded))

	minimal, err := json.Marshal(Row{Type: core.MediaMovie, Title: "Dune"})
	require.NoError(t, err)
	assert.JSONEq(t, `{"type":"movie","title":"Dune","ids":{},"lists":[]}`, string(minimal))
}

func TestMergedKeepsEveryTickAndTheFurthestStatus(t *testing.T) {
	wishlist, finished, dropped := core.StatusWishlist, core.StatusFinished, core.StatusDropped
	early, late := time.Unix(1_600_000_000, 0), time.Unix(1_700_000_000, 0)
	rating := 6.0
	merged := Merged([]Row{
		{Status: &wishlist, Watched: []core.EpisodeKey{{Season: 1, Episode: 2}}, FinishedAt: &early, ListOnly: ptr(true)},
		{Status: &finished, Rating: &rating, Watched: []core.EpisodeKey{{Season: 1, Episode: 1}}, FinishedAt: &late, MangaChapter: ptr(4)},
	})
	assert.Equal(t, core.StatusFinished, *merged.Status)
	assert.Equal(t, &rating, merged.Rating)
	assert.Equal(t, late, *merged.FinishedAt)
	assert.Equal(t, []core.EpisodeKey{{Season: 1, Episode: 1}, {Season: 1, Episode: 2}}, merged.Watched)
	assert.Equal(t, 4, *merged.MangaChapter)
	assert.Nil(t, merged.ListOnly, "a library row takes the title off list-only")

	kept := Merged([]Row{{Status: &dropped}, {Status: &finished}})
	assert.Equal(t, core.StatusDropped, *kept.Status, "never out of dropped")
}
