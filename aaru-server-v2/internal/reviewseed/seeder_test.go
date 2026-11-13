package reviewseed_test

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/moderation"
	"aaru-go-api/internal/reviewseed"
	"aaru-go-api/internal/testdb"
	"context"
	"io"
	"log/slog"
	"net/url"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

// fakeCatalog hydrates every seed title but one (Kind of Blue), so a title that does not resolve
// is seen to be skipped. Shows have six aired episodes in season 1. No network.
type fakeCatalog struct{ unknown string }

func (fakeCatalog) Search(context.Context, string, core.MediaType) ([]catalog.Hit, error) {
	return nil, nil
}

func (fakeCatalog) SearchMulti(context.Context, string) ([]catalog.Hit, error) { return nil, nil }

func (f fakeCatalog) Hydrate(_ context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*catalog.Record, error) {
	for _, seed := range append(append([]reviewseed.Seed{}, reviewseed.ReviewLibrary...), reviewseed.FriendLibrary...) {
		if seed.Ref.Type == mediaType && seed.Ref.IDs.Matches(ids) {
			if seed.Name == f.unknown {
				return nil, nil // not known
			}
			year := 2010
			status := catalog.StatusReturning
			return &catalog.Record{
				Hit:    catalog.Hit{Type: mediaType, Title: seed.Name, Year: &year, IDs: seed.Ref.IDs},
				Status: &status,
			}, nil
		}
	}
	return nil, nil // not known
}

func (fakeCatalog) Episodes(context.Context, core.ExternalIDs) (*catalog.Episodes, error) {
	aired := time.Now().Add(-90 * 24 * time.Hour)
	status := catalog.StatusReturning
	out := catalog.Episodes{Status: &status}
	for e := 1; e <= 6; e++ {
		out.Episodes = append(out.Episodes, catalog.Episode{Season: 1, Episode: e, AirsAt: &aired})
	}
	return &out, nil
}

func (fakeCatalog) Tracks(context.Context, core.ExternalIDs) ([]catalog.AlbumTrack, error) {
	return nil, nil
}

type noMail struct{ sent int }

func (m *noMail) Send(context.Context, string, string, string) error { m.sent++; return nil }

const (
	reviewEmail = "Review@Example.com"
	reviewCode  = "246810"
)

func seeder(pool *pgxpool.Pool) *reviewseed.Seeder {
	fake := fakeCatalog{unknown: "Kind of Blue"}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	kit := catalog.NewKit(pool, catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}, log)
	return reviewseed.New(pool, kit, log)
}

func count(t *testing.T, pool *pgxpool.Pool, query string, args ...any) int {
	t.Helper()
	var n int
	require.NoError(t, pool.QueryRow(context.Background(), query, args...).Scan(&n))
	return n
}

// tables are every row count the seed could change, to show a second run changes none.
func tables(t *testing.T, pool *pgxpool.Pool) map[string]int {
	t.Helper()
	out := map[string]int{}
	for _, table := range []string{
		"users", "auth_identities", "profiles", "library_items", "episode_progress", "actions", "social_friendships",
		"social_friend_requests", "board_posts", "board_comments", "groups", "group_members", "group_invites",
		"group_messages", "titles",
	} {
		out[table] = count(t, pool, "SELECT count(*)::int FROM "+table)
	}
	return out
}

func TestSeedReviewAccount(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	email := "review@example.com"

	first, err := seeder(pool).Run(ctx, reviewEmail)
	require.NoError(t, err)
	require.True(t, first.ReviewerCreated)
	require.True(t, first.FriendCreated)
	require.Equal(t, reviewseed.Counts{Added: 14, Failed: 1}, first.ReviewerLibrary)
	require.Equal(t, reviewseed.Counts{Added: 5}, first.FriendLibrary)
	require.True(t, first.FriendshipMade)
	require.True(t, first.PostCreated)
	require.Equal(t, reviewseed.Counts{Added: 2}, first.Comments)
	require.True(t, first.GroupCreated)
	require.True(t, first.GroupJoined)
	require.Equal(t, reviewseed.Counts{Added: 5}, first.Messages)

	// The review account: an email identity, handle and names, first run done, AI sharing unanswered.
	require.Equal(t, 1, count(t, pool, `SELECT count(*)::int FROM auth_identities WHERE user_id = $1 AND provider = 'email' AND provider_subject = $2`, first.Reviewer, email))
	var handle, firstName, lastName string
	var onboarded bool
	var aiAllowed *bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT p.handle, u.first_name, u.last_name, u.onboarded_at IS NOT NULL, u.ai_sharing_allowed
		FROM users u JOIN profiles p ON p.user_id = u.id WHERE u.id = $1`, first.Reviewer).Scan(&handle, &firstName, &lastName, &onboarded, &aiAllowed))
	require.Equal(t, []any{"appreview", "App", "Review", true}, []any{handle, firstName, lastName, onboarded})
	require.Nil(t, aiAllowed)

	// The library: every status, two ratings, one note, ticks on the three shows in progress.
	require.Equal(t, 14, count(t, pool, `SELECT count(*)::int FROM library_items WHERE user_id = $1`, first.Reviewer))
	require.Equal(t, 1, count(t, pool, `SELECT count(*)::int FROM library_items WHERE user_id = $1 AND status = 'on_hold'`, first.Reviewer))
	require.Equal(t, 2, count(t, pool, `SELECT count(*)::int FROM library_items WHERE user_id = $1 AND rating IS NOT NULL`, first.Reviewer))
	require.Equal(t, 1, count(t, pool, `SELECT count(*)::int FROM library_items WHERE user_id = $1 AND notes IS NOT NULL`, first.Reviewer))
	require.Equal(t, 9, count(t, pool, `SELECT count(*)::int FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id WHERE li.user_id = $1`, first.Reviewer))

	// Mira: no way to sign in, a handle, her own library, a friend of the reviewer.
	require.Equal(t, 0, count(t, pool, `SELECT count(*)::int FROM auth_identities WHERE user_id = $1`, first.Friend))
	require.Equal(t, 1, count(t, pool, `SELECT count(*)::int FROM profiles WHERE user_id = $1 AND handle = 'mira_reads'`, first.Friend))
	require.Equal(t, 5, count(t, pool, `SELECT count(*)::int FROM library_items WHERE user_id = $1`, first.Friend))
	require.Equal(t, 5, count(t, pool, `SELECT count(*)::int FROM group_messages`))
	require.Equal(t, 1, count(t, pool, `SELECT count(*)::int FROM group_messages WHERE author_id = $1`, first.Reviewer))
	require.Equal(t, 2, count(t, pool, `SELECT count(*)::int FROM group_members`))

	// A second run changes nothing.
	before := tables(t, pool)
	second, err := seeder(pool).Run(ctx, reviewEmail)
	require.NoError(t, err)
	require.Equal(t, first.Reviewer, second.Reviewer)
	require.Equal(t, first.Friend, second.Friend)
	require.False(t, second.ReviewerCreated || second.FriendCreated || second.FriendshipMade || second.PostCreated ||
		second.GroupCreated || second.GroupJoined)
	require.Equal(t, reviewseed.Counts{Kept: 14, Failed: 1}, second.ReviewerLibrary)
	require.Equal(t, reviewseed.Counts{Kept: 5}, second.FriendLibrary)
	require.Equal(t, reviewseed.Counts{Kept: 2}, second.Comments)
	require.Equal(t, reviewseed.Counts{Kept: 5}, second.Messages)
	require.Equal(t, before, tables(t, pool))

	// The reviewer's own sign-in, the fixed code with no mail, reaches the seeded account.
	link, _ := url.Parse("https://aaruapp.example/signin")
	mail := &noMail{}
	signIn := auth.NewService(auth.NewStore(pool), nil, &auth.MagicLinks{Sender: mail, LinkBaseURL: link}, nil)
	signIn.Review = &auth.ReviewAccount{Email: email, Code: reviewCode}
	require.NoError(t, signIn.RequestMagicLink(ctx, reviewEmail, "203.0.113.1"))
	require.Zero(t, mail.sent)
	session, err := signIn.VerifyEmailCode(ctx, reviewEmail, reviewCode)
	require.NoError(t, err)
	require.Equal(t, first.Reviewer, session.UserID)

	// Nobody signs in as Mira: no identity of any provider is hers.
	require.Equal(t, 0, count(t, pool, `SELECT count(*)::int FROM auth_identities WHERE user_id = $1`, first.Friend))
}

// A block either way stands: a later run makes nothing social around it.
func TestSeedReviewAccountAfterBlock(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	first, err := seeder(pool).Run(ctx, reviewEmail)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM social_friendships`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO social_blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, now())`, first.Reviewer, first.Friend)
	require.NoError(t, err)

	again, err := seeder(pool).Run(ctx, reviewEmail)
	require.NoError(t, err)
	require.True(t, again.Blocked)
	require.False(t, again.FriendshipMade)
	require.Equal(t, 0, count(t, pool, `SELECT count(*)::int FROM social_friendships`))
}

// A handle held by someone who signs in is a real person: the run stops before writing to them.
func TestSeedReviewAccountRefusesARealFriendHandle(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	someone := uuid.New()
	_, err := pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, someone)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO auth_identities (id, user_id, provider, provider_subject) VALUES ($1, $2, 'apple', 'sub')`, uuid.New(), someone)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO profiles (user_id, handle) VALUES ($1, 'mira_reads')`, someone)
	require.NoError(t, err)

	_, err = seeder(pool).Run(ctx, reviewEmail)
	require.ErrorContains(t, err, "signs in")
	require.Equal(t, 0, count(t, pool, `SELECT count(*)::int FROM library_items WHERE user_id = $1`, someone))
}

// Every line the seed writes passes the word filter.
func TestSeedTextPassesTheWordFilter(t *testing.T) {
	require.NoError(t, moderation.CheckHandle(reviewseed.ReviewHandle))
	require.NoError(t, moderation.CheckHandle(reviewseed.FriendHandle))
	require.True(t, moderation.Allowed(moderation.SurfaceProfileName, reviewseed.ReviewFirstName+" "+reviewseed.ReviewLastName))
	require.True(t, moderation.Allowed(moderation.SurfaceProfileName, reviewseed.FriendFirstName))
	require.True(t, moderation.Allowed(moderation.SurfaceGroupName, reviewseed.GroupName))
	require.True(t, moderation.Allowed(moderation.SurfaceBoardPost, reviewseed.PostBody))
	require.True(t, moderation.Allowed(moderation.SurfaceBoardComment, reviewseed.FriendCommentBody))
	require.True(t, moderation.Allowed(moderation.SurfaceBoardComment, reviewseed.ReviewCommentBody))
	for _, m := range reviewseed.GroupMessages {
		require.True(t, moderation.Allowed(moderation.SurfaceGroupMessage, m.Body), m.Body)
		require.NotContains(t, m.Body, "@")
	}
}
