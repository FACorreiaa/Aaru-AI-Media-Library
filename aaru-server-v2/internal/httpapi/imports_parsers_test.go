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

// Flow tests for the file parsers (upload → plan → apply): GenericImportTests, GoodreadsImportTests,
// CATImportTests, NetflixImportTests, TVTimeImportTests, AnimeListImportTests, MangaImportTests.
// The fake catalog also answers searches by exact query, as FakeCatalog.stubSearch did.

// pzFake is libraryFake plus searches by exact query.
type pzFake struct {
	*libraryFake
	searchMu sync.Mutex
	searches map[string][]catalog.Hit
}

func (f *pzFake) Search(_ context.Context, query string, _ core.MediaType) ([]catalog.Hit, error) {
	f.searchMu.Lock()
	defer f.searchMu.Unlock()
	return f.searches[query], nil
}

func (f *pzFake) SearchMulti(ctx context.Context, query string) ([]catalog.Hit, error) {
	return f.Search(ctx, query, core.MediaMovie)
}

func (f *pzFake) stubSearch(query string, hits ...catalog.Hit) {
	f.searchMu.Lock()
	defer f.searchMu.Unlock()
	f.searches[query] = hits
}

func (f *pzFake) stubEpisodes(tmdb string, episodes catalog.Episodes) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.episodes[tmdb] = episodes
}

type pzEnv struct {
	*libEnv
	search *pzFake
}

func newPzEnv(t *testing.T) *pzEnv {
	t.Helper()
	base := &libraryFake{episodes: map[string]catalog.Episodes{}}
	fake := &pzFake{libraryFake: base, searches: map[string][]catalog.Hit{}}
	providers := catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	user, bearer := h.signIn()
	return &pzEnv{libEnv: &libEnv{harness: h, fake: base, user: user, bearer: bearer}, search: fake}
}

func pzUnique(prefix string) string { return prefix + uuid.NewString()[:8] }

// pzHit stubs a title the fake can hydrate and returns its hit.
func (e *pzEnv) pzHit(mediaType core.MediaType, name string, year int, ids core.ExternalIDs) catalog.Hit {
	if ids.TMDB == "" && ids.AniList == "" && ids.ISBN == "" && ids.OpenLibrary == "" {
		ids.TMDB = e.fake.uniqueID("")
	}
	hit := catalog.Hit{Type: mediaType, Title: name, Year: &year, IDs: ids}
	record := catalog.Record{Hit: hit}
	if mediaType == core.MediaShow {
		record.Status = pzPtr(catalog.StatusReturning)
	}
	e.fake.stubTitle(record)
	return hit
}

func pzPtr[T any](v T) *T { return &v }

// pzUpload posts a text export to /v1/imports/csv.
func (e *pzEnv) pzUpload(text, source, filename, contentType string) *pzReply {
	e.t.Helper()
	rec := e.upload("/v1/imports/csv?source="+source+"&filename="+filename, contentType, []byte(text))
	return &pzReply{code: rec.Code, body: rec.Body.String()}
}

type pzReply struct {
	code int
	body string
}

// pzPlan runs the user's jobs and returns the job's planned rows from the store.
func (e *pzEnv) pzPlan(id string) []imports.PlannedRow {
	e.t.Helper()
	e.runImports()
	rows, err := e.server.Imports.Store.Rows(context.Background(), uuid.MustParse(id))
	require.NoError(e.t, err)
	return rows
}

func pzOutcomes(rows []imports.PlannedRow) []imports.Outcome {
	out := make([]imports.Outcome, len(rows))
	for i, r := range rows {
		out[i] = r.Outcome
	}
	return out
}

func (e *pzEnv) pzApply(id string) {
	e.t.Helper()
	rec := e.send("POST", "/v1/imports/"+id+"/apply", nil)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

type pzItem struct {
	ID         uuid.UUID
	Status     string
	Notes      *string
	IsOwned    bool
	Rating     *float64
	FinishedAt *time.Time
	Chapter    *int
	Volume     *int
}

// pzItemFor is the user's item for a title found by ids, nil when there is none.
func (e *pzEnv) pzItemFor(hit catalog.Hit) *pzItem {
	e.t.Helper()
	title, err := e.server.Catalog.Store.Find(context.Background(), hit.IDs, hit.Type)
	require.NoError(e.t, err)
	if title == nil {
		return nil
	}
	return e.pzItemWhere("li.title_id = $2", title.ID)
}

// pzItemNamed is the user's item for a title by its name.
func (e *pzEnv) pzItemNamed(name string) *pzItem {
	e.t.Helper()
	return e.pzItemWhere("t.title = $2", name)
}

func (e *pzEnv) pzItemWhere(where string, arg any) *pzItem {
	e.t.Helper()
	var it pzItem
	err := e.pool.QueryRow(context.Background(), `SELECT li.id, li.status, li.notes, li.is_owned, li.rating,
		li.finished_at, li.manga_chapter, li.manga_volume
		FROM library_items li JOIN titles t ON t.id = li.title_id WHERE li.user_id = $1 AND `+where, e.user, arg).
		Scan(&it.ID, &it.Status, &it.Notes, &it.IsOwned, &it.Rating, &it.FinishedAt, &it.Chapter, &it.Volume)
	if err != nil {
		return nil
	}
	return &it
}

func (e *pzEnv) pzWatched(item *pzItem) int {
	e.t.Helper()
	return e.watchedCount(item.ID.String())
}

func pzISBN13() string {
	nine := fmt.Sprintf("%09d", rand.IntN(1_000_000_000))
	sum := 0
	for i, r := range nine {
		sum += int(r-'0') * (10 - i)
	}
	check := (11 - sum%11) % 11
	tenth := "X"
	if check < 10 {
		tenth = fmt.Sprint(check)
	}
	return core.NormalizeISBN(nine + tenth)
}

func (e *pzEnv) pzBook(title, isbn string, year int) catalog.Hit {
	byline := "An Author"
	hit := catalog.Hit{
		Type: core.MediaBook, Title: title, Year: &year, Byline: &byline,
		IDs: core.ExternalIDs{ISBN: isbn, OpenLibrary: e.fake.uniqueID("OL")},
	}
	e.fake.stubTitle(catalog.Record{Hit: hit})
	return hit
}

// pzSearchBook is a book Open Library knows by its work id only, found by a title + author search.
func (e *pzEnv) pzSearchBook(title string, year int, byline, query string) catalog.Hit {
	hit := catalog.Hit{
		Type: core.MediaBook, Title: title, Year: &year, Byline: &byline,
		IDs: core.ExternalIDs{OpenLibrary: e.fake.uniqueID("OL")},
	}
	e.fake.stubTitle(catalog.Record{Hit: hit})
	e.search.stubSearch(query, hit)
	return hit
}

func pzJobID(t *testing.T, r *pzReply) string {
	t.Helper()
	require.Equal(t, http.StatusAccepted, r.code, r.body)
	return pzString(t, r.body, "id")
}

func pzString(t *testing.T, body, key string) string {
	t.Helper()
	var m map[string]any
	require.NoError(t, json.Unmarshal([]byte(body), &m))
	s, _ := m[key].(string)
	return s
}

// MARK: GenericImportTests

func TestImportAutoGenericCSV(t *testing.T) {
	env := newPzEnv(t)
	r := env.pzUpload("Title,Year,Type\nArrival,2016,movie\n", "auto", "simkl.csv", "text/csv")
	require.Equal(t, http.StatusAccepted, r.code, r.body)
	assert.Equal(t, "csv", pzString(t, r.body, "source"))
}

// MARK: GoodreadsImportTests

func TestGoodreadsUnknownISBNFallsBackToTitleAndAuthor(t *testing.T) {
	env := newPzEnv(t)
	isbn := pzISBN13()
	env.pzSearchBook("Leviathan Wakes", 2011, "James S. A. Corey", "Leviathan Wakes James S.A. Corey")
	csv := "Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year\n" +
		`1,"Leviathan Wakes (The Expanse, #1)",James S.A. Corey,"=""` + isbn + `""",5,read,read,2011` + "\n"
	id := pzJobID(t, env.pzUpload(csv, "goodreads", "export.csv", "text/csv"))
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate}, pzOutcomes(env.pzPlan(id)))
	env.pzApply(id)
	item := env.pzItemNamed("Leviathan Wakes")
	require.NotNil(t, item)
	assert.Equal(t, "finished", item.Status)
	assert.Equal(t, pzPtr(10.0), item.Rating)
}

func TestGoodreadsYearToleranceNeedsTheAuthor(t *testing.T) {
	env := newPzEnv(t)
	near := pzUnique("Near")
	env.pzSearchBook(near, 2012, "Ann Leckie", near+" Ann Leckie")
	stranger := pzUnique("Stranger")
	env.pzSearchBook(stranger, 2012, "Ann Leckie", stranger+" Someone Else")
	far := pzUnique("Far")
	env.pzSearchBook(far, 2013, "Ann Leckie", far+" Ann Leckie")
	twice := pzUnique("Twice")
	var editions []catalog.Hit
	for _, year := range []int{2010, 2012} {
		byline := "Ann Leckie"
		editions = append(editions, catalog.Hit{
			Type: core.MediaBook, Title: twice, Year: &year, Byline: &byline,
			IDs: core.ExternalIDs{OpenLibrary: env.fake.uniqueID("OL")},
		})
	}
	env.search.stubSearch(twice+" Ann Leckie", editions...)
	csv := "Title,Author,Exclusive Shelf,Original Publication Year\n" +
		near + ",Ann Leckie,read,2011\n" + stranger + ",Someone Else,read,2011\n" +
		far + ",Ann Leckie,read,2011\n" + twice + ",Ann Leckie,read,2011\n"
	id := pzJobID(t, env.pzUpload(csv, "goodreads", "export.csv", "text/csv"))
	rows := env.pzPlan(id)
	assert.Equal(t, []imports.Outcome{
		imports.OutcomeCreate, imports.OutcomeUnmatched, imports.OutcomeUnmatched,
		imports.OutcomeUnmatched,
	}, pzOutcomes(rows))
	require.NotNil(t, rows[3].Reason)
	assert.Contains(t, *rows[3].Reason, "More than one", "two hits one year off are never a guess")
}

func TestGoodreadsDidNotFinishIsDropped(t *testing.T) {
	env := newPzEnv(t)
	isbn := pzISBN13()
	title := pzUnique("Gave Up")
	env.pzBook(title, isbn, 2001)
	csv := "Title,Author,ISBN13,Exclusive Shelf,Bookshelves\n" + title + `,An Author,"=""` + isbn + `""",DNF,dnf` + "\n"
	id := pzJobID(t, env.pzUpload(csv, "goodreads", "export.csv", "text/csv"))
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate}, pzOutcomes(env.pzPlan(id)))
	env.pzApply(id)
	assert.Equal(t, "dropped", env.pzItemNamed(title).Status)
	var lists int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM lists WHERE user_id = $1 AND name = 'dnf'`, env.user).Scan(&lists))
	assert.Equal(t, 1, lists)
}

func TestGoodreadsReviewAndOwnedFillEmptyOnly(t *testing.T) {
	env := newPzEnv(t)
	fresh, noted, bare := pzISBN13(), pzISBN13(), pzISBN13()
	names := [3]string{pzUnique("Fresh"), pzUnique("Noted"), pzUnique("Bare")}
	env.pzBook(names[0], fresh, 2001)
	env.pzBook(names[1], noted, 2002)
	env.pzBook(names[2], bare, 2003)
	for _, isbn := range []string{noted, bare} {
		env.addBody(map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"isbn": isbn}}, "status": "finished"})
	}
	notedItem := env.pzItemNamed(names[1])
	require.NotNil(t, notedItem)
	env.json("PATCH", "/v1/library/items/"+strings.ToUpper(notedItem.ID.String()), map[string]any{"notes": "Mine"})

	csv := "Title,Author,ISBN13,Exclusive Shelf,My Review,Private Notes,Owned Copies\n" +
		names[0] + `,A,"=""` + fresh + `""",read,"Loved it.<br/><br/>Tom &amp; Jerry",,1` + "\n" +
		names[1] + `,A,"=""` + noted + `""",read,Theirs,,0` + "\n" +
		names[2] + `,A,"=""` + bare + `""",read,,Only private,2` + "\n"
	id := pzJobID(t, env.pzUpload(csv, "goodreads", "export.csv", "text/csv"))
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeSkip, imports.OutcomeUpdate}, pzOutcomes(env.pzPlan(id)))
	env.pzApply(id)
	first, second, third := env.pzItemNamed(names[0]), env.pzItemNamed(names[1]), env.pzItemNamed(names[2])
	assert.Equal(t, pzPtr("Loved it.\n\nTom & Jerry"), first.Notes)
	assert.True(t, first.IsOwned)
	assert.Equal(t, pzPtr("Mine"), second.Notes, "notes the library has stay")
	assert.False(t, second.IsOwned, "0 owned copies sets nothing")
	assert.Equal(t, pzPtr("Only private"), third.Notes, "private notes when there is no review")
	assert.True(t, third.IsOwned)
}

// MARK: CATImportTests

func pzCATCalendar(summaries ...string) string {
	parts := []string{"BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CAT//EN"}
	for i, s := range summaries {
		parts = append(parts, fmt.Sprintf("BEGIN:VEVENT\r\nUID:%d@pogdesign\r\nDTSTART;VALUE=DATE:20261021\r\nSUMMARY:%s\r\nEND:VEVENT", i, s))
	}
	parts = append(parts, "END:VCALENDAR")
	return strings.Join(parts, "\r\n") + "\r\n"
}

func TestCATMatching(t *testing.T) {
	env := newPzEnv(t)
	unique, shared, owned, missing := pzUnique("Unique"), pzUnique("Shared"), pzUnique("Owned"), pzUnique("Missing")
	uniqueHit := env.pzHit(core.MediaShow, unique, 2020, core.ExternalIDs{})
	env.search.stubSearch(unique, uniqueHit)
	env.search.stubSearch(shared, env.pzHit(core.MediaShow, shared, 2005, core.ExternalIDs{}),
		env.pzHit(core.MediaShow, shared, 2019, core.ExternalIDs{}))
	ownedHit := env.pzHit(core.MediaShow, owned, 2020, core.ExternalIDs{})
	env.search.stubSearch(owned, ownedHit)
	env.add("show", ownedHit.IDs.TMDB, "in_progress")

	job, err := env.server.Imports.CreateCATImport(context.Background(), env.user, strings.Join([]string{unique, shared, owned, missing}, "\n"))
	require.NoError(t, err)
	assert.Equal(t, core.SourceCATList, job.Source)
	rows := env.pzPlan(job.ID.String())
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeUnmatched, imports.OutcomeSkip, imports.OutcomeUnmatched}, pzOutcomes(rows))
	assert.Equal(t, pzPtr("Several shows are called “"+shared+"”. Pick the right one by hand."), rows[1].Reason)
	env.pzApply(strings.ToUpper(job.ID.String()))

	item := env.pzItemFor(uniqueHit)
	require.NotNil(t, item)
	assert.Equal(t, "wishlist", item.Status)
	assert.Equal(t, 0, env.pzWatched(item))
	assert.Equal(t, "in_progress", env.pzItemFor(ownedHit).Status)
}

func TestCATAiringTiebreak(t *testing.T) {
	env := newPzEnv(t)
	remade, bothAir := pzUnique("Remade"), pzUnique("BothAir")
	episodes := func(hit catalog.Hit, day string) {
		status := catalog.StatusReturning
		env.search.stubEpisodes(hit.IDs.TMDB, catalog.Episodes{Status: &status, Episodes: []catalog.Episode{
			{Season: 2, Episode: 3, AirsAt: catalog.ParseDay(&day)},
		}})
	}
	original, remake := env.pzHit(core.MediaShow, remade, 2005, core.ExternalIDs{}), env.pzHit(core.MediaShow, remade, 2025, core.ExternalIDs{})
	episodes(original, "2006-03-01")
	episodes(remake, "2026-10-20")
	env.search.stubSearch(remade, original, remake)
	first, second := env.pzHit(core.MediaShow, bothAir, 2010, core.ExternalIDs{}), env.pzHit(core.MediaShow, bothAir, 2024, core.ExternalIDs{})
	episodes(first, "2026-10-21")
	episodes(second, "2026-10-22")
	env.search.stubSearch(bothAir, first, second)

	job, err := env.server.Imports.CreateCATImport(context.Background(), env.user, pzCATCalendar(remade+" S02E03", bothAir+" S02E03"))
	require.NoError(t, err)
	rows := env.pzPlan(job.ID.String())
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeUnmatched}, pzOutcomes(rows))
	title, err := env.server.Catalog.Store.Find(context.Background(), remake.IDs, core.MediaShow)
	require.NoError(t, err)
	require.NotNil(t, title)
	require.NotNil(t, rows[0].TitleID)
	assert.Equal(t, title.ID, *rows[0].TitleID)
	assert.Equal(t, pzPtr("Several shows are called “"+bothAir+"”. Pick the right one by hand."), rows[1].Reason)
}

func TestCATRoute(t *testing.T) {
	env := newPzEnv(t)
	post := func(text, contentType string) string {
		rec := env.upload("/v1/imports/cat", contentType, []byte(text))
		require.Equal(t, http.StatusAccepted, rec.Code, rec.Body.String())
		return pzString(t, rec.Body.String(), "source")
	}
	assert.Equal(t, "cat_list", post("Severance\nThe Bear", "text/plain"))
	assert.Equal(t, "cat_ics", post(pzCATCalendar("Severance: S02E01"), "text/calendar"))
}

// pzCATTransport answers every request with the current body and records the URLs asked for.
type pzCATTransport struct {
	mu   sync.Mutex
	urls []string
	body string
	code int
}

func (s *pzCATTransport) Send(_ context.Context, req provider.Request) (*provider.Response, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.urls = append(s.urls, req.URL)
	return &provider.Response{Status: s.code, Body: []byte(s.body)}, nil
}

func (s *pzCATTransport) respond(code int, body string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.code, s.body = code, body
}

func pzCATFeed(transport provider.Transport) *imports.CATCalendarFeed {
	client := provider.NewClient("pogdesign", transport, provider.NewPacer(1000, 100))
	client.Sleep = func(context.Context, time.Duration) error { return nil }
	return &imports.CATCalendarFeed{Client: client}
}

func TestCATFeed(t *testing.T) {
	env := newPzEnv(t)
	key := pzUnique("catkey")
	transport := &pzCATTransport{}
	transport.respond(200, pzCATCalendar("Severance: S02E01", "Severance: S02E02", "The Bear: S04E01"))
	env.server.Imports.CATFeed = pzCATFeed(transport)

	rec := env.send("POST", "/v1/imports/cat/feed", map[string]any{"url": "https://www.pogdesign.co.uk/cat/download_ics/" + key})
	require.Equal(t, http.StatusAccepted, rec.Code, rec.Body.String())
	job := decode[map[string]any](t, rec)
	assert.Equal(t, "cat_ics", job["source"])
	assert.Nil(t, job["filename"])
	assert.Equal(t, []string{"https://www.pogdesign.co.uk/cat/generate_ics/" + key}, transport.urls)
	rows, err := env.server.Imports.Store.Rows(context.Background(), uuid.MustParse(job["id"].(string)))
	require.NoError(t, err)
	var titles []string
	for _, r := range rows {
		titles = append(titles, r.Row.Title)
	}
	assert.Equal(t, []string{"Severance", "The Bear"}, titles)
	var mentions int
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT ((SELECT count(*) FROM import_rows WHERE row::text LIKE $1)
		+ (SELECT count(*) FROM import_jobs WHERE to_jsonb(import_jobs)::text LIKE $1))::int`, "%"+key+"%").Scan(&mentions))
	assert.Zero(t, mentions, "the link's key is never stored")

	transport.respond(200, "<html>Log in</html>")
	rec = env.send("POST", "/v1/imports/cat/feed", map[string]any{"url": "https://www.pogdesign.co.uk/cat/download_ics/" + key})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, "a page that is not a calendar")
	body := decode[map[string]any](t, rec)
	assert.Equal(t, "That link didn't return a CAT calendar. Copy the iCal link from CAT again.", body["message"])

	transport.respond(404, "")
	rec = env.send("POST", "/v1/imports/cat/feed", map[string]any{"url": "https://www.pogdesign.co.uk/cat/download_ics/" + key})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, "an unknown key")

	transport.respond(200, "BEGIN:VCALENDAR\r\n"+strings.Repeat("x", imports.MaxUploadBytes))
	rec = env.send("POST", "/v1/imports/cat/feed", map[string]any{"url": "https://www.pogdesign.co.uk/cat/download_ics/" + key})
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "file_too_large", decode[map[string]any](t, rec)["code"])

	rec = env.send("POST", "/v1/imports/cat/feed", map[string]any{"url": "https://evil.example/cat/download_ics/" + key})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Len(t, transport.urls, 4, "a link that is not CAT's is refused before any request")

	env.server.Imports.CATFeed = nil
	rec = env.send("POST", "/v1/imports/cat/feed", map[string]any{"url": "https://www.pogdesign.co.uk/cat/download_ics/" + key})
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "cat_unavailable", decode[map[string]any](t, rec)["code"])
}

// MARK: NetflixImportTests

func TestNetflixMatching(t *testing.T) {
	env := newPzEnv(t)
	show, film, remade, later := pzUnique("Show"), pzUnique("Film"), pzUnique("Remade"), pzUnique("Later")
	showHit := env.pzHit(core.MediaShow, show, 2015, core.ExternalIDs{})
	name := func(s string) *string { return &s }
	status := catalog.StatusReturning
	env.search.stubEpisodes(showHit.IDs.TMDB, catalog.Episodes{Status: &status, Episodes: []catalog.Episode{
		{Season: 1, Episode: 1, Name: name("Arrival")},
		{Season: 1, Episode: 2, Name: name("Departure")},
		{Season: 2, Episode: 1, Name: name("Return")},
	}})
	env.search.stubSearch(show, showHit)
	filmHit := env.pzHit(core.MediaMovie, film, 2019, core.ExternalIDs{})
	env.search.stubSearch(film, filmHit)
	env.search.stubSearch(remade, env.pzHit(core.MediaMovie, remade, 1990, core.ExternalIDs{}),
		env.pzHit(core.MediaMovie, remade, 2016, core.ExternalIDs{}))
	original := env.pzHit(core.MediaMovie, later, 2001, core.ExternalIDs{})
	env.search.stubSearch(later, original, env.pzHit(core.MediaMovie, later, 2024, core.ExternalIDs{}))

	job, err := env.server.Imports.CreateCSVImport(context.Background(), env.user, core.SourceNetflixCSV, nil, "Title,Date\n"+
		`"`+show+`: Season 1: Arrival",1/2/22`+"\n"+
		`"`+show+`: Season 1: Return",1/3/22`+"\n"+
		`"`+show+`: Season 1: Not On TMDB",1/4/22`+"\n"+
		`"`+film+`",5/6/22`+"\n"+`"`+remade+`",5/7/22`+"\n"+`"`+later+`",5/8/22`+"\n")
	require.NoError(t, err)
	rows := env.pzPlan(job.ID.String())
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeCreate, imports.OutcomeUnmatched, imports.OutcomeCreate}, pzOutcomes(rows))
	assert.Equal(t, pzPtr("Several films are called “"+remade+"”. Pick the right one by hand."), rows[2].Reason)
	assert.Nil(t, rows[0].Row.NamedEpisodes)
	assert.Equal(t, []core.EpisodeKey{{Season: 1, Episode: 1}, {Season: 2, Episode: 1}}, rows[0].Row.Watched)
	env.pzApply(strings.ToUpper(job.ID.String()))

	showItem := env.pzItemFor(showHit)
	require.NotNil(t, showItem)
	assert.Equal(t, "in_progress", showItem.Status)
	assert.Equal(t, 2, env.pzWatched(showItem))
	assert.Equal(t, "finished", env.pzItemFor(filmHit).Status)
	assert.NotNil(t, env.pzItemFor(original), "the 2024 remake came out after it was watched in 2022")
}

// MARK: TVTimeImportTests

func pzNumericID() string { return fmt.Sprint(10_000_000 + rand.IntN(90_000_000)) }

func (e *pzEnv) pzRunTVTime(text string) []imports.PlannedRow {
	e.t.Helper()
	filename := "tvtime.csv"
	job, err := e.server.Imports.CreateCSVImport(context.Background(), e.user, core.SourceTVTimeCSV, &filename, text)
	require.NoError(e.t, err)
	rows := e.pzPlan(job.ID.String())
	e.pzApply(strings.ToUpper(job.ID.String()))
	return rows
}

const (
	pzSeriesEpisodesHeader = "series_tvdb_id,series_imdb_id,series_uuid,title,season,episode,tvdb_id," +
		"is_watched,watched_at,rewatch_count,special"
	pzSeriesHeader = "uuid,tvdb_id,imdb_id,title,status,created_at"
	pzMoviesHeader = "uuid,tvdb_id,imdb_id,title,year,created_at,watched_at,is_watched,rewatch_count"
)

func TestTVTimeMatching(t *testing.T) {
	env := newPzEnv(t)
	known, legacy, lost := pzUnique("Known"), pzUnique("Legacy"), pzUnique("Lost")
	knownTVDB, legacyTVDB, lostTVDB := pzNumericID(), pzNumericID(), pzNumericID()
	knownHit := env.pzHit(core.MediaShow, known, 2015, core.ExternalIDs{TVDB: knownTVDB})
	// TMDB knows this show under another TVDB id than the one TV Time kept.
	legacyHit := env.pzHit(core.MediaShow, legacy, 2010, core.ExternalIDs{TVDB: pzNumericID()})
	env.search.stubSearch(legacy, legacyHit)

	episodes := pzSeriesEpisodesHeader + "\n" +
		knownTVDB + ",,u-1," + known + ",1,1,1,true,2020-01-01 20:00:00,0,false\n" +
		knownTVDB + ",,u-1," + known + ",1,2,2,true,2020-01-02 20:00:00,0,false\n" +
		legacyTVDB + ",,u-2," + legacy + ",1,1,3,true,2020-01-03 20:00:00,0,false\n" +
		lostTVDB + ",,u-3," + lost + ",1,1,4,true,2020-01-04 20:00:00,0,false\n"
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeCreate, imports.OutcomeUnmatched},
		pzOutcomes(env.pzRunTVTime(episodes)))
	knownItem := env.pzItemFor(knownHit)
	require.NotNil(t, knownItem)
	assert.Equal(t, "in_progress", knownItem.Status)
	assert.Equal(t, 2, env.pzWatched(knownItem))
	assert.NotNil(t, env.pzItemFor(legacyHit))

	assert.Equal(t, []imports.Outcome{imports.OutcomeSkip, imports.OutcomeSkip, imports.OutcomeUnmatched},
		pzOutcomes(env.pzRunTVTime(episodes)), "re-running creates nothing new")

	// The series file says the show was never started: an import never moves it back.
	series := env.pzRunTVTime(pzSeriesHeader + "\nu-1," + knownTVDB + ",," + known + ",not_started_yet,2019-01-01T00:00:00Z\n")
	assert.Equal(t, []imports.Outcome{imports.OutcomeSkip}, pzOutcomes(series))
	assert.Equal(t, "in_progress", env.pzItemFor(knownHit).Status)
}

func TestTVTimeMovieMatching(t *testing.T) {
	env := newPzEnv(t)
	byID, byName := pzUnique("ById"), pzUnique("ByName")
	imdb := "tt" + pzNumericID()
	idHit := env.pzHit(core.MediaMovie, byID, 2020, core.ExternalIDs{IMDB: imdb})
	nameHit := env.pzHit(core.MediaMovie, byName, 2017, core.ExternalIDs{})
	env.search.stubSearch(byName, nameHit)
	rows := env.pzRunTVTime(pzMoviesHeader + "\n" +
		"u-1," + pzNumericID() + "," + imdb + "," + byID + ",2020,2022-03-18T00:03:26Z,2022-03-18T00:03:26Z,true,0\n" +
		"u-2," + pzNumericID() + ",-1," + byName + ",2017,2019-09-10T08:01:29Z,,false,0\n")
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeCreate}, pzOutcomes(rows))
	idItem := env.pzItemFor(idHit)
	require.NotNil(t, idItem)
	assert.Equal(t, "finished", idItem.Status)
	require.NotNil(t, idItem.FinishedAt)
	assert.True(t, imports.TVTimeDate(pzPtr("2022-03-18T00:03:26Z")).Equal(*idItem.FinishedAt))
	assert.Equal(t, "wishlist", env.pzItemFor(nameHit).Status)
}

// MARK: AnimeListImportTests, MangaImportTests

const pzMALAnime = `<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
  <myinfo><user_name>someone</user_name></myinfo>
  <anime>
    <series_animedb_id>52991</series_animedb_id>
    <series_title><![CDATA[Sousou no Frieren]]></series_title>
    <series_type>TV</series_type>
    <series_episodes>28</series_episodes>
    <my_watched_episodes>12</my_watched_episodes>
    <my_score>9</my_score>
    <my_status>Watching</my_status>
    <my_finish_date>0000-00-00</my_finish_date>
  </anime>
</myanimelist>`

const pzMALManga = `<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
  <myinfo><user_name>someone</user_name><user_export_type>2</user_export_type></myinfo>
  <manga>
    <manga_mangadb_id>2</manga_mangadb_id>
    <manga_title><![CDATA[Berserk]]></manga_title>
    <manga_volumes>0</manga_volumes>
    <manga_chapters>0</manga_chapters>
    <my_read_volumes>12</my_read_volumes>
    <my_read_chapters>112</my_read_chapters>
    <my_score>10</my_score>
    <my_status>Reading</my_status>
    <my_finish_date>0000-00-00</my_finish_date>
  </manga>
</myanimelist>`

func TestMALUploadFlow(t *testing.T) {
	env := newPzEnv(t)
	mal := fmt.Sprint(100_000 + rand.IntN(900_000))
	runtime := 24
	status := catalog.StatusEnded
	env.fake.stubTitle(catalog.Record{
		Hit:    catalog.Hit{Type: core.MediaShow, Title: "Frieren", Year: pzPtr(2023), IDs: core.ExternalIDs{AniList: env.fake.uniqueID("al"), MAL: mal}, IsAnime: true},
		Status: &status, RuntimeMinutes: &runtime,
	})
	r := env.pzUpload(strings.ReplaceAll(pzMALAnime, "52991", mal), "mal", "animelist.xml", "application/xml")
	id := pzJobID(t, r)
	assert.Equal(t, "mal_xml", pzString(t, r.body, "source"))
	env.runImports()
	_, rows := env.importDetail(id)
	require.NotEmpty(t, rows)
	assert.Equal(t, "create", rows[0]["outcome"], "the MAL id resolves through AniList")
}

func TestAniListCreate(t *testing.T) {
	env := newPzEnv(t)
	bad := env.send("POST", "/v1/imports/anilist", map[string]any{"username": "no spaces!"})
	assert.Equal(t, http.StatusUnprocessableEntity, bad.Code)
	good := env.send("POST", "/v1/imports/anilist", map[string]any{"username": "@Someone_1"})
	require.Equal(t, http.StatusAccepted, good.Code, good.Body.String())
	job := decode[map[string]any](t, good)
	assert.Equal(t, "anilist", job["source"])
	assert.Equal(t, "Someone_1", job["filename"])
}

func TestMALMangaFlow(t *testing.T) {
	env := newPzEnv(t)
	mal := fmt.Sprint(100_000 + rand.IntN(900_000))
	ended, returning := catalog.StatusEnded, catalog.StatusReturning
	runtime := 24
	byline := "Kentarou Miura"
	env.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{
			Type: core.MediaShow, Title: "Same Number Anime", Year: pzPtr(2001),
			IDs: core.ExternalIDs{AniList: env.fake.uniqueID("al"), MAL: mal}, IsAnime: true,
		},
		Status: &ended, RuntimeMinutes: &runtime,
	})
	env.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{
			Type: core.MediaManga, Title: "Berserk", Year: pzPtr(1989), Byline: &byline,
			IDs: core.ExternalIDs{AniList: env.fake.uniqueID("al"), MAL: mal},
		},
		Status: &returning,
	})
	xml := strings.ReplaceAll(pzMALManga, "<manga_mangadb_id>2</manga_mangadb_id>", "<manga_mangadb_id>"+mal+"</manga_mangadb_id>")
	id := env.uploadJob("/v1/imports/csv?source=auto&filename=mangalist.xml", "application/xml", []byte(xml))
	env.runImports()
	env.pzApply(id)

	manga := env.json("GET", "/v1/library/items?type=manga", nil)
	var berserk map[string]any
	for _, it := range manga["items"].([]any) {
		item := it.(map[string]any)
		if item["title"].(map[string]any)["title"] == "Berserk" {
			berserk = item
		}
	}
	require.NotNil(t, berserk)
	assert.Equal(t, "in_progress", berserk["status"])
	progress := berserk["mangaProgress"].(map[string]any)
	assert.InDelta(t, 112, progress["chapter"], 0)
	assert.InDelta(t, 12, progress["volume"], 0)
	shows := env.json("GET", "/v1/library/items?type=show", nil)
	assert.Empty(t, shows["items"], "the anime with that MAL number stays out")
}
