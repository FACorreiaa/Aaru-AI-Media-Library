package library

import (
	"aaru-go-api/internal/core"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ops round-trip through Swift's synthesized Codable shape, so either server undoes the other's.
func TestOpJSONIsSwiftsEncoding(t *testing.T) {
	item := uuid.MustParse("0b7a1e2c-3d4f-4a5b-8c6d-7e8f9a0b1c2d")
	text, err := json.Marshal(SetEpisodes(item, []core.EpisodeKey{{Season: 1, Episode: 2}}, nil))
	require.NoError(t, err)
	assert.JSONEq(t, `{"setEpisodes":{"_0":"0B7A1E2C-3D4F-4A5B-8C6D-7E8F9A0B1C2D",
		"watch":[{"season":1,"episode":2}],"unwatch":[]}}`, string(text))

	// A Swift-written insert: dates are seconds since 2001-01-01, nil optionals absent.
	swift := `{"batch":{"_0":[{"insertItem":{"_0":{"id":"0B7A1E2C-3D4F-4A5B-8C6D-7E8F9A0B1C2D",
		"titleID":"1B7A1E2C-3D4F-4A5B-8C6D-7E8F9A0B1C2D","fields":{"status":"finished","isOwned":false,
		"finishedAt":783000000.5,"statusByHand":true},"addedAt":783000000,"watched":[]}}},
		{"renameList":{"_0":"2B7A1E2C-3D4F-4A5B-8C6D-7E8F9A0B1C2D","_1":"Noir"}}]}}`
	var op Op
	require.NoError(t, json.Unmarshal([]byte(swift), &op))
	require.Equal(t, OpBatch, op.Kind)
	require.Len(t, op.Ops, 2)
	insert := op.Ops[0].Snapshot
	assert.Equal(t, item, insert.ID)
	assert.Equal(t, core.StatusFinished, insert.Fields.Status)
	assert.True(t, *insert.Fields.StatusByHand)
	assert.Nil(t, insert.Fields.Rating)
	assert.Equal(t, time.Date(2025, 10, 24, 12, 0, 0, 500_000_000, time.UTC), insert.Fields.FinishedAt.UTC())
	assert.Equal(t, "Noir", op.Ops[1].Name)

	again, err := json.Marshal(op)
	require.NoError(t, err)
	assert.JSONEq(t, swift, string(again))
	assert.Equal(t, []uuid.UUID{item}, op.ItemIDs())
}

func TestCursorAndLabels(t *testing.T) {
	c := Cursor{UpdatedAtMicros: 1_700_000_000_123_456, ID: uuid.MustParse("0b7a1e2c-3d4f-4a5b-8c6d-7e8f9a0b1c2d")}
	parsed, ok := ParseCursor(c.Token())
	require.True(t, ok)
	assert.Equal(t, c, parsed)
	_, ok = ParseCursor("not a cursor")
	assert.False(t, ok)

	assert.Equal(t, "Plan to read", StatusLabel(core.StatusWishlist, core.MediaManga))
	assert.Equal(t, "Listened", StatusLabel(core.StatusFinished, core.MediaAlbum))
	assert.Equal(t, "Watching", StatusLabel(core.StatusInProgress, core.MediaShow))
	assert.Equal(t, "On hold", StatusLabel(core.StatusOnHold, core.MediaBook))

	name := "Stremio"
	assert.Equal(t, "Stremio: marked 2 episodes", Caller{AgentName: &name}.Summary("Marked 2 episodes"))
}
