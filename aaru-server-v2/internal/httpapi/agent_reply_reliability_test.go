package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/model"
	"context"
	"errors"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Go audit REL-001 / REL-002: an `@aaru` reply posts once and pays once, whatever happens to the
// attempt that runs it.

// blockingModel blocks until its context ends, as a hung provider would.
type blockingModel struct {
	once    sync.Once
	started chan struct{}
}

func newBlockingModel() *blockingModel { return &blockingModel{started: make(chan struct{})} }

func (m *blockingModel) Model() string          { return "blocking" }
func (m *blockingModel) Pricing() model.Pricing { return model.Pricing{} }

func (m *blockingModel) Complete(ctx context.Context, _ model.Request) (model.Response, error) {
	m.once.Do(func() { close(m.started) })
	<-ctx.Done()
	return model.Response{}, ctx.Err()
}

type replyRow struct {
	state    string
	attempts int
	err      *string
}

func (e *groupEnv) replyRow(t *testing.T) replyRow {
	t.Helper()
	var r replyRow
	require.NoError(t, e.pool.QueryRow(context.Background(),
		`SELECT state, attempts, error FROM agent_replies`).Scan(&r.state, &r.attempts, &r.err))
	return r
}

func TestAgentReplyAlreadyPostedFinishesWithoutAModelCall(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("A second answer.")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	mention := env.post(channel, "@aaru hello?")
	// An earlier attempt posted its answer, then failed before it could finish the row.
	_, err := env.server.Groups.PostAgentReply(context.Background(), uuid.MustParse(group), uuid.MustParse(general),
		uuid.MustParse(mention["id"].(string)), "The first answer.", nil, nil)
	require.NoError(t, err)

	worked, err := env.replies(m, nil).RunNext(context.Background())
	require.NoError(t, err)
	assert.True(t, worked)
	assert.Empty(t, m.calls(), "no second model call")
	replies := agentMessages(items(t, env.send(http.MethodGet, channel+"/messages", nil)))
	require.Len(t, replies, 1)
	assert.Equal(t, "The first answer.", replies[0]["body"])
	assert.Equal(t, "done", env.replyRow(t).state)
}

func TestAgentReplyCancelledMidCallGoesBackUncounted(t *testing.T) {
	m := newBlockingModel()
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	env.post(channelPath(group, general), "@aaru hello?")
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		<-m.started
		cancel()
	}()
	worked, err := env.replies(m, nil).RunNext(ctx)
	assert.True(t, worked)
	require.ErrorIs(t, err, context.Canceled)
	row := env.replyRow(t)
	assert.Equal(t, "queued", row.state)
	assert.Equal(t, 0, row.attempts, "a shutdown is not the mention's attempt")
	assert.Empty(t, agentMessages(items(t, env.send(http.MethodGet, channelPath(group, general)+"/messages", nil))))
}

func TestAgentReplyThatHangsFailsInsideItsLease(t *testing.T) {
	m := newBlockingModel()
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	env.post(channelPath(group, general), "@aaru hello?")
	replies := env.replies(m, nil)
	replies.Deadline = 100 * time.Millisecond
	started := time.Now()
	worked, err := replies.RunNext(context.Background())
	require.NoError(t, err)
	assert.True(t, worked)
	assert.Less(t, time.Since(started), agent.Lease)
	row := env.replyRow(t)
	assert.Equal(t, "queued", row.state, "retried, not left running past its lease")
	assert.Equal(t, 1, row.attempts)
	require.NotNil(t, row.err)
	assert.Contains(t, *row.err, "deadline")
}

func TestAgentReplyExpiredOnItsLastAttemptFailsOnce(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("Too late.")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	env.post(channel, "@aaru hello?")
	// The process died under the last attempt: running, lease run out, no attempts left.
	_, err := env.pool.Exec(context.Background(), `UPDATE agent_replies SET state = 'running', attempts = $1,
		locked_until = now() - interval '1 minute'`, agent.MaxAttempts)
	require.NoError(t, err)

	replies := env.replies(m, nil)
	for range 2 {
		worked, err := replies.RunNext(context.Background())
		require.NoError(t, err)
		assert.False(t, worked, "never leased again")
	}
	assert.Empty(t, m.calls())
	row := env.replyRow(t)
	assert.Equal(t, "failed", row.state)
	bodies := []any{}
	for _, reply := range agentMessages(items(t, env.send(http.MethodGet, channel+"/messages", nil))) {
		bodies = append(bodies, reply["body"])
	}
	assert.Equal(t, []any{agent.FailureReply}, bodies)
}

func TestAgentReplyPanicIsTheAttemptsFailure(t *testing.T) {
	m := &panickingModel{}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	env.post(channelPath(group, general), "@aaru hello?")
	worked, err := env.replies(m, nil).RunNext(context.Background())
	require.NoError(t, err)
	assert.True(t, worked)
	row := env.replyRow(t)
	assert.Equal(t, "queued", row.state)
	assert.Equal(t, 1, row.attempts)
	require.NotNil(t, row.err)
	assert.Contains(t, *row.err, "panic")
}

type panickingModel struct{}

func (panickingModel) Model() string          { return "panicking" }
func (panickingModel) Pricing() model.Pricing { return model.Pricing{} }

func (panickingModel) Complete(context.Context, model.Request) (model.Response, error) {
	panic(errors.New("provider decoder bug"))
}
