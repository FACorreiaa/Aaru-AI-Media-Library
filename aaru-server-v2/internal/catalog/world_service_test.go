package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/testdb"
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-007: Worlds queued, built and stored, against the database.

type worldEnv struct {
	t      *testing.T
	ctx    context.Context
	store  *Store
	worlds *WorldService
	now    time.Time
}

// newWorldEnv is a World service over uncached fake sources, with a clock the test moves.
func newWorldEnv(t *testing.T, sources ...RelationSource) *worldEnv {
	t.Helper()
	store := NewStore(testdb.New(t))
	env := &worldEnv{t: t, ctx: context.Background(), store: store, now: time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC)}
	relations := &RelationService{Store: store, Sources: sources, log: slog.Default()}
	env.worlds = NewWorldService(relations, store, nil)
	env.worlds.Now = func() time.Time { return env.now }
	return env
}

func (e *worldEnv) title(mediaType core.MediaType, name, column, id string) uuid.UUID {
	e.t.Helper()
	titleID := uuid.New()
	_, err := e.store.pool.Exec(e.ctx, `INSERT INTO titles (id, type, title, `+column+`) VALUES ($1, $2, $3, $4)`,
		titleID, string(mediaType), name, id)
	require.NoError(e.t, err)
	return titleID
}

func (e *worldEnv) buildAll() int {
	e.t.Helper()
	built := 0
	for {
		worked, err := e.worlds.BuildNext(e.ctx)
		require.NoError(e.t, err)
		if !worked {
			return built
		}
		built++
	}
}

func (e *worldEnv) stored(keys ...string) []sqlc.World {
	e.t.Helper()
	worlds, err := e.store.q.WorldByKeys(e.ctx, keys)
	require.NoError(e.t, err)
	return worlds
}

func (e *worldEnv) build(titleID uuid.UUID) sqlc.WorldBuildRow {
	e.t.Helper()
	row, err := e.store.q.WorldBuild(e.ctx, titleID)
	require.NoError(e.t, err)
	return row
}

func TestWorldIsBuiltFromTheQueueAndStoredOnce(t *testing.T) {
	env := newWorldEnv(t, duneSources()...)
	partTwo := env.title(core.MediaMovie, "Dune: Part Two", "tmdb", "693134")
	messiah := env.title(core.MediaBook, "Dune Messiah", "open_library", "OL2W")

	env.worlds.Enqueue(env.ctx, partTwo, WorldPriorityOpened)
	assert.Equal(t, "queued", env.build(partTwo).State)
	require.Equal(t, 1, env.buildAll())
	assert.Equal(t, "done", env.build(partTwo).State)

	worlds := env.stored("tmdb:movie:693134")
	require.Len(t, worlds, 1)
	world := worlds[0]
	assert.Equal(t, "Dune", world.Name)
	assert.Equal(t, "openlibrary:OL1W", world.RootKey)
	assert.EqualValues(t, 5, world.TitleCount)
	assert.False(t, world.Partial)
	titles, err := env.store.q.WorldTitles(env.ctx, world.ID)
	require.NoError(t, err)
	require.Len(t, titles, 5)
	assert.Equal(t, "openlibrary:OL1W", titles[0].NodeKey)
	assert.Equal(t, "book", titles[0].Lane)
	assert.Equal(t, "show", titles[4].Lane)
	assert.True(t, titles[4].Side)

	// Another of its titles finds the same World, and building from it keeps the id.
	env.worlds.Enqueue(env.ctx, messiah, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	again := env.stored("openlibrary:OL2W", "tmdb:show:90228")
	require.Len(t, again, 1)
	assert.Equal(t, world.ID, again[0].ID)
	assert.True(t, world.CreatedAt.Equal(again[0].CreatedAt))
}

func TestATitleWithNoWorldIsRememberedAndAskedAgainOnlyOnceStale(t *testing.T) {
	env := newWorldEnv(t, duneSources()...)
	alone := env.title(core.MediaMovie, "Alone", "tmdb", "7")
	env.worlds.Enqueue(env.ctx, alone, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	assert.Equal(t, "done", env.build(alone).State)
	assert.Empty(t, env.stored("tmdb:movie:7"))

	env.now = env.now.Add(WorldRecheck - time.Hour)
	env.worlds.Enqueue(env.ctx, alone, WorldPriorityOpened)
	assert.Equal(t, 0, env.buildAll(), "looked at within the recheck window: not asked again")

	env.now = env.now.Add(2 * time.Hour)
	env.worlds.Enqueue(env.ctx, alone, WorldPriorityOpened)
	assert.Equal(t, 1, env.buildAll(), "asked again once the look is stale")
}

func TestTwoWorldsThatTurnOutToBeOneMergeIntoTheOlder(t *testing.T) {
	one, two := film("438631", "Dune: Part One", "2021-09-15"), film("693134", "Dune: Part Two", "2024-02-27")
	dune, messiah := book("OL1W", "Dune", 1965), book("OL2W", "Dune Messiah", 1969)
	books := universe("books", link(dune, core.RelationSequel, messiah))
	films := universe("films", link(one, core.RelationSequel, two))
	bridge := &fakeRelations{name: "wiki", answers: map[string]Relations{}}
	env := newWorldEnv(t, books, films, bridge)
	bookTitle := env.title(core.MediaBook, "Dune", "open_library", "OL1W")
	filmTitle := env.title(core.MediaMovie, "Dune: Part One", "tmdb", "438631")

	env.worlds.Enqueue(env.ctx, filmTitle, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	env.now = env.now.Add(time.Minute)
	env.worlds.Enqueue(env.ctx, bookTitle, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	filmsWorld, booksWorld := env.stored("tmdb:movie:438631"), env.stored("openlibrary:OL1W")
	require.Len(t, filmsWorld, 1)
	require.Len(t, booksWorld, 1)
	require.NotEqual(t, filmsWorld[0].ID, booksWorld[0].ID, "nothing joins them yet")

	// A provider learns the films adapt the novel: the next build finds one World.
	bridge.answers["tmdb:movie:438631"] = Relations{Edges: []RelatedEdge{{To: dune, Relation: core.RelationSource}}}
	bridge.answers["openlibrary:OL1W"] = Relations{Edges: []RelatedEdge{{To: one, Relation: core.RelationAdaptation}}}
	env.now = env.now.Add(WorldRecheck + time.Hour)
	env.worlds.Enqueue(env.ctx, bookTitle, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())

	merged := env.stored("tmdb:movie:438631", "tmdb:movie:693134", "openlibrary:OL1W", "openlibrary:OL2W")
	require.Len(t, merged, 1, "one World holds all four")
	assert.Equal(t, filmsWorld[0].ID, merged[0].ID, "the older World keeps its id")
	assert.Equal(t, "Dune", merged[0].Name, "and is named after its new first title")
	assert.EqualValues(t, 4, merged[0].TitleCount)
	var count int
	require.NoError(t, env.store.pool.QueryRow(env.ctx, `SELECT count(*) FROM worlds`).Scan(&count))
	assert.Equal(t, 1, count)
}

func TestAPartialBuildNeverReplacesACompleteWorldAndIsTriedAgain(t *testing.T) {
	failing := &fakeRelations{name: "down"}
	sources := append(duneSources(), failing)
	env := newWorldEnv(t, sources...)
	partOne := env.title(core.MediaMovie, "Dune: Part One", "tmdb", "438631")
	env.worlds.Enqueue(env.ctx, partOne, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	complete := env.stored("tmdb:movie:438631")
	require.Len(t, complete, 1)
	require.False(t, complete[0].Partial)

	// The next build runs while a provider is down and the other knows less than it did.
	failing.err = errors.New("provider is down")
	all := sources[0].(*fakeRelations)
	saved := all.answers
	all.answers = map[string]Relations{"tmdb:movie:438631": {Edges: []RelatedEdge{
		link(film("438631", "Dune: Part One", "2021-09-15"), core.RelationSequel, film("693134", "Dune: Part Two", "2024-02-27")),
	}}}
	env.now = env.now.Add(WorldRecheck + time.Hour)
	env.worlds.Enqueue(env.ctx, partOne, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())

	kept := env.stored("tmdb:movie:438631")
	require.Len(t, kept, 1)
	assert.EqualValues(t, 5, kept[0].TitleCount, "the complete World stays")
	assert.True(t, complete[0].BuiltAt.Equal(kept[0].BuiltAt))
	row := env.build(partOne)
	assert.Equal(t, "queued", row.State, "and the title waits to be tried again")
	assert.True(t, env.now.Add(worldRetryBase).Equal(row.RunAfter), "waits %s, got %s", worldRetryBase, row.RunAfter)
	assert.Equal(t, 0, env.buildAll(), "not before its wait is over")

	// Back up: the retry builds it whole.
	failing.err, all.answers = nil, saved
	env.now = env.now.Add(worldRetryBase + time.Second)
	require.Equal(t, 1, env.buildAll())
	assert.Equal(t, "done", env.build(partOne).State)
}

func TestAPartialWorldIsStoredWhenThereIsNoneAndFailsAfterItsAttempts(t *testing.T) {
	failing := &fakeRelations{name: "down", err: errors.New("provider is down")}
	env := newWorldEnv(t, append(duneSources(), failing)...)
	partOne := env.title(core.MediaMovie, "Dune: Part One", "tmdb", "438631")
	env.worlds.Enqueue(env.ctx, partOne, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	stored := env.stored("tmdb:movie:438631")
	require.Len(t, stored, 1, "what was found is shown meanwhile")
	assert.True(t, stored[0].Partial)

	for attempt := int32(2); attempt <= WorldBuildAttempts; attempt++ {
		env.now = env.now.Add(worldRetryMax + time.Second)
		require.Equal(t, 1, env.buildAll(), "attempt %d", attempt)
	}
	assert.Equal(t, "failed", env.build(partOne).State)
	env.now = env.now.Add(worldRetryMax + time.Second)
	assert.Equal(t, 0, env.buildAll(), "out of attempts: left alone until a read asks again")
}

func TestWorldBuildsAreLeasedByPriorityAndAnExpiredLeaseIsTakenOver(t *testing.T) {
	env := newWorldEnv(t, duneSources()...)
	imported := env.title(core.MediaMovie, "Imported", "tmdb", "1")
	opened := env.title(core.MediaMovie, "Opened", "tmdb", "2")
	env.worlds.Enqueue(env.ctx, imported, WorldPriorityImport)
	env.now = env.now.Add(time.Second)
	env.worlds.Enqueue(env.ctx, opened, WorldPriorityOpened)

	lease := env.now.Add(WorldBuildLease)
	claim := func() (sqlc.WorldBuildClaimRow, error) {
		return env.store.q.WorldBuildClaim(env.ctx, sqlc.WorldBuildClaimParams{LeasedUntil: &lease, Now: env.now, MaxAttempts: WorldBuildAttempts})
	}
	first, err := claim()
	require.NoError(t, err)
	assert.Equal(t, opened, first.TitleID, "an opened title goes before an import's backlog")
	second, err := claim()
	require.NoError(t, err)
	assert.Equal(t, imported, second.TitleID)
	_, err = claim()
	require.Error(t, err, "both are leased")

	// The process died under them: once the lease is over they are taken again.
	env.now = env.now.Add(WorldBuildLease + time.Second)
	assert.Equal(t, 2, env.buildAll())
	assert.Equal(t, "done", env.build(opened).State)
	assert.EqualValues(t, 2, env.build(opened).Attempts)

	// Queued again while queued only raises the priority.
	third := env.title(core.MediaMovie, "Third", "tmdb", "3")
	env.worlds.Enqueue(env.ctx, third, WorldPriorityImport)
	env.worlds.Enqueue(env.ctx, third, WorldPriorityOpened)
	env.worlds.Enqueue(env.ctx, third, WorldPriorityImport)
	assert.Equal(t, WorldPriorityOpened, env.build(third).Priority)
}

func TestEnqueueLibraryQueuesOnlyTitlesNeverLookedAt(t *testing.T) {
	env := newWorldEnv(t, duneSources()...)
	user := uuid.New()
	_, err := env.store.pool.Exec(env.ctx, `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)
	seen := env.title(core.MediaMovie, "Seen", "tmdb", "7")
	fresh := env.title(core.MediaMovie, "Dune: Part One", "tmdb", "438631")
	other := env.title(core.MediaMovie, "Someone else's", "tmdb", "8")
	for _, id := range []uuid.UUID{seen, fresh} {
		_, err := env.store.pool.Exec(env.ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
			VALUES ($1, $2, $3, 'wishlist', now(), now())`, uuid.New(), user, id)
		require.NoError(t, err)
	}
	env.worlds.Enqueue(env.ctx, seen, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())

	queued, err := env.worlds.EnqueueLibrary(env.ctx, user)
	require.NoError(t, err)
	assert.EqualValues(t, 1, queued)
	assert.Equal(t, "queued", env.build(fresh).State)
	assert.Equal(t, WorldPriorityImport, env.build(fresh).Priority)
	assert.Equal(t, "done", env.build(seen).State)
	_, err = env.store.q.WorldBuild(env.ctx, other)
	require.Error(t, err, "a title outside the library is not queued")
}

func TestAnAnimeSeasonIsAlsoFoundByTheShowAaruKeepsItIn(t *testing.T) {
	first, second := anime("101", "Season one", "2010-04-01"), anime("102", "Season two", "2012-04-01")
	env := newWorldEnv(t, universe("anilist", link(first, core.RelationSequel, second)))
	_, err := env.store.pool.Exec(env.ctx, `INSERT INTO anime_mappings (anilist, tmdb, tmdb_season) VALUES ('101', '555', 1), ('102', '555', 2)`)
	require.NoError(t, err)
	showID := env.title(core.MediaShow, "The show", "tmdb", "555")
	_, err = env.store.pool.Exec(env.ctx, `UPDATE titles SET is_anime = true WHERE id = $1`, showID)
	require.NoError(t, err)

	env.worlds.Enqueue(env.ctx, showID, WorldPriorityOpened)
	require.Equal(t, 1, env.buildAll())
	byShow := env.stored("tmdb:show:555")
	require.Len(t, byShow, 1, "the two seasons map to one show, and the key is stored once")
	assert.EqualValues(t, 2, byShow[0].TitleCount)
	assert.Equal(t, byShow[0].ID, env.stored("anilist:102")[0].ID)
}

func TestWorldRetryWaitsDoubleUpToACap(t *testing.T) {
	assert.Equal(t, 5*time.Minute, worldRetryAfter(1))
	assert.Equal(t, 10*time.Minute, worldRetryAfter(2))
	assert.Equal(t, 40*time.Minute, worldRetryAfter(4))
	assert.Equal(t, worldRetryMax, worldRetryAfter(20))
}
