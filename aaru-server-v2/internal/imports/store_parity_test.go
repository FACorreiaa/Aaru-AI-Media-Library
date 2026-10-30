package imports

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// DatabaseTests.importJobRoundTrip (SRV-007): an import job round-trips without losing a field.
func TestAnImportJobRoundTrips(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	user := uuid.New()
	_, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)
	store := NewStore(pool)
	now := time.Now().UTC().Truncate(time.Second)
	job := core.ImportJob{
		ID: uuid.New(), UserID: user, Source: core.SourceLetterboxdCSV, State: core.JobQueued,
		CreatedAt: now, UpdatedAt: now,
	}
	require.NoError(t, store.Insert(ctx, job, nil))
	stored, err := store.Job(ctx, job.ID, user)
	require.NoError(t, err)
	require.NotNil(t, stored)
	assert.Equal(t, job, *stored)

	summary := "4 rows unmatched"
	job.State = core.JobPartial
	job.Stats = core.ImportStats{Created: 3, Updated: 1, Skipped: 2, Unmatched: 4}
	job.ErrorSummary = &summary
	job.UpdatedAt = now.Add(5 * time.Second)
	require.NoError(t, store.Update(ctx, job))
	stored, err = store.Job(ctx, job.ID, user)
	require.NoError(t, err)
	require.NotNil(t, stored)
	assert.Equal(t, job, *stored)
}
