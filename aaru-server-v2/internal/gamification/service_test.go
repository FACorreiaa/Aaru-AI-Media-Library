package gamification

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/testdb"
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fixture is a fresh database with one user, standing in for LibraryHarness: library rows are
// written with plain SQL and their points recorded through RecordLibraryWrite, as the library
// store does inside its transaction.
type fixture struct {
	t    *testing.T
	ctx  context.Context
	pool *pgxpool.Pool
	svc  *Service
	user uuid.UUID
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	pool := testdb.New(t)
	f := &fixture{t: t, ctx: context.Background(), pool: pool, svc: New(pool, slog.New(slog.NewTextHandler(io.Discard, nil)))}
	f.user = f.newUser("me_handle")
	return f
}

func (f *fixture) exec(sql string, args ...any) {
	f.t.Helper()
	_, err := f.pool.Exec(f.ctx, sql, args...)
	require.NoError(f.t, err)
}

func (f *fixture) newUser(handle string) uuid.UUID {
	id := uuid.New()
	f.exec(`INSERT INTO users (id) VALUES ($1)`, id)
	f.exec(`INSERT INTO profiles (user_id, handle) VALUES ($1, $2)`, id, handle)
	// As sign-up does: a new account has no history to backfill.
	f.exec(`INSERT INTO user_progress (user_id, evaluated_at) VALUES ($1, now())`, id)
	return id
}

// show is a show with one season of aired episodes.
func (f *fixture) show(status string, episodes int) uuid.UUID {
	title := uuid.New()
	f.exec(`INSERT INTO titles (id, type, title, status) VALUES ($1, 'show', 'Show', $2)`, title, status)
	for e := 1; e <= episodes; e++ {
		f.exec(`INSERT INTO show_episodes (id, title_id, season, episode, airs_at) VALUES ($1, $2, 1, $3, now() - interval '30 days')`,
			uuid.New(), title, e)
	}
	return title
}

func (f *fixture) movie(year *int) uuid.UUID {
	title := uuid.New()
	f.exec(`INSERT INTO titles (id, type, title, year) VALUES ($1, 'movie', 'Movie', $2)`, title, year)
	return title
}

func (f *fixture) item(user, title uuid.UUID, status string) uuid.UUID {
	id := uuid.New()
	f.exec(`INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at) VALUES ($1, $2, $3, $4, now(), now())`,
		id, user, title, status)
	return id
}

// write records one library write in its own transaction, as the library store does.
func (f *fixture) write(ctx context.Context, user uuid.UUID, facts *WriteFacts, scrobbled bool) uuid.UUID {
	f.t.Helper()
	action := f.action(user)
	err := pgx.BeginFunc(ctx, f.pool, func(tx pgx.Tx) error {
		return RecordLibraryWrite(ctx, tx, LibraryWrite{
			Facts: facts, Scrobbled: scrobbled, ActionID: action, UserID: user, RequestedZone: reqctx.TimeZone(ctx),
		})
	})
	require.NoError(f.t, err)
	f.svc.AfterWrite(ctx, user, &action)
	return action
}

// action is a journal row for points and badges to point at.
func (f *fixture) action(user uuid.UUID) uuid.UUID {
	id := uuid.New()
	f.exec(`INSERT INTO actions (id, user_id, actor, kind, summary, inverse) VALUES ($1, $2, 'user', 'test', 'test', '{}')`, id, user)
	return id
}

func keys(season int, episodes ...int) []core.EpisodeKey {
	out := make([]core.EpisodeKey, len(episodes))
	for i, e := range episodes {
		out[i] = core.EpisodeKey{Season: season, Episode: e}
	}
	return out
}

// tick inserts the episode rows and records the write.
func (f *fixture) tick(item uuid.UUID, kind string, ks []core.EpisodeKey, scrobbled bool) uuid.UUID {
	for _, k := range ks {
		f.exec(`INSERT INTO episode_progress (id, library_item_id, season, episode) VALUES ($1, $2, $3, $4)`, uuid.New(), item, k.Season, k.Episode)
	}
	facts := NewWriteFacts(kind)
	facts.Episodes(item, ks, nil)
	return f.write(f.ctx, f.user, facts, scrobbled)
}

func (f *fixture) untick(item uuid.UUID, kind string, ks []core.EpisodeKey) {
	for _, k := range ks {
		f.exec(`DELETE FROM episode_progress WHERE library_item_id = $1 AND season = $2 AND episode = $3`, item, k.Season, k.Episode)
	}
	facts := NewWriteFacts(kind)
	facts.Episodes(item, nil, ks)
	f.write(f.ctx, f.user, facts, false)
}

func (f *fixture) total(user uuid.UUID) int {
	f.t.Helper()
	total, err := f.svc.TotalPoints(f.ctx, user)
	require.NoError(f.t, err)
	return total
}

func (f *fixture) badgeIDs(user uuid.UUID) []string {
	f.t.Helper()
	earned, err := f.svc.EarnedBadges(f.ctx, user)
	require.NoError(f.t, err)
	var ids []string
	for _, b := range earned {
		ids = append(ids, b.Badge)
	}
	return ids
}

func TestTickEarnsOnceUntickTakesBackUndoRedoNetsOne(t *testing.T) {
	f := newFixture(t)
	item := f.item(f.user, f.show("returning", 3), "in_progress")
	ep := keys(1, 1)
	f.tick(item, "episode", ep, false)
	assert.Equal(t, 10, f.total(f.user))
	facts := NewWriteFacts("episode") // ticking again: the inverse is empty
	f.write(f.ctx, f.user, facts, false)
	assert.Equal(t, 10, f.total(f.user), "ticking again earns nothing")

	f.untick(item, "episode", ep)
	assert.Equal(t, 0, f.total(f.user))
	f.tick(item, "episode", ep, false)
	assert.Equal(t, 10, f.total(f.user))

	f.untick(item, "undo", ep)
	assert.Equal(t, 0, f.total(f.user))
	f.tick(item, "undo", ep, false)
	assert.Equal(t, 10, f.total(f.user), "undo then redo nets one award")

	cached := f.total(f.user)
	rebuilt, err := f.svc.RebuildTotal(f.ctx, f.user)
	require.NoError(t, err)
	assert.Equal(t, cached, rebuilt)
}

func TestFullSeasonEarnsItsBonusAndUndoTakesAllBack(t *testing.T) {
	f := newFixture(t)
	item := f.item(f.user, f.show("ended", 3), "in_progress")
	f.tick(item, "season", keys(1, 1, 2, 3), false)
	assert.Equal(t, 3*10+30, f.total(f.user))
	f.untick(item, "undo", keys(1, 1, 2, 3))
	assert.Equal(t, 0, f.total(f.user))
}

func TestDailyCapsHoldAndACappedAwardSpendsItsRoot(t *testing.T) {
	f := newFixture(t)
	eps := make([]int, 35)
	for i := range eps {
		eps[i] = i + 1
	}
	item := f.item(f.user, f.show("ended", 35), "in_progress")
	f.tick(item, "season", keys(1, eps...), false)
	assert.Equal(t, 300+30, f.total(f.user), "episodes stop at 300 a day; the season bonus has its own cap")
	var spent int
	require.NoError(t, f.pool.QueryRow(f.ctx, `SELECT count(*) FROM points_events WHERE user_id = $1 AND kind = 'episode'`, f.user).Scan(&spent))
	assert.Equal(t, 35, spent, "capped awards are written at 0 points")
}

func TestTheSameScrobbleTwiceAwardsOnceWithTheBonus(t *testing.T) {
	f := newFixture(t)
	item := f.item(f.user, f.show("ended", 3), "in_progress")
	f.tick(item, "episode", keys(1, 2), true)
	assert.Equal(t, 15, f.total(f.user))
	facts := NewWriteFacts("episode")
	facts.Episodes(item, keys(1, 2), nil) // a replayed scrobble re-sends the same tick
	f.write(f.ctx, f.user, facts, true)
	assert.Equal(t, 15, f.total(f.user), "a replayed scrobble earns nothing twice")
}

func TestImportsAndPlansEarnNothingAndNoStreakDay(t *testing.T) {
	f := newFixture(t)
	item := f.item(f.user, f.show("ended", 3), "in_progress")
	for _, kind := range []string{"import", "plan"} {
		facts := NewWriteFacts(kind)
		facts.Episodes(item, keys(1, 1, 2), nil)
		require.NoError(t, RecordLibraryWrite(f.ctx, f.pool, LibraryWrite{Facts: facts, ActionID: uuid.New(), UserID: f.user}))
	}
	assert.Equal(t, 0, f.total(f.user))
	days, err := f.svc.StreakDays(f.ctx, f.user)
	require.NoError(t, err)
	assert.Empty(t, days)
}

func TestFriendshipEarnsBothShortOneTakesBackRefriendingEarnsNothing(t *testing.T) {
	f := newFixture(t)
	ana := f.newUser("ana_handle")
	f.svc.FriendAdded(f.ctx, f.user, ana)
	assert.Equal(t, 20, f.total(f.user))
	assert.Equal(t, 20, f.total(ana))
	f.svc.FriendEnded(f.ctx, f.user, ana, time.Now().Add(-time.Hour))
	assert.Equal(t, 0, f.total(f.user))
	assert.Equal(t, 0, f.total(ana))
	f.svc.FriendAdded(f.ctx, ana, f.user)
	assert.Equal(t, 0, f.total(f.user), "the pair's points were spent")

	bob := f.newUser("bob_handle")
	f.svc.FriendAdded(f.ctx, f.user, bob)
	f.svc.FriendEnded(f.ctx, f.user, bob, time.Now().Add(-8*24*time.Hour))
	assert.Equal(t, 20, f.total(bob), "an old friendship keeps its points")
}

func TestStreakDayIsDatedInTheRequestZoneAndTheZoneIsKept(t *testing.T) {
	f := newFixture(t)
	zone, err := time.LoadLocation("Pacific/Kiritimati")
	require.NoError(t, err)
	item := f.item(f.user, f.show("ended", 3), "in_progress")
	f.exec(`INSERT INTO episode_progress (id, library_item_id, season, episode) VALUES ($1, $2, 1, 1)`, uuid.New(), item)
	facts := NewWriteFacts("episode")
	facts.Episodes(item, keys(1, 1), nil)
	f.write(reqctx.WithTimeZone(f.ctx, zone), f.user, facts, false)

	days, err := f.svc.StreakDays(f.ctx, f.user)
	require.NoError(t, err)
	require.Len(t, days, 1)
	assert.Equal(t, core.LocalDate(time.Now(), zone), days[0].Date)
	assert.Equal(t, "Pacific/Kiritimati", days[0].TimeZone)
	stored, err := f.svc.TimeZone(f.ctx, f.user)
	require.NoError(t, err)
	assert.Equal(t, "Pacific/Kiritimati", stored.String(), "a later request without the header uses the stored zone")

	progress, err := f.svc.Progress(reqctx.WithTimeZone(f.ctx, zone), f.user)
	require.NoError(t, err)
	assert.Equal(t, 1, progress.Streak.Current)
	assert.True(t, progress.Streak.Today)
	assert.Len(t, progress.Days, 7)
}

func (f *fixture) addFinishedMovie(year *int) uuid.UUID {
	item := f.item(f.user, f.movie(year), "finished")
	facts := NewWriteFacts("add")
	facts.Inserted(item, core.StatusFinished)
	return f.write(f.ctx, f.user, facts, false)
}

func TestALiveFinishEarnsUnseenBadgesOnce(t *testing.T) {
	f := newFixture(t)
	f.addFinishedMovie(nil)
	assert.Equal(t, 25, f.total(f.user))
	progress, err := f.svc.Progress(f.ctx, f.user)
	require.NoError(t, err)
	var unseen []uuid.UUID
	for _, b := range progress.Unseen {
		assert.Equal(t, OriginLive, b.Origin)
		unseen = append(unseen, b.ID)
	}
	assert.Contains(t, f.badgeIDs(f.user), "first_film")

	require.NoError(t, f.svc.MarkSeen(f.ctx, unseen, f.user))
	progress, err = f.svc.Progress(f.ctx, f.user)
	require.NoError(t, err)
	assert.Empty(t, progress.Unseen)

	again, err := f.svc.Evaluate(f.ctx, f.user, OriginLive, nil)
	require.NoError(t, err)
	assert.Empty(t, again)
}

func TestUndoingTheActionThatEarnedATierTakesItBack(t *testing.T) {
	f := newFixture(t)
	action := f.addFinishedMovie(nil)
	assert.Contains(t, f.badgeIDs(f.user), "first_film")
	// The undo removes the item; its finish is revoked through the facts.
	f.exec(`DELETE FROM library_items WHERE user_id = $1`, f.user)
	undo := f.action(f.user)
	f.svc.AfterUndo(f.ctx, f.user, action, undo)
	assert.NotContains(t, f.badgeIDs(f.user), "first_film")
}

func TestTheFirstRunIsOneBackfillAndImportedHistoryCounts(t *testing.T) {
	f := newFixture(t)
	f.item(f.user, f.movie(nil), "finished") // imported: no points
	// As if the account predates achievements: never evaluated, nothing earned.
	f.exec(`UPDATE user_progress SET evaluated_at = NULL WHERE user_id = $1`, f.user)
	worker := NewWorker(f.svc)
	worker.Pace = 0
	claimed := false
	for i := 0; i < 50 && !claimed; i++ {
		_, err := worker.Step(f.ctx)
		require.NoError(t, err)
		fresh, err := f.svc.IsFresh(f.ctx, f.user)
		require.NoError(t, err)
		claimed = !fresh
	}
	assert.True(t, claimed)
	earned, err := f.svc.EarnedBadges(f.ctx, f.user)
	require.NoError(t, err)
	require.NotEmpty(t, earned)
	assert.Equal(t, OriginBackfill, earned[0].Origin)
	assert.Contains(t, f.badgeIDs(f.user), "first_film")
}

func TestStreakMilestoneOncePerRun(t *testing.T) {
	f := newFixture(t)
	today := core.LocalDate(time.Now(), time.UTC)
	for back := 0; back < 7; back++ {
		date, _ := core.AddingDays(-back, today)
		f.exec(`INSERT INTO check_ins (user_id, local_date, time_zone, first_at) VALUES ($1, $2::text::date, 'UTC', now())`, f.user, date)
	}
	require.NoError(t, f.svc.StreakBonuses(f.ctx, f.user))
	require.NoError(t, f.svc.StreakBonuses(f.ctx, f.user))
	assert.Equal(t, 50, f.total(f.user))
	badges, err := f.svc.Evaluate(f.ctx, f.user, OriginLive, nil)
	require.NoError(t, err)
	var ids []string
	for _, b := range badges {
		ids = append(ids, b.Badge)
	}
	assert.Contains(t, ids, "streak")
}

func TestListensEarnOnlyFromTheLastDay(t *testing.T) {
	f := newFixture(t)
	now := time.Now()
	f.svc.ListensKept(f.ctx, f.user, []Listen{
		{ListenedAt: now.Add(-time.Hour), Artist: "A", Track: "One"},
		{ListenedAt: now.Add(-48 * time.Hour), Artist: "A", Track: "Two"},
	})
	f.svc.ListensKept(f.ctx, f.user, []Listen{{ListenedAt: now.Add(-time.Hour), Artist: "a", Track: "one"}})
	assert.Equal(t, 1, f.total(f.user), "a backlog earns nothing; the same play twice is kept once")
}

func TestFriendAchievementsHidePrivateBadgesAndRespectTheSwitch(t *testing.T) {
	f := newFixture(t)
	f.addFinishedMovie(nil)
	_, err := f.svc.InsertBadges(f.ctx, []TierDue{{Badge: "collector", Tier: 1}}, f.user, OriginLive, nil)
	require.NoError(t, err)
	level, badges, ok, err := f.svc.FriendAchievements(f.ctx, f.user)
	require.NoError(t, err)
	require.True(t, ok)
	assert.Equal(t, 1, level)
	var ids []string
	for _, b := range badges {
		ids = append(ids, b.Badge)
	}
	assert.Contains(t, ids, "first_film")
	assert.NotContains(t, ids, "collector", "owned items are never shown to friends")

	f.exec(`INSERT INTO social_settings (user_id, show_achievements_to_friends) VALUES ($1, false)`, f.user)
	_, _, ok, err = f.svc.FriendAchievements(f.ctx, f.user)
	require.NoError(t, err)
	assert.False(t, ok)
}

func befriend(f *fixture, a, b uuid.UUID) {
	low, high := a, b
	if low.String() > high.String() {
		low, high = high, low
	}
	f.exec(`INSERT INTO social_friendships (user_low, user_high, created_at) VALUES ($1, $2, now())`, low, high)
}

func join(f *fixture, user uuid.UUID) {
	f.exec(`INSERT INTO social_settings (user_id, leaderboard_opt_in) VALUES ($1, true)
		ON CONFLICT (user_id) DO UPDATE SET leaderboard_opt_in = true`, user)
}

func handles(board Leaderboard) []string {
	var out []string
	for _, e := range board.Entries {
		out = append(out, e.User.Handle)
	}
	return out
}

func TestNobodyAppearsUntilTheyJoinAndBlocksHideBothWays(t *testing.T) {
	f := newFixture(t)
	ana := f.newUser("ana_handle")
	befriend(f, f.user, ana)

	board, err := f.svc.Leaderboard(f.ctx, f.user, nil)
	require.NoError(t, err)
	assert.False(t, board.OptedIn)
	assert.Empty(t, board.Entries)

	join(f, f.user)
	board, err = f.svc.Leaderboard(f.ctx, f.user, nil)
	require.NoError(t, err)
	assert.Equal(t, []string{"me_handle"}, handles(board), "a friend who has not joined never appears")
	anaBoard, err := f.svc.Leaderboard(f.ctx, ana, nil)
	require.NoError(t, err)
	assert.Empty(t, anaBoard.Entries, "nor does anyone, to someone not joined")

	join(f, ana)
	board, err = f.svc.Leaderboard(f.ctx, f.user, nil)
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"me_handle", "ana_handle"}, handles(board))

	f.exec(`INSERT INTO social_blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, now())`, f.user, ana)
	board, err = f.svc.Leaderboard(f.ctx, f.user, nil)
	require.NoError(t, err)
	assert.Equal(t, []string{"me_handle"}, handles(board))
	anaBoard, err = f.svc.Leaderboard(f.ctx, ana, nil)
	require.NoError(t, err)
	assert.Equal(t, []string{"ana_handle"}, handles(anaBoard))
}

func TestFriendPointsStayOffTheBoardAndRanksFollowPoints(t *testing.T) {
	f := newFixture(t)
	ana := f.newUser("ana_handle")
	befriend(f, f.user, ana)
	f.svc.FriendAdded(f.ctx, f.user, ana)
	join(f, f.user)
	join(f, ana)
	f.addFinishedMovie(nil)

	board, err := f.svc.Leaderboard(f.ctx, f.user, nil)
	require.NoError(t, err)
	require.Len(t, board.Entries, 2)
	assert.Equal(t, f.user, board.Entries[0].User.ID)
	assert.Equal(t, 25, board.Entries[0].Points, "the friend award does not count")
	assert.Equal(t, 1, board.Entries[0].Rank)
	assert.Equal(t, 0, board.Entries[1].Points)
	progress, err := f.svc.Progress(f.ctx, f.user)
	require.NoError(t, err)
	assert.Equal(t, 25, progress.WeekPoints)

	bad := "bad"
	_, err = f.svc.Leaderboard(f.ctx, f.user, &bad)
	assert.Equal(t, ErrBadWeek, err)
}
