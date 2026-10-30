package catalog

import (
	"context"
	"slices"
	"strconv"
	"testing"
	"time"

	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Show episode refresh (JOB-001 refresh kind), genres (CAT-018), page counts (APP-017).

const day = 24 * time.Hour

type refreshEnv struct {
	t     *testing.T
	ctx   context.Context
	pool  *pgxpool.Pool
	store *Store
	user  uuid.UUID
	n     int
}

func newRefreshEnv(t *testing.T) *refreshEnv {
	pool := testdb.New(t)
	env := &refreshEnv{t: t, ctx: context.Background(), pool: pool, store: NewStore(pool), user: uuid.New()}
	_, err := pool.Exec(env.ctx, `INSERT INTO users (id) VALUES ($1)`, env.user)
	require.NoError(t, err)
	return env
}

// title stores a title and returns it.
func (e *refreshEnv) title(mediaType core.MediaType, name string, ids core.ExternalIDs) core.Title {
	e.t.Helper()
	title := core.Title{ID: uuid.New(), Type: mediaType, Title: name, Year: ptr(2020), IDs: ids}
	require.NoError(e.t, e.store.Insert(e.ctx, title, nil, nil, nil))
	return title
}

// track puts the title in the user's library.
func (e *refreshEnv) track(id uuid.UUID, status string) {
	e.t.Helper()
	_, err := e.pool.Exec(e.ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
		VALUES ($1, $2, $3, $4, now(), now())`, uuid.New(), e.user, id, status)
	require.NoError(e.t, err)
}

// show stores a tracked show whose six episodes were loaded at hydratedAt.
func (e *refreshEnv) show(name, status string, hydratedAt time.Time) core.Title {
	e.n++
	title := e.title(core.MediaShow, name, core.ExternalIDs{TMDB: strconv.Itoa(1000 + e.n)})
	require.NoError(e.t, e.store.SaveEpisodes(e.ctx, title.ID, sixEpisodes(StatusEnded, nil), hydratedAt))
	e.track(title.ID, status)
	return title
}

func sixEpisodes(status TitleStatus, airsAt *time.Time) Episodes {
	e := Episodes{Status: &status}
	for i := range 6 {
		e.Episodes = append(e.Episodes, Episode{Season: 1, Episode: i + 1, Name: ptr("Episode " + strconv.Itoa(i+1)), AirsAt: airsAt})
	}
	return e
}

func (e *refreshEnv) setState(id uuid.UUID, hydratedAt, attemptedAt *time.Time) {
	e.t.Helper()
	_, err := e.pool.Exec(e.ctx, `UPDATE titles SET episodes_hydrated_at = $2, episodes_attempted_at = $3 WHERE id = $1`, id, hydratedAt, attemptedAt)
	require.NoError(e.t, err)
}

func (e *refreshEnv) state(id uuid.UUID) (hydrated, attempted *time.Time) {
	e.t.Helper()
	require.NoError(e.t, e.pool.QueryRow(e.ctx, `SELECT episodes_hydrated_at, episodes_attempted_at FROM titles WHERE id = $1`, id).
		Scan(&hydrated, &attempted))
	return hydrated, attempted
}

func (e *refreshEnv) due(now time.Time) []uuid.UUID {
	e.t.Helper()
	ids, err := e.store.StaleTrackedShows(e.ctx, now, now.Add(-RefreshRetryAfter), 100_000)
	require.NoError(e.t, err)
	return ids
}

func TestRefreshPass(t *testing.T) {
	env := newRefreshEnv(t)
	now := time.Now().UTC().Truncate(time.Second)
	fresh := env.show("Fresh", "wishlist", now)
	stale := env.show("Stale", "in_progress", now)
	imported := env.show("Imported", "wishlist", now)
	gone := env.show("Gone", "wishlist", now)
	dropped := env.show("Dropped", "dropped", now)
	env.setState(stale.ID, ptr(now.Add(-40*day)), nil)
	env.setState(imported.ID, nil, nil)
	env.setState(dropped.ID, nil, nil)
	// Its last refresh attempt failed ten minutes ago.
	env.setState(gone.ID, ptr(now.Add(-40*day)), ptr(now.Add(-10*time.Minute)))

	due := env.due(now)
	assert.Contains(t, due, stale.ID)
	assert.Contains(t, due, imported.ID)
	assert.NotContains(t, due, gone.ID, "attempted within the hour: backs off")
	assert.NotContains(t, due, fresh.ID, "inside its window")
	assert.NotContains(t, due, dropped.ID, "not tracked")
	assert.Less(t, slices.Index(due, imported.ID), slices.Index(due, stale.ID), "never-loaded first")

	fake := newFake()
	for _, show := range []core.Title{fresh, stale, imported, gone, dropped} {
		fake.stubEpisodes(show.IDs.TMDB, sixEpisodes(StatusEnded, nil))
	}
	refresher := NewRefresher(env.store, NewService(env.store, fake.providers()))
	refresher.Now = func() time.Time { return now }
	refresher.PassLimit = 100_000
	_, err := refresher.RunOnce(env.ctx)
	require.NoError(t, err)
	hydrated, attempted := env.state(imported.ID)
	assert.NotNil(t, hydrated)
	episodes, err := env.store.ShowEpisodes(env.ctx, imported.ID)
	require.NoError(t, err)
	assert.Len(t, episodes, 6)
	staleHydrated, _ := env.state(stale.ID)
	assert.True(t, staleHydrated.After(now.Add(-day)))
	assert.True(t, attempted.Equal(now), "every attempt is stamped")

	again := env.due(now)
	assert.NotContains(t, again, imported.ID)
	assert.NotContains(t, again, stale.ID)
	assert.Contains(t, env.due(now.Add(RefreshRetryAfter)), gone.ID, "retried once the hour is up")
}

func TestShowOnlyOnAListIsRefreshed(t *testing.T) {
	env := newRefreshEnv(t)
	now := time.Now().UTC()
	show := env.title(core.MediaShow, "Listed", core.ExternalIDs{TMDB: "55"})
	list := uuid.New()
	_, err := env.pool.Exec(env.ctx, `INSERT INTO lists (id, user_id, name, created_at, updated_at) VALUES ($1, $2, 'Later', now(), now())`, list, env.user)
	require.NoError(t, err)
	_, err = env.pool.Exec(env.ctx, `INSERT INTO list_items (id, list_id, title_id, position) VALUES ($1, $2, $3, 0)`, uuid.New(), list, show.ID)
	require.NoError(t, err)
	assert.Contains(t, env.due(now), show.ID)
}

func TestAiringShowIsStaleAfterADay(t *testing.T) {
	env := newRefreshEnv(t)
	now := time.Now().UTC().Truncate(time.Second)
	airing := env.title(core.MediaShow, "Airing", core.ExternalIDs{TMDB: "66"})
	require.NoError(t, env.store.SaveEpisodes(env.ctx, airing.ID, sixEpisodes(StatusReturning, ptr(now.Add(7*day))), now))
	env.track(airing.ID, "in_progress")
	env.setState(airing.ID, ptr(now.Add(-2*day)), nil)
	assert.Contains(t, env.due(now), airing.ID)
}

func TestSaveEpisodesUpsertsAndNeverDeletes(t *testing.T) {
	env := newRefreshEnv(t)
	now := time.Now().UTC()
	title := env.title(core.MediaShow, "Repeat", core.ExternalIDs{TMDB: "77"})
	require.NoError(t, env.store.SaveEpisodes(env.ctx, title.ID, Episodes{Status: ptr(StatusReturning), Episodes: []Episode{
		{Season: 1, Episode: 1, Name: ptr("Pilot")}, {Season: 1, Episode: 2, Name: ptr("Old")}, {Season: 1, Episode: 2, Name: ptr("New")},
	}}, now))
	require.NoError(t, env.store.SaveEpisodes(env.ctx, title.ID, Episodes{Status: ptr(StatusEnded), Episodes: []Episode{
		{Season: 1, Episode: 1, Name: ptr("Pilot (renamed)")},
	}}, now))
	saved, err := env.store.ShowEpisodes(env.ctx, title.ID)
	require.NoError(t, err)
	require.Len(t, saved, 2)
	assert.Equal(t, []string{"Pilot (renamed)", "New"}, []string{*saved[0].Name, *saved[1].Name})
	state, err := env.store.State(env.ctx, title.ID)
	require.NoError(t, err)
	assert.Equal(t, StatusEnded, *state.Status)
}

func genreRecord(mediaType core.MediaType, name string, ids core.ExternalIDs, anime bool, genres []string) Record {
	return Record{Hit: Hit{Type: mediaType, Title: name, Year: ptr(2020), IDs: ids, IsAnime: anime}, Genres: genres}
}

func TestGenresAreStoredAtHydration(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	fake := newFake()
	movie, show, anime := core.ExternalIDs{TMDB: "1"}, core.ExternalIDs{TMDB: "2"}, core.ExternalIDs{AniList: "3"}
	fake.stubTitle(genreRecord(core.MediaMovie, "Arrival", movie, false, []string{"Drama", "Science Fiction"}))
	fake.stubTitle(genreRecord(core.MediaShow, "Severance", show, false, []string{"Drama", "Mystery"}))
	fake.stubTitle(genreRecord(core.MediaShow, "Frieren", anime, true, []string{"Adventure", "Fantasy"}))
	resolver := NewResolver(store, fake.providers())
	var genres [][]string
	for _, ref := range []core.MediaRef{
		{Type: core.MediaMovie, IDs: movie}, {Type: core.MediaShow, IDs: show}, {Type: core.MediaShow, IDs: anime},
	} {
		title, err := resolver.Resolve(ctx, ref, nil)
		require.NoError(t, err)
		g, err := store.Genres(ctx, title.ID)
		require.NoError(t, err)
		genres = append(genres, g)
	}
	assert.Equal(t, [][]string{{"Drama", "Science Fiction"}, {"Drama", "Mystery"}, {"Adventure", "Fantasy"}}, genres)
}

func TestGenreBackfill(t *testing.T) {
	env := newRefreshEnv(t)
	// Stored before genres were: none.
	heat := env.title(core.MediaMovie, "Heat", core.ExternalIDs{TMDB: "949"})
	silent := env.title(core.MediaMovie, "Silent", core.ExternalIDs{TMDB: "950"})
	book := env.title(core.MediaBook, "Emma", core.ExternalIDs{ISBN: "9780141439587"})
	for _, id := range []uuid.UUID{heat.ID, silent.ID, book.ID} {
		env.track(id, "wishlist")
	}
	// The provider now lists Heat's genres; it still has none for Silent.
	later := newFake()
	later.stubTitle(genreRecord(core.MediaMovie, "Heat", heat.IDs, false, []string{"Crime"}))
	later.stubTitle(genreRecord(core.MediaMovie, "Silent", silent.IDs, false, nil))
	now := time.Now()
	refresher := NewRefresher(env.store, NewService(env.store, later.providers()))
	refresher.Now = func() time.Time { return now }
	refresher.GenreLimit = 100_000
	_, err := refresher.FillGenres(env.ctx)
	require.NoError(t, err)
	genres := func(id uuid.UUID) []string {
		g, err := env.store.Genres(env.ctx, id)
		require.NoError(t, err)
		return g
	}
	assert.Equal(t, []string{"Crime"}, genres(heat.ID))
	assert.Empty(t, genres(silent.ID))
	ids := func(titles []core.Title) []uuid.UUID {
		out := []uuid.UUID{}
		for _, t := range titles {
			out = append(out, t.ID)
		}
		return out
	}
	due, err := env.store.TitlesMissingGenres(env.ctx, now.Add(-GenresRetryAfter), 100_000)
	require.NoError(t, err)
	assert.NotContains(t, ids(due), heat.ID, "stamped: not asked again this week")
	assert.NotContains(t, ids(due), silent.ID)
	nextWeek, err := env.store.TitlesMissingGenres(env.ctx, now.Add(time.Second), 100_000)
	require.NoError(t, err)
	assert.Contains(t, ids(nextWeek), silent.ID)
	assert.NotContains(t, ids(nextWeek), heat.ID)
	require.NoError(t, env.store.FillGenres(env.ctx, heat.ID, []string{"Drama"}, now))
	assert.Equal(t, []string{"Crime"}, genres(heat.ID), "fill-empty-only")
	assert.NotContains(t, ids(nextWeek), book.ID, "books have no genres to fill")
}

func TestPageCountBackfill(t *testing.T) {
	env := newRefreshEnv(t)
	emma := env.title(core.MediaBook, "Emma", core.ExternalIDs{ISBN: "9780141439587"})
	env.track(emma.ID, "in_progress")
	later := newFake()
	later.stubTitle(Record{Hit: Hit{Type: core.MediaBook, Title: "Emma", IDs: emma.IDs, PageCount: ptr(474)}})
	refresher := NewRefresher(env.store, NewService(env.store, later.providers()))
	refresher.PageCountLimit = 100_000
	n, err := refresher.FillPageCounts(env.ctx)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, n, 1)
	stored, err := env.store.Title(env.ctx, emma.ID)
	require.NoError(t, err)
	assert.Equal(t, 474, *stored.PageCount)
	again, err := env.store.BooksMissingPageCount(env.ctx, time.Now(), 100_000)
	require.NoError(t, err)
	for _, b := range again {
		assert.NotEqual(t, emma.ID, b.ID, "filled, so never asked again")
	}
}

func TestRefreshWorkerStopsOnCancel(t *testing.T) {
	env := newRefreshEnv(t)
	worker := NewRefreshWorker(NewRefresher(env.store, NewService(env.store, newFake().providers())), nil)
	worker.Interval = time.Millisecond
	ctx, cancel := context.WithTimeout(env.ctx, 50*time.Millisecond)
	defer cancel()
	assert.NoError(t, worker.Run(ctx))
	assert.Equal(t, "catalog-refresh", worker.Name())
}
