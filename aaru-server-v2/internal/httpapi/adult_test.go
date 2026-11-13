package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/mal"
	"context"
	"fmt"
	"math/rand/v2"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The adult rule (CAT-023, catalog/adult.go) end to end: an import reports an adult row and goes
// on, the MAL read-back leaves an adult entry out, an add by id is refused, and a title already
// in a library still reads.

func TestImportReportsAnAdultRowAndFinishes(t *testing.T) {
	env, fake := newOneFakeEnv(t)
	ctx := context.Background()
	base := 1_000_000 + rand.IntN(8_000_000) // test data
	safe, adult := fmt.Sprint(base), fmt.Sprint(base+1)
	fake.stubTitle(malAnime(safe))
	marked := malAnime(adult)
	marked.Hit.Adult = true
	fake.stubTitle(marked)

	svc := env.server.Imports
	name := "animelist.xml"
	job, err := svc.CreateCSVImport(ctx, env.user, core.SourceMALXML, &name, malExport([]string{safe, adult}))
	require.NoError(t, err)
	worked, err := svc.RunNext(ctx, &env.user)
	require.NoError(t, err)
	assert.True(t, worked)

	planned, rows, err := svc.Detail(ctx, job.ID, env.user)
	require.NoError(t, err)
	assert.Equal(t, core.JobPlanned, planned.State, "one adult row never fails the job")
	assert.Equal(t, 1, planned.Stats.Created)
	assert.Equal(t, 1, planned.Stats.Unmatched, "the adult row is counted, not lost")
	require.Len(t, rows, 2)
	assert.Equal(t, imports.OutcomeCreate, rows[0].Outcome)
	assert.Equal(t, imports.OutcomeUnmatched, rows[1].Outcome)
	require.NotNil(t, rows[1].Reason)
	assert.Equal(t, catalog.AdultReason, *rows[1].Reason)
	assert.Nil(t, rows[1].TitleID)

	applied, err := svc.Apply(ctx, job.ID, env.user)
	require.NoError(t, err)
	assert.Equal(t, 1, applied.Stats.Created)
	assert.Len(t, env.syncItems(), 1)
	var held int
	require.NoError(t, env.pool.QueryRow(ctx, `SELECT count(*) FROM titles WHERE mal = $1`, adult).Scan(&held))
	assert.Zero(t, held, "no title was made of it")
}

func TestAdultTitleIsNotAddedByIDAndOneAlreadyHeldStillReads(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	year := 2021
	fresh, held := env.fake.uniqueID(""), env.fake.uniqueID("")
	for _, id := range []string{fresh, held} {
		env.fake.stubTitle(catalog.Record{Hit: catalog.Hit{
			Type: core.MediaMovie, Title: "Adult " + id, Year: &year, IDs: core.ExternalIDs{TMDB: id}, Adult: true,
		}})
	}
	ref := func(id string) map[string]any {
		return map[string]any{"mediaRef": map[string]any{"type": "movie", "ids": map[string]string{"tmdb": id}}}
	}
	rec := env.send(http.MethodPost, "/v1/library/items", ref(fresh))
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, rec.Body.String())
	assert.Contains(t, rec.Body.String(), `"unresolvable"`)
	assert.Empty(t, env.syncItems())

	// A title that was in the catalog before the rule: its library row is added to, read and kept.
	title := core.Title{ID: uuid.New(), Type: core.MediaMovie, Title: "Adult " + held, Year: &year, IDs: core.ExternalIDs{TMDB: held}}
	require.NoError(t, env.server.Catalog.Store.Insert(ctx, title, nil, nil, nil))
	item := env.addBody(ref(held))
	items := env.syncItems()
	require.Len(t, items, 1)
	assert.Equal(t, http.StatusOK, env.send(http.MethodGet, "/v1/library/items/"+item, nil).Code)
	assert.Equal(t, http.StatusOK, env.send(http.MethodGet, "/v1/titles/"+title.ID.String(), nil).Code)
}

func TestMALReadBackLeavesAnAdultEntryOut(t *testing.T) {
	env := newMALEnv(t)
	safe, adult := malUniqueID(), malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {safe}, 2: {adult}})
	now := time.Now()
	marked := malEntry(adult, "watching", 2, 0, now.Add(time.Minute))
	marked["node"].(map[string]any)["nsfw"] = "black"
	env.mal.setList(malEntry(safe, "watching", 1, 0, now.Add(time.Minute)), marked)

	assert.Equal(t, 1, env.pull(now, true), "the read goes on past the adult entry")
	assert.Equal(t, []int{1}, env.watchedEpisodes(item), "nothing of the adult entry is merged")

	planned, err := env.server.Imports.ApplyFromMAL(context.Background(),
		[]imports.Row{mal.RowOf(mal.ListEntry{
			Node:       mal.Node{ID: 1, Title: "Adult", NSFW: &[]string{"black"}[0]},
			ListStatus: mal.ListStatusEntry{Status: &[]string{"completed"}[0], UpdatedAt: now},
		})}, env.user)
	require.NoError(t, err)
	require.Len(t, planned, 1)
	assert.Equal(t, imports.OutcomeUnmatched, planned[0].Outcome, "reported, as any row with no title is")
	require.NotNil(t, planned[0].Reason)
	assert.Equal(t, catalog.AdultReason, *planned[0].Reason)
	env.disconnectMAL()
}
