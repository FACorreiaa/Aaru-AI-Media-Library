//go:build parity_g1

package library

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// storeFixtureParity is a migrated database with one user, for the store-level SRV tests.
func storeFixtureParity(t *testing.T) (*pgxpool.Pool, *Store, uuid.UUID) {
	t.Helper()
	pool := testdb.New(t)
	user := uuid.New()
	_, err := pool.Exec(context.Background(), `INSERT INTO users (id) VALUES ($1)`, user)
	require.NoError(t, err)
	return pool, NewStore(pool), user
}

func insertTitleParity(t *testing.T, pool *pgxpool.Pool, mediaType core.MediaType, name string) uuid.UUID {
	t.Helper()
	id := uuid.New()
	_, err := pool.Exec(context.Background(), `INSERT INTO titles (id, type, title) VALUES ($1, $2, $3)`, id, string(mediaType), name)
	require.NoError(t, err)
	return id
}

// DatabaseTests.libraryItemIsUnique (SRV-006): a second item for the same user and title is
// rejected; another user cannot read the first.
func TestASecondItemForTheSameTitleIsRejected(t *testing.T) {
	pool, store, user := storeFixtureParity(t)
	ctx := context.Background()
	title := insertTitleParity(t, pool, core.MediaMovie, "Dune")
	rating := 8.5
	snapshot := ItemSnapshot{
		ID: uuid.New(), TitleID: title, AddedAt: time.Now().UTC().Truncate(time.Second),
		Fields: ItemFields{Status: core.StatusWishlist, Rating: &rating},
	}
	_, err := store.Apply(ctx, InsertItem(snapshot), user, UserCaller, "add", "a")
	require.NoError(t, err)
	stored, err := store.Entry(ctx, snapshot.ID, user, time.Now())
	require.NoError(t, err)
	require.NotNil(t, stored)
	require.NotNil(t, stored.Item.Rating)
	assert.InDelta(t, 8.5, stored.Item.Rating.Value(), 0)
	assert.True(t, stored.Item.AddedAt.Equal(snapshot.AddedAt))

	duplicate := snapshot
	duplicate.ID = uuid.New()
	_, err = store.Apply(ctx, InsertItem(duplicate), user, UserCaller, "add", "b")
	var conflict *StoreConflict
	assert.ErrorAs(t, err, &conflict)

	other, err := store.Entry(ctx, snapshot.ID, uuid.New(), time.Now())
	require.NoError(t, err)
	assert.Nil(t, other, "another user cannot read it")
}

// DatabaseTests.listRoundTrip (SRV-006): lists keep member order and default to private.
func TestListsKeepMemberOrderAndArePrivate(t *testing.T) {
	pool, store, user := storeFixtureParity(t)
	ctx := context.Background()
	first := insertTitleParity(t, pool, core.MediaBook, "Dune")
	second := insertTitleParity(t, pool, core.MediaBook, "Children of Dune")
	snapshot := ListSnapshot{
		ID: uuid.New(), Name: "Arrakis", CreatedAt: time.Now().UTC().Truncate(time.Second), Members: []uuid.UUID{second, first},
	}
	_, err := store.Apply(ctx, InsertList(snapshot), user, UserCaller, "list", "L")
	require.NoError(t, err)
	lists, err := store.Lists(ctx, user)
	require.NoError(t, err)
	require.Len(t, lists, 1)
	assert.Equal(t, []uuid.UUID{second, first}, lists[0].TitleIDs)
	assert.True(t, lists[0].CreatedAt.Equal(snapshot.CreatedAt))
	var visibility string
	require.NoError(t, pool.QueryRow(ctx, `SELECT visibility FROM lists WHERE id = $1`, snapshot.ID).Scan(&visibility))
	assert.Equal(t, "private", visibility)
	other, err := store.List(ctx, snapshot.ID, uuid.New())
	require.NoError(t, err)
	assert.Nil(t, other)
}
