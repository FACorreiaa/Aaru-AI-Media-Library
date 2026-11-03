package httpapi

import (
	"aaru-go-api/internal/imports"
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Go audit REL-001: a job that panics, or that the process dies under, fails through its attempts
// instead of being leased again forever.

func TestImportPanicFailsTheJobAfterItsAttempts(t *testing.T) {
	env := newLibEnv(t)
	isbn := importISBN13()
	env.importBook("Dune", isbn, 1965)
	env.fake.mu.Lock()
	env.fake.panicISBN = isbn
	env.fake.mu.Unlock()
	csv := "Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year\n" +
		`1,Dune,Frank Herbert,"=""` + isbn + `""",4,read,read,1965`
	id := env.uploadCSV(csv, "goodreads")
	ctx := context.Background()
	for attempt := 1; attempt <= imports.MaxAttempts; attempt++ {
		worked, err := env.server.Imports.RunNext(ctx, &env.user)
		require.NoError(t, err, "attempt %d", attempt)
		require.True(t, worked, "attempt %d", attempt)
		// Skip the retry's backoff.
		_, err = env.pool.Exec(ctx, `UPDATE import_jobs SET locked_until = NULL WHERE state = 'queued'`)
		require.NoError(t, err)
	}
	worked, err := env.server.Imports.RunNext(ctx, &env.user)
	require.NoError(t, err)
	assert.False(t, worked)
	job, _ := env.importDetail(id)
	assert.Equal(t, "failed", job["state"])
	assert.Contains(t, job["errorSummary"], "panic")
}

func TestImportExpiredOnItsLastAttemptFailsInsteadOfReleasing(t *testing.T) {
	env := newLibEnv(t)
	isbn := importISBN13()
	env.importBook("Dune", isbn, 1965)
	csv := "Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year\n" +
		`1,Dune,Frank Herbert,"=""` + isbn + `""",4,read,read,1965`
	id := env.uploadCSV(csv, "goodreads")
	ctx := context.Background()
	// The process died under the last attempt (an OOM kill): running, lease run out.
	_, err := env.pool.Exec(ctx, `UPDATE import_jobs SET state = 'running', attempts = $1,
		locked_until = now() - interval '1 minute'`, imports.MaxAttempts)
	require.NoError(t, err)
	worked, err := env.server.Imports.RunNext(ctx, &env.user)
	require.NoError(t, err)
	assert.False(t, worked, "never leased again")
	job, _ := env.importDetail(id)
	assert.Equal(t, "failed", job["state"])
	assert.Equal(t, imports.ExpiredSummary, job["errorSummary"])

	// One with attempts left is still taken over.
	other := env.uploadCSV(csv, "goodreads")
	_, err = env.pool.Exec(ctx, `UPDATE import_jobs SET state = 'running', attempts = 1,
		locked_until = now() - interval '1 minute' WHERE state = 'queued'`)
	require.NoError(t, err)
	planned, _ := env.planJob(other)
	assert.Equal(t, "planned", planned["state"])
}
