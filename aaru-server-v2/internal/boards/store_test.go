package boards

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/testdb"
	"context"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Board store (BoardStoreTests.swift, BOARD-001).

type storeEnv struct {
	t     *testing.T
	pool  *pgxpool.Pool
	store *Store
}

func newStoreEnv(t *testing.T) *storeEnv {
	t.Helper()
	pool := testdb.New(t)
	return &storeEnv{t: t, pool: pool, store: &Store{Q: sqlc.New(pool)}}
}

// author is a user with a handle, which is what makes someone a Board author.
func (e *storeEnv) author() groups.User {
	e.t.Helper()
	ctx := context.Background()
	id := uuid.New()
	handle := "b" + strings.ReplaceAll(uuid.NewString(), "-", "")[:12]
	_, err := e.pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, id)
	require.NoError(e.t, err)
	_, err = e.pool.Exec(ctx, `INSERT INTO profiles (user_id, handle) VALUES ($1, $2)`, id, handle)
	require.NoError(e.t, err)
	return groups.User{ID: id, Handle: handle}
}

func (e *storeEnv) post(p Post) Post {
	e.t.Helper()
	created, err := e.store.CreatePost(context.Background(), p)
	require.NoError(e.t, err)
	return created
}

func freePost(author groups.User, at time.Time) Post {
	return Post{ID: uuid.New(), Author: author, Body: "hello", CreatedAt: at}
}

func postIDs(posts []Post) []uuid.UUID {
	out := make([]uuid.UUID, len(posts))
	for i, p := range posts {
		out[i] = p.ID
	}
	return out
}

func commentIDs(comments []Comment) []uuid.UUID {
	out := make([]uuid.UUID, len(comments))
	for i, c := range comments {
		out[i] = c.ID
	}
	return out
}

func TestStoreFeedIsNewestFirstAndPagesByBefore(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	alice := e.author()
	now := time.Now()
	first := e.post(freePost(alice, now.Add(-30*time.Second)))
	second := e.post(freePost(alice, now.Add(-20*time.Second)))
	third := e.post(freePost(alice, now.Add(-10*time.Second)))

	page, err := e.store.Feed(ctx, []uuid.UUID{alice.ID}, nil, 2, alice.ID)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{third.ID, second.ID}, postIDs(page))
	next, err := e.store.Feed(ctx, []uuid.UUID{alice.ID}, &second.ID, 2, alice.ID)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{first.ID}, postIDs(next))
	require.NotEmpty(t, next)
	assert.Equal(t, alice, next[0].Author)
}

func TestStoreUpvotesAreIdempotentAndCounted(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	alice, bob := e.author(), e.author()
	created := e.post(freePost(alice, time.Now()))
	require.NoError(t, e.store.SetUpvote(ctx, created.ID, alice.ID, true))
	require.NoError(t, e.store.SetUpvote(ctx, created.ID, alice.ID, true))
	require.NoError(t, e.store.SetUpvote(ctx, created.ID, bob.ID, true))

	counted, err := e.store.Post(ctx, created.ID, alice.ID)
	require.NoError(t, err)
	require.NotNil(t, counted)
	assert.Equal(t, 2, counted.Upvotes)
	assert.True(t, counted.UpvotedByViewer)
	upvoters, err := e.store.Upvoters(ctx, created.ID)
	require.NoError(t, err)
	assert.Len(t, upvoters, 2)

	require.NoError(t, e.store.SetUpvote(ctx, created.ID, alice.ID, false))
	require.NoError(t, e.store.SetUpvote(ctx, created.ID, alice.ID, false))
	after, err := e.store.Post(ctx, created.ID, alice.ID)
	require.NoError(t, err)
	require.NotNil(t, after)
	assert.Equal(t, 1, after.Upvotes)
	assert.False(t, after.UpvotedByViewer)
}

func TestStoreTopOrdersByUpvotesInsideTheWindow(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	alice, bob := e.author(), e.author()
	now := time.Now()
	quiet := e.post(freePost(alice, now.Add(-10*time.Second)))
	loved := e.post(freePost(alice, now.Add(-20*time.Second)))
	require.NoError(t, e.store.SetUpvote(ctx, loved.ID, alice.ID, true))
	require.NoError(t, e.store.SetUpvote(ctx, loved.ID, bob.ID, true))

	ranked, err := e.store.Top(ctx, []uuid.UUID{alice.ID}, now.Add(-60*time.Second), 10, alice.ID)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{loved.ID, quiet.ID}, postIDs(ranked))
	narrow, err := e.store.Top(ctx, []uuid.UUID{alice.ID}, now.Add(-15*time.Second), 10, alice.ID)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{quiet.ID}, postIDs(narrow))
}

func TestStoreDeletedPostsVanish(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	alice := e.author()
	created := e.post(freePost(alice, time.Now()))
	require.NoError(t, e.store.DeletePost(ctx, created.ID, time.Now()))
	found, err := e.store.Post(ctx, created.ID, alice.ID)
	require.NoError(t, err)
	assert.Nil(t, found)
	feed, err := e.store.Feed(ctx, []uuid.UUID{alice.ID}, nil, 10, alice.ID)
	require.NoError(t, err)
	assert.Empty(t, feed)
}

func TestStoreTitlePostsCarryRatingAndSpoilerCommentsKeepDeletedRows(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	alice := e.author()
	title := uuid.New()
	_, err := e.pool.Exec(ctx, `INSERT INTO titles (id, type, title) VALUES ($1, 'movie', $2)`, title, "Dune "+uuid.NewString())
	require.NoError(t, err)
	rating := 8.5
	stamp := groups.EpisodeStamp(groups.EpisodePoint{Season: 1, Episode: 2})
	created := e.post(Post{
		ID: uuid.New(), Author: alice, TitleID: &title, Rating: &rating, Body: "great", Spoiler: stamp, CreatedAt: time.Now(),
	})

	about, err := e.store.TitlePosts(ctx, title, []uuid.UUID{alice.ID}, 5, alice.ID)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{created.ID}, postIDs(about))
	require.NotEmpty(t, about)
	require.NotNil(t, about[0].Rating)
	assert.InDelta(t, 8.5, *about[0].Rating, 0)
	assert.Equal(t, stamp, about[0].Spoiler)

	now := time.Now()
	kept, err := e.store.AddComment(ctx, Comment{
		ID: uuid.New(), PostID: created.ID, Author: &alice, Body: "one", Mentions: []uuid.UUID{alice.ID}, CreatedAt: now,
	})
	require.NoError(t, err)
	gone, err := e.store.AddComment(ctx, Comment{
		ID: uuid.New(), PostID: created.ID, FromAgent: true, ReplyTo: &kept.ID, Body: "two", Mentions: []uuid.UUID{},
		CreatedAt: now.Add(time.Second),
	})
	require.NoError(t, err)
	require.NoError(t, e.store.DeleteComment(ctx, gone.ID, now))

	all, err := e.store.Comments(ctx, created.ID, nil, 10)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{kept.ID, gone.ID}, commentIDs(all))
	require.Len(t, all, 2)
	assert.Equal(t, []uuid.UUID{alice.ID}, all[0].Mentions)
	assert.True(t, all[1].FromAgent)
	assert.Nil(t, all[1].Author)
	assert.NotNil(t, all[1].DeletedAt)
	after, err := e.store.Comments(ctx, created.ID, &kept.ID, 10)
	require.NoError(t, err)
	assert.Equal(t, []uuid.UUID{gone.ID}, commentIDs(after))
	one, err := e.store.Comment(ctx, kept.ID, created.ID)
	require.NoError(t, err)
	require.NotNil(t, one)
	assert.Equal(t, "one", one.Body)
	counted, err := e.store.Post(ctx, created.ID, alice.ID)
	require.NoError(t, err)
	require.NotNil(t, counted)
	assert.Equal(t, 1, counted.CommentCount)
}

func TestStoreAccountDeletionLeavesNoBoardRows(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	alice := e.author()
	created := e.post(freePost(alice, time.Now()))
	require.NoError(t, e.store.SetUpvote(ctx, created.ID, alice.ID, true))
	_, err := e.store.AddComment(ctx, Comment{ID: uuid.New(), PostID: created.ID, Author: &alice, Body: "c", CreatedAt: time.Now()})
	require.NoError(t, err)
	require.NoError(t, sqlc.New(e.pool).DeleteUser(ctx, alice.ID))

	var rows int
	require.NoError(t, e.pool.QueryRow(ctx, `
		SELECT (SELECT count(*) FROM board_posts WHERE user_id = $1)
		     + (SELECT count(*) FROM board_upvotes WHERE user_id = $1)
		     + (SELECT count(*) FROM board_comments WHERE user_id = $1)
		     + (SELECT count(*) FROM board_comments WHERE post_id = $2)
		     + (SELECT count(*) FROM board_upvotes WHERE post_id = $2)`, alice.ID, created.ID).Scan(&rows))
	assert.Zero(t, rows)
}

func TestStoreDeletingAnAccountKeepsOtherPeoplesRepliesToItsComments(t *testing.T) {
	e := newStoreEnv(t)
	ctx := context.Background()
	ana, ben := e.author(), e.author()
	created := e.post(freePost(ben, time.Now()))
	top, err := e.store.AddComment(ctx, Comment{ID: uuid.New(), PostID: created.ID, Author: &ana, Body: "top", CreatedAt: time.Now()})
	require.NoError(t, err)
	reply, err := e.store.AddComment(ctx, Comment{
		ID: uuid.New(), PostID: created.ID, Author: &ben, ReplyTo: &top.ID, Body: "reply", CreatedAt: time.Now().Add(time.Second),
	})
	require.NoError(t, err)
	require.NoError(t, sqlc.New(e.pool).DeleteUser(ctx, ana.ID))

	survivor, err := e.store.Comment(ctx, reply.ID, created.ID)
	require.NoError(t, err)
	require.NotNil(t, survivor)
	assert.Equal(t, "reply", survivor.Body)
	assert.Nil(t, survivor.ReplyTo)
}
