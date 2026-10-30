package shares

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/social"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ShareStoreTests.dedupeByNote: the same sender, target and note find the same link; another
// note or sender does not.
func TestTheSameSenderTargetAndNoteFindTheSameLink(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	s := &Service{Q: sqlc.New(pool)}
	sender, other, titleID := uuid.New(), uuid.New(), uuid.New()
	for _, id := range []uuid.UUID{sender, other} {
		_, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, id)
		require.NoError(t, err)
	}
	_, err := pool.Exec(ctx, `INSERT INTO titles (id, type, title) VALUES ($1, 'movie', 'Arrival')`, titleID)
	require.NoError(t, err)

	title := Target{Kind: KindTitle, TitleID: titleID}
	hi := "hi"
	at := time.Unix(1_800_000_000, 0).UTC()
	withNote := Share{Code: social.NewCode(), Sender: &sender, Target: title, Note: &hi, CreatedAt: at}
	bare := Share{Code: social.NewCode(), Sender: &sender, Target: title, CreatedAt: at}
	require.NoError(t, s.Save(ctx, withNote))
	require.NoError(t, s.Save(ctx, bare))

	code := func(sender uuid.UUID, target Target, note *string) string {
		t.Helper()
		found, err := s.existing(ctx, sender, target, note)
		require.NoError(t, err)
		if found == nil {
			return ""
		}
		return found.Code
	}
	yo := "yo"
	assert.Equal(t, withNote.Code, code(sender, title, &hi))
	assert.Equal(t, bare.Code, code(sender, title, nil))
	assert.Empty(t, code(sender, title, &yo))
	assert.Empty(t, code(other, title, nil))
	assert.Empty(t, code(sender, Target{Kind: KindSportEvent, EventID: "1"}, nil))
}
