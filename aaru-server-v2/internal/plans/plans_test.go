package plans

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSummaryAndCounts(t *testing.T) {
	one := []library.PreparedWrite{{Kind: "episode", Summary: "Marked 3 episodes of Andor watched", Episodes: 3}}
	assert.Equal(t, "Marked 3 episodes of Andor watched", Summary(one))
	many := []library.PreparedWrite{
		{Kind: "add"}, {Kind: "add"}, {Kind: "season", Episodes: 6}, {Kind: "update"}, {Kind: "remove"},
	}
	assert.Equal(t, "Add 2 titles, mark 6 episodes, update 1 item, remove 1 title", Summary(many))
	assert.Equal(t, Counts{Adds: 2, Updates: 1, Removes: 1, Episodes: 6}, CountsOf(many))
}

func TestStoredJSONReadsWhatSwiftWrote(t *testing.T) {
	swift := `{"items":[{"text":"Marked S01E01 of Andor watched","titleID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",` +
		`"title":"Andor","type":"show","libraryItemID":"0A1B2C3D-0000-4000-8000-000000000001"},` +
		`{"text":"Added Dune to Plan to watch","titleID":"0A1B2C3D-0000-4000-8000-000000000002","title":"Dune","type":"movie",` +
		`"posterURL":"https://image.tmdb.org/p.jpg"}]}`
	changes, err := decodeChanges([]byte(swift))
	require.NoError(t, err)
	require.Len(t, changes, 2)
	assert.Equal(t, core.MediaShow, changes[0].Type)
	require.NotNil(t, changes[0].LibraryItemID)
	assert.Nil(t, changes[1].LibraryItemID)
	again, err := encodeChanges(changes)
	require.NoError(t, err)
	assert.JSONEq(t, swift, string(again))

	basis := `{"items":{"0a1b2c3d-0000-4000-8000-000000000001":1761800000123456},"absentTitles":["0A1B2C3D-0000-4000-8000-000000000002"]}`
	b, err := decodeBasis([]byte(basis))
	require.NoError(t, err)
	assert.Equal(t, int64(1761800000123456), b.Items["0a1b2c3d-0000-4000-8000-000000000001"])
	assert.Equal(t, uuid.MustParse("0a1b2c3d-0000-4000-8000-000000000002"), b.AbsentTitles[0])
	encoded, err := encodeBasis(b)
	require.NoError(t, err)
	assert.JSONEq(t, basis, string(encoded))
	empty, err := encodeBasis(Basis{})
	require.NoError(t, err)
	assert.JSONEq(t, `{"items":{},"absentTitles":[]}`, string(empty))
}

func TestTapSized(t *testing.T) {
	key, _ := core.NewEpisodeKey(1, 1)
	season := 1
	assert.True(t, AgentChange{Kind: ChangeAdd}.IsTapSized())
	assert.True(t, AgentChange{Kind: ChangeUpdate}.IsTapSized())
	assert.True(t, AgentChange{Kind: ChangeEpisodes, Keys: []core.EpisodeKey{key}}.IsTapSized())
	assert.False(t, AgentChange{Kind: ChangeEpisodes, Keys: []core.EpisodeKey{key, key}}.IsTapSized())
	assert.False(t, AgentChange{Kind: ChangeEpisodes, Season: &season}.IsTapSized())
	assert.False(t, AgentChange{Kind: ChangeRemove}.IsTapSized())
}
