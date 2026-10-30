package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/model"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AgentTests.swift, the group-reply part: `@aaru` in groups (GRP-010 / GRP-011). The wire-body
// tests live with the Anthropic provider in internal/model.

// scriptedModel answers from a script and records what it was asked. Never a network call.
type scriptedModel struct {
	mu       sync.Mutex
	script   []model.Response
	requests []model.Request
}

func (m *scriptedModel) Model() string          { return "scripted" }
func (m *scriptedModel) Pricing() model.Pricing { return model.Pricing{} }

func (m *scriptedModel) Complete(_ context.Context, req model.Request) (model.Response, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requests = append(m.requests, req)
	if len(m.script) == 0 {
		return model.Response{}, &model.ProviderError{Status: 500}
	}
	next := m.script[0]
	m.script = m.script[1:]
	return next, nil
}

func (m *scriptedModel) calls() []model.Request {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]model.Request(nil), m.requests...)
}

// everythingSeen is everything the model was shown, as one string, for "never saw X" checks.
func (m *scriptedModel) everythingSeen() string {
	var b strings.Builder
	for _, req := range m.calls() {
		b.WriteString(req.System)
		for _, turn := range req.Turns {
			for _, block := range turn.Content {
				b.Write(block)
			}
		}
	}
	return b.String()
}

func toolResponse(name string, input map[string]any, id string) model.Response {
	if input == nil {
		input = map[string]any{}
	}
	block, _ := json.Marshal(map[string]any{"type": "tool_use", "id": id, "name": name, "input": input})
	return model.Response{Content: []model.Block{block}, Stop: model.StopToolUse, InputTokens: 100, OutputTokens: 10}
}

func textResponse(text string) model.Response {
	block, _ := json.Marshal(map[string]any{"type": "text", "text": text})
	return model.Response{Content: []model.Block{block}, Stop: model.StopDone, InputTokens: 200, OutputTokens: 30}
}

func newAgentEnv(t *testing.T, m model.Provider) *groupEnv {
	return newGroupEnv(t, func(d *Deps) { d.Model = m })
}

func (e *groupEnv) replies(m model.Provider, now func() time.Time) *agent.ReplyService {
	return &agent.ReplyService{
		Groups: e.server.Groups, Catalog: e.server.Catalog, Library: e.server.Library, Model: m, Now: now,
	}
}

func agentMessages(items []map[string]any) []map[string]any {
	out := []map[string]any{}
	for _, m := range items {
		if m["fromAgent"] == true {
			out = append(out, m)
		}
	}
	return out
}

func TestAgentToolsOnlyRead(t *testing.T) {
	names := []string{}
	for _, tool := range agent.GroupToolDefinitions {
		names = append(names, tool.Name)
	}
	assert.ElementsMatch(t, []string{"search_titles", "title_details", "list_airs", "read_my_library", "show_titles"}, names)
}

func TestAgentReplyUsesOnlyTheTaggersLibrary(t *testing.T) {
	m := &scriptedModel{script: []model.Response{
		toolResponse("read_my_library", nil, "a"),
		toolResponse("show_titles", map[string]any{"refs": []string{"r1"}}, "b"),
		textResponse("Heat is waiting on your list."),
	}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	ana := env.friend(env.user)
	group, general := env.createGroup("Film club")
	env.join(ana, group)
	assert.Equal(t, true, env.get("/v1/groups/" + group)["agent"])
	// The owner's library holds Arrival; Ana's holds Heat.
	env.add("movie", env.stubMovie("Arrival"))
	heat := env.stubMovie("Heat")
	rec := env.send(http.MethodPost, "/v1/library/items",
		map[string]any{"mediaRef": map[string]any{"type": "movie", "ids": map[string]string{"tmdb": heat}}}, ana.Token)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	channel := channelPath(group, general)
	env.post(channel, "I loved Arrival")
	mention := env.post(channel, "@aaru what should I watch tonight?", ana.Token)
	assert.Equal(t, true, mention["mentionsAgent"])

	replies := env.replies(m, nil)
	ctx := context.Background()
	worked, err := replies.RunNext(ctx)
	require.NoError(t, err)
	assert.True(t, worked)
	worked, err = replies.RunNext(ctx)
	require.NoError(t, err)
	assert.False(t, worked)

	list := items(t, env.send(http.MethodGet, channel+"/messages", nil))
	reply := list[len(list)-1]
	assert.Equal(t, true, reply["fromAgent"])
	assert.Nil(t, reply["author"])
	assert.Equal(t, mention["id"], reply["replyTo"])
	assert.Equal(t, "Heat is waiting on your list.", reply["body"])
	components := maps(reply["components"])
	require.NotEmpty(t, components)
	assert.Equal(t, "Heat", components[0]["title"].(map[string]any)["title"])
	assert.Len(t, agentMessages(list), 1)

	// The model saw the chat (where the owner named Arrival) but never the owner's library.
	seen := m.everythingSeen()
	assert.Contains(t, seen, "Heat")
	assert.Contains(t, seen, "I loved Arrival")
	assert.NotContains(t, seen, "Arrival (2001)")
	assert.Contains(t, m.calls()[0].System, "@"+ana.Handle)

	// Three calls metered to the tagger, none to anyone else.
	q := sqlc.New(env.pool)
	usage, err := agent.UsageOn(ctx, q, ana.uid, time.Now())
	require.NoError(t, err)
	assert.Equal(t, agent.Usage{Requests: 3, InputTokens: 400, OutputTokens: 50}, usage)
	mine, err := agent.UsageOn(ctx, q, env.user, time.Now())
	require.NoError(t, err)
	assert.Equal(t, 0, mine.Requests)
}

func TestAgentOverTheHourlyCapRestsOnceWithoutAModelCall(t *testing.T) {
	m := &scriptedModel{}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	for number := 1; number <= groups.AgentHourlyCapPerGroup+2; number++ {
		env.post(channel, fmt.Sprintf("@aaru question %d", number))
	}
	agentReplies := agentMessages(items(t, env.send(http.MethodGet, channel+"/messages", nil)))
	require.Len(t, agentReplies, 1)
	assert.Equal(t, groups.RestingNote, agentReplies[0]["body"])
	assert.Empty(t, m.calls())
}

func TestAgentRefusalGetsAShortReply(t *testing.T) {
	m := &scriptedModel{script: []model.Response{{Stop: model.StopRefusal, InputTokens: 5}}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	env.post(channel, "@aaru something odd")
	worked, err := env.replies(m, nil).RunNext(context.Background())
	require.NoError(t, err)
	assert.True(t, worked)
	list := items(t, env.send(http.MethodGet, channel+"/messages", nil))
	assert.Equal(t, agent.RefusalReply, list[len(list)-1]["body"])
}

func TestAgentRepeatedFailuresEndInOneApology(t *testing.T) {
	m := &scriptedModel{}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	env.post(channel, "@aaru hello?")
	// Each retry waits; a clock that jumps ahead lets the next attempt claim it.
	clock := time.Now()
	replies := env.replies(m, func() time.Time { return clock })
	ctx := context.Background()
	for range agent.MaxAttempts {
		worked, err := replies.RunNext(ctx)
		require.NoError(t, err)
		assert.True(t, worked)
		clock = clock.Add(600 * time.Second)
	}
	worked, err := replies.RunNext(ctx)
	require.NoError(t, err)
	assert.False(t, worked)
	bodiesFromAgent := []any{}
	for _, reply := range agentMessages(items(t, env.send(http.MethodGet, channel+"/messages", nil))) {
		bodiesFromAgent = append(bodiesFromAgent, reply["body"])
	}
	assert.Equal(t, []any{agent.FailureReply}, bodiesFromAgent)
	assert.Len(t, m.calls(), agent.MaxAttempts)
}

func TestAgentDisabledWithoutAModel(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	assert.Equal(t, false, env.get("/v1/groups/" + group)["agent"])
	env.post(channelPath(group, general), "@aaru hi")
	var queued int
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT count(*) FROM agent_replies`).Scan(&queued))
	assert.Equal(t, 0, queued)
}
