package httpapi

import (
	"context"
	"net/http"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// DB-003: an approval locks the job, checks its state again and writes the library and the plan in
// one transaction, so a double tap or a client retry applies once.

// applyTwice sends two approvals of one job at once and returns their status codes, sorted.
func applyTwice(e *libEnv, id string) []int {
	e.t.Helper()
	var wg sync.WaitGroup
	codes := make([]int, 2)
	start := make(chan struct{})
	for i := range codes {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			codes[i] = e.send(http.MethodPost, "/v1/imports/"+id+"/apply", nil).Code
		}()
	}
	close(start)
	wg.Wait()
	sort.Ints(codes)
	return codes
}

func TestImportApplyConcurrentAppliesOnce(t *testing.T) {
	env := newLibEnv(t)
	isbn := importISBN13()
	env.importBook("Dune", isbn, 1965)
	// In the library already, unrated: the import is an update, which no unique key would stop twice.
	env.addBody(map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"isbn": isbn}}, "status": "finished"})
	csv := "Title,Author,ISBN13,My Rating,Exclusive Shelf\n" + `Dune,Frank Herbert,"=""` + isbn + `""",4,read`
	id := env.uploadCSV(csv, "goodreads")
	job, _ := env.planJob(id)
	require.Equal(t, "planned", job["state"])

	assert.Equal(t, []int{http.StatusOK, http.StatusConflict}, applyTwice(env, id))
	var actions int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM actions WHERE user_id = $1 AND kind = 'import'`, env.user).Scan(&actions))
	assert.Equal(t, 1, actions, "one journaled action")
	assert.InDelta(t, 8, env.syncItem("Dune")["rating"], 0)
	fetched, _ := env.importDetail(id)
	assert.Equal(t, "succeeded", fetched["state"])
	assert.NotNil(t, fetched["actionId"])
}

func TestListenImportApplyConcurrentAppliesOnce(t *testing.T) {
	e := newLibEnv(t)
	file := listenImpSpotifyFile(t,
		listenImpPlay{"Airbag", listenImpEnded, 240_000},
		listenImpPlay{"Paranoid Android", listenImpEnded.Add(400 * time.Second), 383_000},
	)
	created := listenImpUpload(e, file, "auto")
	require.Equal(t, http.StatusAccepted, created.status, string(created.body))
	id := created.json(t)["id"].(string)
	require.Equal(t, "planned", listenImpPlan(e, id)["state"])

	assert.Equal(t, []int{http.StatusOK, http.StatusConflict}, applyTwice(e, id))
	assert.Len(t, listenImpLog(e), 2)
	job, _ := e.importDetail(id)
	assert.InDelta(t, 2, listenImpStats(t, job)["created"], 0, "the second approval does not overwrite the counts")
}

// DB-004: the quota is counted and the capture inserted under one per-user lock, so parallel
// captures from one account cannot all pass the count.
func TestCaptureParallelAccountGetsExactlyThirtyADay(t *testing.T) {
	env := newCaptureEnv(t, nil, nil)
	tmdb := env.captureFilm("Race " + uuid.NewString())
	link := map[string]any{"url": "https://www.themoviedb.org/movie/" + tmdb}
	var wg sync.WaitGroup
	codes := make([]int, 40)
	start := make(chan struct{})
	for i := range codes {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			codes[i] = env.send(http.MethodPost, "/v1/imports/capture", link).Code
		}()
	}
	close(start)
	wg.Wait()
	accepted, refused := 0, 0
	for _, c := range codes {
		switch c {
		case http.StatusAccepted:
			accepted++
		case http.StatusTooManyRequests:
			refused++
		}
	}
	assert.Equal(t, 30, accepted, codes)
	assert.Equal(t, 10, refused, codes)
	var jobs int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM import_jobs WHERE user_id = $1 AND source = 'capture'`, env.user).Scan(&jobs))
	assert.Equal(t, 30, jobs)
}
