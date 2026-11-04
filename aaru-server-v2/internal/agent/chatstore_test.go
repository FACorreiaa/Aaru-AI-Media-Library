package agent_test

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type chatFixture struct {
	t     *testing.T
	ctx   context.Context
	pool  *pgxpool.Pool
	store *agent.ChatStore
	user  uuid.UUID
	now   time.Time
}

func newChatFixture(t *testing.T) *chatFixture {
	t.Helper()
	pool := testdb.New(t)
	f := &chatFixture{
		t: t, ctx: context.Background(), pool: pool, store: &agent.ChatStore{Q: sqlc.New(pool)},
		now: time.Date(2026, 11, 4, 12, 0, 0, 0, time.UTC),
	}
	f.user = f.newUser()
	return f
}

func (f *chatFixture) exec(sql string, args ...any) {
	f.t.Helper()
	_, err := f.pool.Exec(f.ctx, sql, args...)
	require.NoError(f.t, err)
}

func (f *chatFixture) newUser() uuid.UUID {
	id := uuid.New()
	f.exec(`INSERT INTO users (id) VALUES ($1)`, id)
	return id
}

func (f *chatFixture) newChat() uuid.UUID {
	f.t.Helper()
	id, err := f.store.CreateChat(f.ctx, f.user)
	require.NoError(f.t, err)
	return id
}

func (f *chatFixture) count(sql string, args ...any) int {
	f.t.Helper()
	var n int
	require.NoError(f.t, f.pool.QueryRow(f.ctx, sql, args...).Scan(&n))
	return n
}

func TestBeginTurnBusy(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()
	_, _, err := f.store.BeginTurn(f.ctx, chat, f.user, "hello", f.now)
	require.NoError(t, err)

	_, _, err = f.store.BeginTurn(f.ctx, chat, f.user, "again", f.now.Add(time.Minute))
	assert.ErrorIs(t, err, agent.ErrChatBusy)
	assert.Equal(t, 2, f.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1`, chat), "a refused turn leaves nothing behind")
}

func TestBeginTurnAfterFinish(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()
	_, agentTurn, err := f.store.BeginTurn(f.ctx, chat, f.user, "hello", f.now)
	require.NoError(t, err)
	require.NoError(t, f.store.FinishTurn(f.ctx, agentTurn, agent.TurnDone, "hi", []byte(`[{"type":"x"}]`), f.now))

	_, _, err = f.store.BeginTurn(f.ctx, chat, f.user, "again", f.now.Add(time.Second))
	require.NoError(t, err)

	turns, err := f.store.RecentTurns(f.ctx, chat, 10)
	require.NoError(t, err)
	require.Len(t, turns, 4)
	assert.Equal(t, []string{"user", "agent", "user", "agent"}, []string{turns[0].Role, turns[1].Role, turns[2].Role, turns[3].Role})
	assert.Equal(t, "hi", turns[1].Body)
	assert.JSONEq(t, `[{"type":"x"}]`, string(turns[1].Components))
	assert.Equal(t, agent.TurnStreaming, turns[3].State)
	assert.Equal(t, agent.TurnDone, turns[0].State)

	last, err := f.store.RecentTurns(f.ctx, chat, 2)
	require.NoError(t, err)
	require.Len(t, last, 2)
	assert.Equal(t, "again", last[0].Body, "limit keeps the newest, oldest first")
}

func TestBeginTurnClearsStale(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()
	_, stale, err := f.store.BeginTurn(f.ctx, chat, f.user, "hello", f.now)
	require.NoError(t, err)

	_, _, err = f.store.BeginTurn(f.ctx, chat, f.user, "again", f.now.Add(agent.StaleTurnAfter+time.Second))
	require.NoError(t, err)

	var state string
	require.NoError(t, f.pool.QueryRow(f.ctx, `SELECT state FROM chat_turns WHERE id = $1`, stale).Scan(&state))
	assert.Equal(t, agent.TurnFailed, state)
}

func TestChatOtherUser(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()

	got, err := f.store.Chat(f.ctx, chat, f.newUser())
	require.NoError(t, err)
	assert.Nil(t, got)

	got, err = f.store.Chat(f.ctx, uuid.New(), f.user)
	require.NoError(t, err)
	assert.Nil(t, got)

	got, err = f.store.Chat(f.ctx, chat, f.user)
	require.NoError(t, err)
	require.NotNil(t, got)
	assert.Equal(t, chat, got.ID)
}

func TestBeginTurnOtherUsersChat(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()
	_, _, err := f.store.BeginTurn(f.ctx, chat, f.newUser(), "hello", f.now)
	assert.Error(t, err)
	assert.NotErrorIs(t, err, agent.ErrChatBusy)
	assert.Zero(t, f.count(`SELECT count(*)::int FROM chat_turns`))
}

func TestUserDeleteCascades(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()
	_, _, err := f.store.BeginTurn(f.ctx, chat, f.user, "hello", f.now)
	require.NoError(t, err)

	f.exec(`DELETE FROM users WHERE id = $1`, f.user)
	assert.Zero(t, f.count(`SELECT count(*)::int FROM chats WHERE id = $1`, chat))
	assert.Zero(t, f.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1`, chat))
}

// agentReply inserts one @aaru reply by user in state, with the group, channel and message it needs.
func (f *chatFixture) agentReply(user uuid.UUID, state string, at time.Time) {
	f.t.Helper()
	group, channel, message := uuid.New(), uuid.New(), uuid.New()
	f.exec(`INSERT INTO groups (id, name, created_at, updated_at) VALUES ($1, 'g', $2, $2)`, group, at)
	f.exec(`INSERT INTO group_channels (id, group_id, kind, name, position, is_default, created_at)
		VALUES ($1, $2, 'text', 'general', 0, true, $3)`, channel, group, at)
	f.exec(`INSERT INTO group_messages (id, channel_id, author_id, body, created_at) VALUES ($1, $2, $3, 'hi', $4)`,
		message, channel, user, at)
	f.exec(`INSERT INTO agent_replies (id, message_id, group_id, channel_id, tagger_id, state, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $7)`, uuid.New(), message, group, channel, user, state, at)
}

// userTurns inserts n finished chat turns by the user at at, in a chat of their own.
func (f *chatFixture) userTurns(user uuid.UUID, n int, at time.Time) {
	f.t.Helper()
	chat := uuid.New()
	f.exec(`INSERT INTO chats (id, user_id) VALUES ($1, $2)`, chat, user)
	for range n {
		f.exec(`INSERT INTO chat_turns (id, chat_id, user_id, role, body, state, created_at, updated_at)
			VALUES ($1, $2, $3, 'user', 'q', 'done', $4, $4)`, uuid.New(), chat, user, at)
	}
}

func TestRepliesTodayShared(t *testing.T) {
	f := newChatFixture(t)
	today := f.now
	yesterday := dayStart(f.now).Add(-time.Hour)
	f.agentReply(f.user, "done", today)
	f.agentReply(f.user, "failed", today)
	f.agentReply(f.user, "capped", today) // a note, not a reply
	f.agentReply(f.user, "done", yesterday)
	f.userTurns(f.user, 3, today)
	f.userTurns(f.user, 2, yesterday)
	other := f.newUser()
	f.agentReply(other, "done", today)
	f.userTurns(other, 4, today)

	n, err := f.store.RepliesToday(f.ctx, f.user, f.now)
	require.NoError(t, err)
	assert.Equal(t, 5, n)
}

func TestGroupAgentLoadCountsChat(t *testing.T) {
	f := newChatFixture(t)
	f.agentReply(f.user, "done", f.now)
	f.userTurns(f.user, 29, f.now)
	f.userTurns(f.user, 5, dayStart(f.now).Add(-time.Hour))

	load, err := f.store.Q.GroupAgentLoad(f.ctx, sqlc.GroupAgentLoadParams{
		Tagger: f.user, DayStart: dayStart(f.now), GroupID: uuid.New(), HourStart: f.now.Add(-time.Hour),
	})
	require.NoError(t, err)
	assert.EqualValues(t, 30, load.UserToday, "30 chat turns and replies cap @aaru")
}

func TestChatPlanSpendsCapture(t *testing.T) {
	f := newChatFixture(t)
	since := dayStart(f.now)
	captures := &capture.Store{Q: f.store.Q}
	plan := func(spends bool) {
		f.exec(`INSERT INTO agent_plans (id, user_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at, spends_capture)
			VALUES ($1, $2, 'aaru', 'pending', 's', '[]', '{}', '{}', '{}', $3, $4, $5)`,
			uuid.New(), f.user, f.now, f.now.Add(time.Hour), spends)
	}
	before, err := captures.Captures(f.ctx, f.user, since)
	require.NoError(t, err)

	plan(false)
	got, err := captures.Captures(f.ctx, f.user, since)
	require.NoError(t, err)
	assert.Equal(t, before, got, "a plan that spends nothing adds nothing")

	plan(true)
	got, err = captures.Captures(f.ctx, f.user, since)
	require.NoError(t, err)
	assert.Equal(t, before+1, got)

	n, err := f.store.Q.BillingCapturesSince(f.ctx, sqlc.BillingCapturesSinceParams{UserID: f.user, CreatedAt: since})
	require.NoError(t, err)
	assert.EqualValues(t, before+1, n)

	got, err = captures.Captures(f.ctx, f.user, f.now.Add(time.Minute))
	require.NoError(t, err)
	assert.Equal(t, before, got, "counted from the plan's creation time")
}

func TestDeleteAllAndExport(t *testing.T) {
	f := newChatFixture(t)
	chat := f.newChat()
	_, agentTurn, err := f.store.BeginTurn(f.ctx, chat, f.user, "hello", f.now)
	require.NoError(t, err)
	require.NoError(t, f.store.FinishTurn(f.ctx, agentTurn, agent.TurnStopped, "par", nil, f.now))
	other := f.newUser()
	f.userTurns(other, 1, f.now)

	out, err := f.store.ForExport(f.ctx, f.user)
	require.NoError(t, err)
	require.Len(t, out, 1)
	require.Len(t, out[0].Turns, 2)
	assert.Equal(t, "hello", out[0].Turns[0].Body)
	assert.Equal(t, agent.TurnStopped, out[0].Turns[1].State)

	require.NoError(t, f.store.DeleteAll(f.ctx, f.user))
	out, err = f.store.ForExport(f.ctx, f.user)
	require.NoError(t, err)
	assert.Empty(t, out)
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM chat_turns WHERE user_id = $1`, other), "only the user's own")
}

func dayStart(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
