package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ImportFlowTests, ImportResolveTests, ImportOutageTests and ImportSpeedTests: upload, plan in the
// worker, approve, undo; leases; triage; AniList outages; batching and progress.

// importFake is the library fake with call counts, a switchable failure and AniList's MAL batch.
type importFake struct {
	*libraryFake
	mu    sync.Mutex
	calls map[string]int
	err   error
}

func newImportFake() *importFake {
	return &importFake{libraryFake: &libraryFake{episodes: map[string]catalog.Episodes{}}, calls: map[string]int{}}
}

func (f *importFake) count(name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls[name]++
	return f.err
}

func (f *importFake) callCount(name string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls[name]
}

func (f *importFake) fail(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *importFake) Search(ctx context.Context, q string, t core.MediaType) ([]catalog.Hit, error) {
	if err := f.count("search"); err != nil {
		return nil, err
	}
	return f.libraryFake.Search(ctx, q, t)
}

func (f *importFake) Hydrate(ctx context.Context, ids core.ExternalIDs, t core.MediaType) (*catalog.Record, error) {
	if err := f.count("hydrate"); err != nil {
		return nil, err
	}
	return f.libraryFake.Hydrate(ctx, ids, t)
}

func (f *importFake) Episodes(ctx context.Context, ids core.ExternalIDs) (*catalog.Episodes, error) {
	if err := f.count("episodes"); err != nil {
		return nil, err
	}
	return f.libraryFake.Episodes(ctx, ids)
}

func (f *importFake) HydrateMAL(_ context.Context, malIDs []string, t core.MediaType) (map[string]catalog.Record, error) {
	if err := f.count("hydrateMAL"); err != nil {
		return nil, err
	}
	f.libraryFake.mu.Lock()
	defer f.libraryFake.mu.Unlock()
	out := map[string]catalog.Record{}
	for _, id := range malIDs {
		for _, r := range f.titles {
			if r.Hit.IDs.MAL == id && (r.Hit.Type == core.MediaManga) == (t == core.MediaManga) {
				out[id] = r
				break
			}
		}
	}
	return out, nil
}

// newImportEnv is a library env over these fakes as TMDB, AniList and Open Library.
func newImportEnv(t *testing.T, tmdb, anilist, openLibrary *importFake) *libEnv {
	t.Helper()
	providers := catalog.Providers{TMDB: tmdb, AniList: anilist, OpenLibrary: openLibrary, Music: tmdb}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	user, bearer := h.signIn()
	return &libEnv{harness: h, fake: tmdb.libraryFake, user: user, bearer: bearer}
}

// newOneFakeEnv is newImportEnv with one fake in every role.
func newOneFakeEnv(t *testing.T) (*libEnv, *importFake) {
	f := newImportFake()
	return newImportEnv(t, f, f, f), f
}

func importISBN13() string {
	twelve := fmt.Sprintf("978%09d", rand.IntN(1_000_000_000)) //nolint:gosec // test data
	sum := 0
	for i, r := range twelve {
		d := int(r - '0')
		if i%2 == 1 {
			d *= 3
		}
		sum += d
	}
	return twelve + fmt.Sprint((10-sum%10)%10)
}

func (e *libEnv) importBook(name, isbn string, year int) {
	byline := "An Author"
	e.fake.stubTitle(catalog.Record{Hit: catalog.Hit{
		Type: core.MediaBook, Title: name, Year: &year, Byline: &byline,
		IDs: core.ExternalIDs{ISBN: isbn, OpenLibrary: e.fake.uniqueID("OL")},
	}})
}

func (e *libEnv) uploadCSV(csv, source string) string {
	e.t.Helper()
	return e.uploadJob("/v1/imports/csv?source="+source+"&filename=export.csv", "text/csv", []byte(csv))
}

// planJob runs the worker until this job leaves the queue and returns GET /v1/imports/{id}.
func (e *libEnv) planJob(id string) (map[string]any, []map[string]any) {
	e.t.Helper()
	for range 50 {
		job, _ := e.importDetail(id)
		if s := job["state"]; s != "queued" && s != "running" {
			break
		}
		worked, err := e.server.Imports.RunNext(context.Background(), &e.user)
		require.NoError(e.t, err)
		if !worked {
			break
		}
	}
	return e.importDetail(id)
}

func rowOutcomes(rows []map[string]any) []string {
	out := make([]string, len(rows))
	for i, r := range rows {
		out[i], _ = r["outcome"].(string)
	}
	return out
}

func (e *libEnv) syncItems() []map[string]any {
	e.t.Helper()
	var out []map[string]any
	for _, it := range e.json("GET", "/v1/library/sync", nil)["items"].([]any) {
		out = append(out, it.(map[string]any))
	}
	return out
}

func (e *libEnv) syncItem(title string) map[string]any {
	e.t.Helper()
	for _, it := range e.syncItems() {
		if it["title"].(map[string]any)["title"] == title {
			return it
		}
	}
	return nil
}

// MARK: ImportFlowTests

func TestImportGoodreadsPlanApplyUndo(t *testing.T) {
	env := newLibEnv(t)
	isbn := importISBN13()
	env.importBook("Dune", isbn, 1965)
	shelf := env.fake.uniqueID("shelf")
	csv := "Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year\n" +
		`1,Dune,Frank Herbert,"=""` + isbn + `""",4,read,"` + shelf + `, read",1965` + "\n" +
		`2,A Book Nobody Has,Nobody,"=""""",0,to-read,to-read,1999` + "\n" +
		`3,Dune,Frank Herbert,"=""` + isbn + `""",4,read,read,1965`
	id := env.uploadCSV(csv, "goodreads")

	job, rows := env.planJob(id)
	assert.Equal(t, "planned", job["state"])
	assert.Equal(t, []string{"create", "unmatched", "skip"}, rowOutcomes(rows))
	assert.Equal(t, "A Book Nobody Has", rows[1]["title"])
	assert.NotEmpty(t, rows[1]["reason"])
	assert.Empty(t, env.syncItems(), "nothing is written before approval")

	applied := env.json("POST", "/v1/imports/"+id+"/apply", nil)
	assert.Equal(t, "partial", applied["state"], "one row stayed unmatched")
	assert.InDelta(t, 1, applied["stats"].(map[string]any)["created"], 0)

	items := env.syncItems()
	require.Len(t, items, 1)
	assert.Equal(t, "finished", items[0]["status"])
	assert.InDelta(t, 8, items[0]["rating"], 0)
	found := false
	for _, l := range env.json("GET", "/v1/lists", nil)["items"].([]any) {
		found = found || l.(map[string]any)["name"] == shelf
	}
	assert.True(t, found, "the custom shelf is a list")

	action := env.json("GET", "/v1/actions?limit=1", nil)["items"].([]any)[0].(map[string]any)
	assert.Equal(t, "import", action["kind"])
	assert.True(t, strings.EqualFold(applied["actionId"].(string), action["id"].(string)))
	fetched, _ := env.importDetail(id)
	assert.True(t, strings.EqualFold(fetched["actionId"].(string), action["id"].(string)))
	require.Equal(t, http.StatusOK, env.send("POST", "/v1/actions/"+action["id"].(string)+"/undo", nil).Code)
	assert.Empty(t, env.syncItems(), "one undo removes the whole import")
	assert.Equal(t, http.StatusConflict, env.send("POST", "/v1/imports/"+id+"/apply", nil).Code, "applies once")
}

func TestImportFillsEmptyOnly(t *testing.T) {
	env := newLibEnv(t)
	rated, unrated := importISBN13(), importISBN13()
	env.importBook("Rated", rated, 2000)
	env.importBook("Unrated", unrated, 2001)
	for _, isbn := range []string{rated, unrated} {
		env.addBody(map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"isbn": isbn}}, "status": "finished"})
	}
	ratedID := env.syncItem("Rated")["id"].(string)
	require.Equal(t, http.StatusOK, env.send("PATCH", "/v1/library/items/"+ratedID, map[string]any{"rating": 6}).Code)

	csv := "Title,Author,ISBN13,My Rating,Exclusive Shelf\n" +
		`Rated,A,"=""` + rated + `""",5,read` + "\n" + `Unrated,A,"=""` + unrated + `""",5,read`
	id := env.uploadCSV(csv, "goodreads")
	_, rows := env.planJob(id)
	assert.Equal(t, []string{"skip", "update"}, rowOutcomes(rows))
	env.json("POST", "/v1/imports/"+id+"/apply", nil)
	assert.InDelta(t, 6, env.syncItem("Rated")["rating"], 0, "the library's rating stays")
	assert.InDelta(t, 10, env.syncItem("Unrated")["rating"], 0, "an empty rating is filled")
}

func (e *libEnv) insertEmptyJob(source core.ImportSource) uuid.UUID {
	e.t.Helper()
	epoch := time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)
	job := core.ImportJob{ID: uuid.New(), UserID: e.user, Source: source, State: core.JobQueued, CreatedAt: epoch, UpdatedAt: epoch}
	require.NoError(e.t, e.server.Imports.Store.Insert(context.Background(), job, nil))
	return job.ID
}

// claimUntil leases runnable jobs at now until it gets this one; nil when it never comes.
func (e *libEnv) claimUntil(id uuid.UUID, now time.Time) *imports.ClaimedJob {
	e.t.Helper()
	for {
		claimed, err := e.server.Imports.Store.ClaimNext(context.Background(), now, time.Minute, &e.user)
		require.NoError(e.t, err)
		if claimed == nil || claimed.Job.ID == id {
			return claimed
		}
	}
}

func TestImportExpiredLeaseIsReclaimed(t *testing.T) {
	env := newLibEnv(t)
	id := env.insertEmptyJob(core.SourceGoodreadsCSV)
	start := time.Now().UTC()
	first := env.claimUntil(id, start)
	require.NotNil(t, first)
	assert.Equal(t, 1, first.Attempts)
	still, err := env.server.Imports.Store.ClaimNext(context.Background(), start.Add(30*time.Second), time.Minute, &env.user)
	require.NoError(t, err)
	assert.Nil(t, still, "still leased")
	again := env.claimUntil(id, start.Add(61*time.Second))
	require.NotNil(t, again)
	assert.Equal(t, 2, again.Attempts, "the dead worker's job runs again")
}

func TestImportReleasedJobIsClaimedAgain(t *testing.T) {
	env := newLibEnv(t)
	id := env.insertEmptyJob(core.SourceGoodreadsCSV)
	start := time.Now().UTC()
	first := env.claimUntil(id, start)
	require.NotNil(t, first)
	assert.Equal(t, 1, first.Attempts)
	require.NoError(t, env.server.Imports.Store.Release(context.Background(), id, start))
	again := env.claimUntil(id, start)
	require.NotNil(t, again)
	assert.Equal(t, 1, again.Attempts, "the lease is given back before it runs out")
}

func TestImportFailingJobFails(t *testing.T) {
	env, fake := newOneFakeEnv(t)
	clock := time.Now().UTC()
	env.server.Imports.Now = func() time.Time { return clock }
	csv := "Title,Author,ISBN13,My Rating,Exclusive Shelf\nX,A,\"=\"\"" + importISBN13() + "\"\"\",0,read\n"
	id := env.uploadCSV(csv, "goodreads")
	fake.fail(providerUnavailable("openlibrary"))
	var state any
	for range 60 {
		_, err := env.server.Imports.RunNext(context.Background(), &env.user)
		require.NoError(t, err)
		clock = clock.Add(120 * time.Second)
		job, _ := env.importDetail(id)
		if state = job["state"]; state == "failed" {
			break
		}
	}
	fake.fail(nil)
	job, _ := env.importDetail(id)
	assert.Equal(t, "failed", state)
	assert.Contains(t, job["errorSummary"], "Open Library")
}

func TestImportUploadLimits(t *testing.T) {
	env := newLibEnv(t)
	huge := strings.Repeat("a", imports.MaxUploadBytes+1)
	rec := env.upload("/v1/imports/csv?source=imdb&filename=export.csv", "text/csv", []byte(huge))
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Contains(t, rec.Body.String(), "file_too_large")
	wrong := env.upload("/v1/imports/csv?source=imdb&filename=export.csv", "text/csv", []byte("Title,Author,Exclusive Shelf\nDune,F,read\n"))
	assert.Equal(t, http.StatusUnprocessableEntity, wrong.Code)
	assert.Contains(t, wrong.Body.String(), "IMDb")
}

// MARK: ImportResolveTests (IMP-011)

func (e *libEnv) resolveUpload() (id, meant string) {
	e.t.Helper()
	known := importISBN13()
	meant = importISBN13()
	e.importBook("Dune", known, 1965)
	e.importBook("The Book It Meant", meant, 1999)
	csv := "Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year\n" +
		`1,Dune,Frank Herbert,"=""` + known + `""",4,read,read,1965` + "\n" +
		`2,A Book Nobody Has,Nobody,"=""""",5,read,read,1999`
	id = e.uploadCSV(csv, "goodreads")
	_, rows := e.planJob(id)
	require.Equal(e.t, []string{"create", "unmatched"}, rowOutcomes(rows))
	return id, meant
}

func (e *libEnv) resolveRow(id string, row int, isbn string) *testResponse {
	rec := e.send("POST", fmt.Sprintf("/v1/imports/%s/rows/%d/resolve", id, row),
		map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"isbn": isbn}}})
	return &testResponse{code: rec.Code, body: rec.Body.Bytes()}
}

type testResponse struct {
	code int
	body []byte
}

func TestImportResolveAfterApproval(t *testing.T) {
	env := newLibEnv(t)
	id, isbn := env.resolveUpload()
	assert.Equal(t, "partial", env.json("POST", "/v1/imports/"+id+"/apply", nil)["state"])

	reply := env.resolveRow(id, 1, isbn)
	require.Equal(t, http.StatusOK, reply.code, string(reply.body))
	body := decodeBytes(t, reply.body)
	job := body["job"].(map[string]any)
	assert.Equal(t, "succeeded", job["state"], "nothing is left unmatched")
	assert.InDelta(t, 0, job["stats"].(map[string]any)["unmatched"], 0)
	assert.InDelta(t, 2, job["stats"].(map[string]any)["created"], 0)
	assert.Equal(t, "create", body["row"].(map[string]any)["outcome"])

	item := env.syncItem("The Book It Meant")
	require.NotNil(t, item)
	assert.Equal(t, "finished", item["status"])
	assert.InDelta(t, 10, item["rating"], 0)

	assert.Equal(t, http.StatusConflict, env.resolveRow(id, 1, isbn).code, "matches once")
	assert.Equal(t, http.StatusNotFound, env.resolveRow(id, 7, isbn).code)

	action := env.json("GET", "/v1/actions?limit=1", nil)["items"].([]any)[0].(map[string]any)
	assert.Contains(t, action["summary"], "by hand")
	require.Equal(t, http.StatusOK, env.send("POST", "/v1/actions/"+action["id"].(string)+"/undo", nil).Code)
	assert.Nil(t, env.syncItem("The Book It Meant"), "the pick undoes on its own")
	assert.NotNil(t, env.syncItem("Dune"), "the rest of the import stays")
}

func TestImportResolveBeforeApproval(t *testing.T) {
	env := newLibEnv(t)
	id, isbn := env.resolveUpload()
	reply := env.resolveRow(id, 1, isbn)
	require.Equal(t, http.StatusOK, reply.code, string(reply.body))
	body := decodeBytes(t, reply.body)
	job := body["job"].(map[string]any)
	assert.Equal(t, "planned", job["state"])
	assert.InDelta(t, 0, job["stats"].(map[string]any)["unmatched"], 0)
	assert.Equal(t, "create", body["row"].(map[string]any)["outcome"])
	assert.Nil(t, env.syncItem("The Book It Meant"), "nothing is written before approval")

	applied := env.json("POST", "/v1/imports/"+id+"/apply", nil)
	assert.Equal(t, "succeeded", applied["state"])
	assert.InDelta(t, 2, applied["stats"].(map[string]any)["created"], 0)
	item := env.syncItem("The Book It Meant")
	require.NotNil(t, item)
	assert.Equal(t, "finished", item["status"])
}

func TestImportResolveMergesIntoExisting(t *testing.T) {
	env := newLibEnv(t)
	id, isbn := env.resolveUpload()
	env.addBody(map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"isbn": isbn}}, "status": "wishlist"})
	env.json("POST", "/v1/imports/"+id+"/apply", nil)
	reply := env.resolveRow(id, 1, isbn)
	require.Equal(t, http.StatusOK, reply.code, string(reply.body))
	assert.Equal(t, "update", decodeBytes(t, reply.body)["row"].(map[string]any)["outcome"])
	count := 0
	for _, it := range env.syncItems() {
		if it["title"].(map[string]any)["title"] == "The Book It Meant" {
			count++
		}
	}
	assert.Equal(t, 1, count)
	item := env.syncItem("The Book It Meant")
	assert.Equal(t, "finished", item["status"], "moved forward from plan to read")
	assert.InDelta(t, 10, item["rating"], 0)
}

// MARK: ImportOutageTests and ImportSpeedTests (IMP-017)

// malExport is a MAL export of ids, each a TV entry the user plans to watch.
func malExport(ids []string) string {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0"?><myanimelist>`)
	for _, id := range ids {
		fmt.Fprintf(&b, `<anime>
  <series_animedb_id>%s</series_animedb_id>
  <series_title><![CDATA[Show %s]]></series_title>
  <series_type>TV</series_type>
  <series_episodes>12</series_episodes>
  <my_watched_episodes>0</my_watched_episodes>
  <my_score>0</my_score>
  <my_status>Plan to Watch</my_status>
</anime>`, id, id)
	}
	b.WriteString("</myanimelist>")
	return b.String()
}

func malAnime(mal string) catalog.Record {
	year, runtime := 2020, 24
	status := catalog.StatusEnded
	return catalog.Record{
		Hit: catalog.Hit{
			Type: core.MediaShow, Title: "Show " + mal, Year: &year, IDs: core.ExternalIDs{AniList: "al" + mal, MAL: mal}, IsAnime: true,
		},
		Status: &status, RuntimeMinutes: &runtime,
	}
}

func TestImportPlansAroundAniListOutage(t *testing.T) {
	tmdb, anilist := newImportFake(), newImportFake()
	env := newImportEnv(t, tmdb, anilist, tmdb)
	ctx := context.Background()
	base := 1_000_000 + rand.IntN(8_000_000) //nolint:gosec // test data
	mapped, lonely, tmdbID := fmt.Sprint(base), fmt.Sprint(base+1), fmt.Sprint(base)
	season := 1
	require.NoError(t, env.server.Catalog.Store.UpsertMapping(ctx, catalog.AnimeMapping{
		AniList: fmt.Sprint(base + 5_000_000), MAL: &mapped, TMDB: &tmdbID, TMDBSeason: &season,
	}))
	year, runtime := 2020, 24
	status := catalog.StatusEnded
	tmdb.stubTitle(catalog.Record{
		Hit:    catalog.Hit{Type: core.MediaShow, Title: "Show " + mapped, Year: &year, IDs: core.ExternalIDs{TMDB: tmdbID}, IsAnime: true},
		Status: &status, RuntimeMinutes: &runtime,
	})
	anilist.fail(providerUnauthorized("anilist"))
	svc := env.server.Imports
	name := "animelist.xml"
	job, err := svc.CreateCSVImport(ctx, env.user, core.SourceMALXML, &name, malExport([]string{mapped, lonely}))
	require.NoError(t, err)

	worked, err := svc.RunNext(ctx, &env.user)
	require.NoError(t, err)
	assert.True(t, worked)
	waiting, rows, err := svc.Detail(ctx, job.ID, env.user)
	require.NoError(t, err)
	assert.Equal(t, core.JobQueued, waiting.State, "a first try waits for AniList to come back")
	require.NotNil(t, waiting.ErrorSummary)
	assert.Equal(t, "AniList could not be reached while matching titles.", *waiting.ErrorSummary)

	before := anilist.callCount("hydrate")
	planned, err := svc.Plan(ctx, rows, env.user, true, nil)
	require.NoError(t, err)
	assert.Equal(t, imports.OutcomeCreate, planned[0].Outcome, "a mapped anime resolves through TMDB")
	assert.Equal(t, imports.OutcomeUnmatched, planned[1].Outcome)
	require.NotNil(t, planned[1].Reason)
	assert.Contains(t, *planned[1].Reason, "AniList was not answering")
	assert.Equal(t, before, anilist.callCount("hydrate"), "rows after the failed batch do not ask again")
}

func TestImportMALBatchedWithProgress(t *testing.T) {
	env, fake := newOneFakeEnv(t)
	ctx := context.Background()
	base := 1_000_000 + rand.IntN(8_000_000) //nolint:gosec // test data
	var known []string
	for i := range 59 {
		known = append(known, fmt.Sprint(base+i))
		fake.stubTitle(malAnime(known[i]))
	}
	svc := env.server.Imports
	name := "animelist.xml"
	job, err := svc.CreateCSVImport(ctx, env.user, core.SourceMALXML, &name, malExport(append(known, fmt.Sprint(base+99))))
	require.NoError(t, err)
	assert.Equal(t, 60, job.RowsTotal, "the upload's answer already counts the rows")
	stored, _, err := svc.Detail(ctx, job.ID, env.user)
	require.NoError(t, err)
	assert.Equal(t, 60, stored.RowsTotal)

	worked, err := svc.RunNext(ctx, &env.user)
	require.NoError(t, err)
	assert.True(t, worked)
	planned, rows, err := svc.Detail(ctx, job.ID, env.user)
	require.NoError(t, err)
	assert.Equal(t, core.JobPlanned, planned.State)
	assert.Equal(t, 60, planned.RowsMatched)
	assert.Equal(t, 60, planned.RowsTotal)
	assert.Equal(t, 59, planned.Stats.Created)
	assert.Equal(t, 1, planned.Stats.Unmatched)
	assert.Equal(t, 2, fake.callCount("hydrateMAL"), "60 rows: a chunk of 50 and a chunk of 10")
	assert.Equal(t, 0, fake.callCount("hydrate"), "no per-entry AniList calls")
	for _, row := range rows {
		if row.Outcome != imports.OutcomeCreate {
			continue
		}
		title, err := env.server.Catalog.Store.Title(ctx, *row.TitleID)
		require.NoError(t, err)
		assert.Equal(t, row.Row.IDs.MAL, title.IDs.MAL, "each row keeps its own match")
	}
	assert.Equal(t, imports.OutcomeUnmatched, rows[len(rows)-1].Outcome)
}

func TestImportProgressReports(t *testing.T) {
	env, fake := newOneFakeEnv(t)
	base := 1_000_000 + rand.IntN(8_000_000) //nolint:gosec // test data
	var ids []string
	for i := range 60 {
		ids = append(ids, fmt.Sprint(base+i))
		fake.stubTitle(malAnime(ids[i]))
	}
	parsed, err := imports.Parse(malExport(ids), core.SourceMALXML, nil)
	require.NoError(t, err)
	rows := make([]imports.PlannedRow, len(parsed))
	for i, r := range parsed {
		rows[i] = imports.PlannedRow{Index: i, Row: r, Outcome: imports.OutcomePending}
	}
	var reports []int
	_, err = env.server.Imports.Plan(context.Background(), rows, env.user, false, func(n int) error {
		reports = append(reports, n)
		return nil
	})
	require.NoError(t, err)
	assert.Len(t, reports, 2, "a chunk of 50 and a chunk of 10")
	assert.Equal(t, 60, reports[len(reports)-1])
	assert.IsNonDecreasing(t, reports)
}

func providerUnavailable(name string) error {
	return provider.NewError(name, provider.KindUnavailable)
}

func providerUnauthorized(name string) error {
	return provider.NewError(name, provider.KindUnauthorized)
}

func decodeBytes(t *testing.T, data []byte) map[string]any {
	t.Helper()
	var v map[string]any
	require.NoError(t, json.Unmarshal(data, &v), string(data))
	return v
}
