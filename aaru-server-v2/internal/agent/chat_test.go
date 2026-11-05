package agent_test

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/reqctx"
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// step is one scripted model call.
type step struct {
	response model.Response
	err      error
	// deltas stream first, on a streamingModel.
	deltas []string
	// during runs inside the call, after the deltas: a hang-up, say.
	during func()
	// block waits for the call's context to end and answers with its error.
	block bool
	// ended is told that error: canceled, or the ceiling's deadline.
	ended *error
}

// scriptedModel answers from a script and records what it was asked. Never a network call.
type scriptedModel struct {
	mu       sync.Mutex
	script   []step
	requests []model.Request
}

func (m *scriptedModel) Model() string { return "scripted" }
func (m *scriptedModel) Pricing() model.Pricing {
	return model.Pricing{InputPerMTok: 1, OutputPerMTok: 5}
}

func (m *scriptedModel) next(req model.Request) step {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requests = append(m.requests, req)
	if len(m.script) == 0 {
		return step{err: &model.ProviderError{Status: 500}}
	}
	s := m.script[0]
	m.script = m.script[1:]
	return s
}

func (s step) answer(ctx context.Context) (model.Response, error) {
	if s.during != nil {
		s.during()
	}
	if s.block {
		<-ctx.Done()
		if s.ended != nil {
			*s.ended = ctx.Err()
		}
		return model.Response{}, ctx.Err()
	}
	return s.response, s.err
}

func (m *scriptedModel) Complete(ctx context.Context, req model.Request) (model.Response, error) {
	return m.next(req).answer(ctx)
}

func (m *scriptedModel) calls() []model.Request {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]model.Request(nil), m.requests...)
}

func seenIn(req model.Request) string {
	var b strings.Builder
	b.WriteString(req.System)
	for _, turn := range req.Turns {
		for _, block := range turn.Content {
			b.Write(block)
		}
	}
	return b.String()
}

// everythingSeen is everything the model was shown, as one string, for "never saw X" checks.
func (m *scriptedModel) everythingSeen() string {
	var b strings.Builder
	for _, req := range m.calls() {
		b.WriteString(seenIn(req))
	}
	return b.String()
}

// streamingModel is a scriptedModel that delivers text piece by piece.
type streamingModel struct{ *scriptedModel }

func (m streamingModel) Stream(ctx context.Context, req model.Request, onText func(string)) (model.Response, error) {
	s := m.next(req)
	for _, d := range s.deltas {
		onText(d)
	}
	return s.answer(ctx)
}

type call struct {
	name  string
	input map[string]any
	id    string
}

func toolCalls(calls ...call) model.Response {
	blocks := make([]model.Block, len(calls))
	for i, c := range calls {
		input := c.input
		if input == nil {
			input = map[string]any{}
		}
		blocks[i], _ = json.Marshal(map[string]any{"type": "tool_use", "id": c.id, "name": c.name, "input": input})
	}
	return model.Response{Content: blocks, Stop: model.StopToolUse, InputTokens: 100, OutputTokens: 10}
}

func textResponse(text string) model.Response {
	block, _ := json.Marshal(map[string]any{"type": "text", "text": text})
	return model.Response{Content: []model.Block{block}, Stop: model.StopDone, InputTokens: 200, OutputTokens: 30}
}

func gate(inScope bool) step {
	r := toolCalls(call{"record_scope", map[string]any{"in_scope": inScope}, "gate"})
	r.InputTokens, r.OutputTokens = 11, 3
	return step{response: r}
}

func says(text string) step { return step{response: textResponse(text)} }

func tool(name string, input map[string]any) step {
	return step{response: toolCalls(call{name, input, "t-" + name})}
}

type turnFixture struct {
	*chatToolsFixture
	model *scriptedModel
	svc   *agent.ChatService
	chat  uuid.UUID
	sent  []agent.ChatEvent
}

func newTurnFixture(t *testing.T, script ...step) *turnFixture {
	t.Helper()
	f := &turnFixture{chatToolsFixture: newChatToolsFixture(t), model: &scriptedModel{script: script}}
	var mu sync.Mutex
	clock := f.now
	f.svc = &agent.ChatService{
		Store: f.store, Deps: f.deps(true), Model: f.model, Log: slog.New(slog.DiscardHandler),
		Now: func() time.Time {
			mu.Lock()
			defer mu.Unlock()
			clock = clock.Add(time.Second)
			return clock
		},
	}
	f.chat = f.newChat()
	return f
}

// streaming makes the model deliver text piece by piece.
func (f *turnFixture) streaming() { f.svc.Model = streamingModel{f.model} }

func (f *turnFixture) send(ctx context.Context, body string, hint agent.Hint) error {
	f.t.Helper()
	return f.svc.Turn(ctx, f.user, f.chat, body, hint, func(e agent.ChatEvent) { f.sent = append(f.sent, e) })
}

func (f *turnFixture) ask(body string) {
	f.t.Helper()
	require.NoError(f.t, f.send(f.ctx, body, agent.Hint{}))
}

func (f *turnFixture) kinds() []string {
	out := make([]string, len(f.sent))
	for i, e := range f.sent {
		out[i] = e.Type
	}
	return out
}

func (f *turnFixture) event(kind string) agent.ChatEvent {
	f.t.Helper()
	for _, e := range f.sent {
		if e.Type == kind {
			return e
		}
	}
	require.Failf(f.t, "no event", "no %s in %v", kind, f.kinds())
	return agent.ChatEvent{}
}

func (f *turnFixture) deltas() string {
	var b strings.Builder
	for _, e := range f.sent {
		if e.Type == agent.ChatEventDelta {
			b.WriteString(e.Text)
		}
	}
	return b.String()
}

type storedTurn struct {
	id         uuid.UUID
	state      string
	body       string
	components json.RawMessage
}

// lastTurn is the chat's newest agent turn.
func (f *turnFixture) lastTurn() storedTurn {
	f.t.Helper()
	var s storedTurn
	require.NoError(f.t, f.pool.QueryRow(f.ctx, `SELECT id, state, body, components FROM chat_turns
		WHERE chat_id = $1 AND role = 'agent' ORDER BY created_at DESC LIMIT 1`, f.chat).
		Scan(&s.id, &s.state, &s.body, &s.components))
	return s
}

func (f *turnFixture) turnCount() int {
	f.t.Helper()
	return f.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1`, f.chat)
}

func TestTurnEvents(t *testing.T) {
	f := newTurnFixture(t, gate(true), tool("read_my_library", nil), step{
		response: textResponse("You have nothing yet."), deltas: []string{"You have ", "nothing yet."},
	})
	f.streaming()
	f.ask("what's in my library?")

	assert.Equal(t, []string{"status", "delta", "delta", "done"}, f.kinds())
	assert.Equal(t, "Checking your library", f.sent[0].Text)
	assert.Equal(t, "You have ", f.sent[1].Text)
	assert.Equal(t, "nothing yet.", f.sent[2].Text)

	stored := f.lastTurn()
	assert.Equal(t, agent.TurnDone, stored.state)
	assert.Equal(t, "You have nothing yet.", stored.body)
	assert.Nil(t, stored.components)
	require.NotNil(t, f.sent[3].TurnID)
	assert.Equal(t, stored.id, *f.sent[3].TurnID)
}

func TestTextAcrossRoundsMatchesTheStream(t *testing.T) {
	first := toolCalls(call{"read_my_library", nil, "a"})
	first.Content = append(textResponse("Let me look.").Content, first.Content...)
	f := newTurnFixture(t, gate(true),
		step{response: first, deltas: []string{"Let me look."}},
		step{response: textResponse("Nothing yet."), deltas: []string{"Nothing yet."}})
	f.streaming()
	f.ask("what's in my library?")

	assert.Equal(t, "Let me look.\n\nNothing yet.", f.deltas())
	assert.Equal(t, f.deltas(), f.lastTurn().body, "what is stored is what was read")
}

func TestOffTopicNoMainCall(t *testing.T) {
	f := newTurnFixture(t, gate(false), says("should never be asked"))
	f.ask("what will the stock market do?")

	assert.Len(t, f.model.calls(), 1)
	assert.Equal(t, []string{"delta", "done"}, f.kinds())
	const refused = "I can only help with films, shows, anime, books, music, sport and your Aaru library."
	assert.Equal(t, refused, f.sent[0].Text)
	stored := f.lastTurn()
	assert.Equal(t, agent.TurnDone, stored.state)
	assert.Equal(t, refused, stored.body)
}

func TestGateErrorFailsClosed(t *testing.T) {
	f := newTurnFixture(t, step{err: &model.ProviderError{Status: 500}}, says("should never be asked"))
	f.ask("what's airing?")

	assert.Len(t, f.model.calls(), 1, "no main call")
	assert.Equal(t, []string{"error"}, f.kinds())
	assert.Equal(t, "try_again", f.sent[0].Code)
	assert.NotEmpty(t, f.sent[0].Text)
	assert.Equal(t, agent.TurnFailed, f.lastTurn().state)
}

func TestGateNoCallFailsClosed(t *testing.T) {
	f := newTurnFixture(t, says("in scope, I think"), says("should never be asked"))
	f.ask("what's airing?")

	assert.Len(t, f.model.calls(), 1)
	assert.Equal(t, "try_again", f.event("error").Code)
	assert.Equal(t, agent.TurnFailed, f.lastTurn().state)
}

func TestFollowUpGateSeesTurns(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Severance's first season is nine episodes."), gate(true), says("Ten."))
	f.ask("how long is Severance?")
	f.ask("e a segunda temporada?")

	calls := f.model.calls()
	require.Len(t, calls, 4)
	assert.Equal(t, "record_scope", calls[2].ToolChoice)
	seen := seenIn(calls[2])
	assert.Contains(t, seen, "how long is Severance?")
	assert.Contains(t, seen, "nine episodes")
	assert.Contains(t, seen, "e a segunda temporada?")
}

func TestMainCallSeesTheChatInOrder(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Nine."), gate(true), says("Ten."))
	f.ask("how long is Severance?")
	f.ask("and the second season?")

	turns := f.model.calls()[3].Turns
	require.Len(t, turns, 3)
	assert.Equal(t, model.RoleUser, turns[0].Role)
	assert.Contains(t, string(turns[0].Content[0]), "how long is Severance?")
	assert.Equal(t, model.RoleAssistant, turns[1].Role)
	assert.Contains(t, string(turns[1].Content[0]), "Nine.")
	assert.Equal(t, model.RoleUser, turns[2].Role)
	assert.Contains(t, string(turns[2].Content[0]), "and the second season?")
}

func TestTranscriptStartsWithTheUser(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("ok"))
	f.exec(`INSERT INTO chat_turns (id, chat_id, user_id, role, body, state, created_at, updated_at)
		VALUES ($1, $2, $3, 'agent', 'orphan', 'done', $4, $4)`, uuid.New(), f.chat, f.user, f.now.Add(-time.Hour))
	f.ask("next")

	turns := f.model.calls()[1].Turns
	require.Len(t, turns, 1)
	assert.Equal(t, model.RoleUser, turns[0].Role)
	assert.Contains(t, string(turns[0].Content[0]), "next")
}

func TestContextIsBounded(t *testing.T) {
	f := newTurnFixture(t)
	for i := range 20 {
		_, agentTurn, err := f.store.BeginTurn(f.ctx, f.chat, f.user, "q", f.now.Add(time.Duration(i-30)*time.Minute))
		require.NoError(t, err)
		body := "a"
		if i == 19 {
			body = "" // a failed turn has no words: it never reaches the model
		}
		require.NoError(t, f.store.FinishTurn(f.ctx, agentTurn, agent.TurnDone, body, nil, f.now))
	}
	f.model.script = []step{gate(true), says("ok")}
	f.ask("next")

	turns := f.model.calls()[1].Turns
	assert.Len(t, turns, agent.MaxChatContext) // 12 stored, one of them empty, plus this one
	assert.Equal(t, model.RoleUser, turns[0].Role)
	assert.Equal(t, model.RoleUser, turns[len(turns)-1].Role)
	for _, turn := range turns {
		for _, block := range turn.Content {
			assert.NotContains(t, string(block), `"text":""`)
		}
	}
}

func TestDisconnectStoresStopped(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	f := newTurnFixture(t)
	f.withHit("900")
	f.model.script = []step{
		gate(true),
		{response: toolCalls(
			call{"search_titles", map[string]any{"query": "hit", "kind": "movie"}, "a"},
			call{"apply_library_patch", map[string]any{"changes": []any{
				map[string]any{"op": "add", "ref": "r1", "status": "wishlist"},
			}}, "b"},
		)},
		{deltas: []string{"I added"}, during: cancel, block: true},
	}
	f.streaming()
	require.NoError(t, f.send(ctx, "add the hit", agent.Hint{}))

	stored := f.lastTurn()
	assert.Equal(t, agent.TurnStopped, stored.state)
	assert.Equal(t, "I added", stored.body)
	assert.Contains(t, string(stored.components), "actionId", "the undo of a write that stays")
	assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
	assert.NotContains(t, f.kinds(), "error")
	assert.NotContains(t, f.kinds(), "done")
}

// A shutdown must not leave a turn `streaming`: the chat would answer busy for StaleTurnAfter.
func TestStopStoresStoppedAndFreesTheChat(t *testing.T) {
	stop, shutDown := context.WithCancel(t.Context())
	defer shutDown()
	var ended error
	f := newTurnFixture(t, gate(true), step{deltas: []string{"Half an"}, during: shutDown, block: true, ended: &ended},
		gate(true), says("Back."))
	f.streaming()
	f.svc.Stop = stop
	// Only a turn the signal did not reach ever waits for this.
	f.svc.Ceiling = 20 * time.Second

	f.ask("tell me")

	require.ErrorIs(t, ended, context.Canceled, "the signal ended the call, not the ceiling")
	stored := f.lastTurn()
	assert.Equal(t, agent.TurnStopped, stored.state)
	assert.Equal(t, "Half an", stored.body)
	failure := f.event("error")
	assert.Equal(t, "try_again", failure.Code, "the client is still there")
	assert.Equal(t, "error", f.kinds()[len(f.sent)-1])
	assert.NotContains(t, f.kinds(), "done")

	// The next pod has its own stop signal.
	f.svc.Stop = t.Context()
	f.sent = nil
	require.NoError(t, f.send(f.ctx, "again", agent.Hint{}), "a new send on that chat is not busy")
	assert.Equal(t, agent.TurnDone, f.lastTurn().state)
}

// A write that went through before the stop keeps its Undo, on the event and on the stored turn.
func TestStopKeepsAWrite(t *testing.T) {
	stop, shutDown := context.WithCancel(t.Context())
	defer shutDown()
	f := newTurnFixture(t)
	f.withHit("900")
	f.model.script = []step{
		gate(true),
		{response: toolCalls(
			call{"search_titles", map[string]any{"query": "hit", "kind": "movie"}, "a"},
			call{"apply_library_patch", map[string]any{"changes": []any{
				map[string]any{"op": "add", "ref": "r1", "status": "wishlist"},
			}}, "b"},
		)},
		{during: shutDown, block: true},
	}
	f.svc.Stop = stop
	f.svc.Ceiling = 20 * time.Second
	f.ask("add the hit")

	assert.Equal(t, agent.TurnStopped, f.lastTurn().state)
	assert.Contains(t, string(f.lastTurn().components), "actionId")
	require.NotNil(t, f.event("components").ActionID)
	assert.Equal(t, "try_again", f.event("error").Code)
}

// A hang-up during a shutdown is still a hang-up: nobody is there to read an event.
func TestStopAfterAHangUpEmitsNothing(t *testing.T) {
	stop, shutDown := context.WithCancel(t.Context())
	defer shutDown()
	ctx, hangUp := context.WithCancel(t.Context())
	defer hangUp()
	f := newTurnFixture(t, gate(true), step{during: func() { hangUp(); shutDown() }, block: true})
	f.svc.Stop = stop

	require.NoError(t, f.send(ctx, "tell me", agent.Hint{}))

	assert.Equal(t, agent.TurnStopped, f.lastTurn().state)
	assert.NotContains(t, f.kinds(), "error")
}

func TestNoToolRunsAfterAHangUp(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	f := newTurnFixture(t)
	f.withHit("900")
	f.model.script = []step{gate(true), {
		during: cancel,
		response: toolCalls(
			call{"search_titles", map[string]any{"query": "hit", "kind": "movie"}, "a"},
			call{"apply_library_patch", map[string]any{"changes": []any{
				map[string]any{"op": "add", "ref": "r1", "status": "wishlist"},
			}}, "b"},
		),
	}}
	require.NoError(t, f.send(ctx, "add the hit", agent.Hint{}))

	assert.Equal(t, agent.TurnStopped, f.lastTurn().state)
	assert.Empty(t, f.sent, "not even a status: the tools never started")
	assert.Equal(t, 0, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
}

func TestTurnCeiling(t *testing.T) {
	assert.Less(t, agent.TurnCeiling, agent.StaleTurnAfter, "a running turn is never failed as stale")
	assert.Equal(t, 4*time.Minute, agent.TurnCeiling)

	f := newTurnFixture(t, gate(true), step{deltas: []string{"Half an"}, block: true})
	f.streaming()
	f.svc.Ceiling = 50 * time.Millisecond
	f.ask("what's airing?")

	assert.Equal(t, []string{"delta", "error"}, f.kinds())
	assert.Equal(t, "try_again", f.event("error").Code)
	stored := f.lastTurn()
	assert.Equal(t, agent.TurnFailed, stored.state)
	assert.Equal(t, "Half an", stored.body)
}

func TestPanicFailsTheTurn(t *testing.T) {
	f := newTurnFixture(t, gate(true), step{during: func() { panic("boom") }})
	f.ask("what's airing?")

	assert.Equal(t, "try_again", f.event("error").Code)
	assert.Equal(t, agent.TurnFailed, f.lastTurn().state)
}

func TestRestingAtCap(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Your 30th."))
	f.userTurns(f.user, 29, f.now)
	f.ask("one more")
	assert.Equal(t, agent.TurnDone, f.lastTurn().state, "29 replies today leaves room for one")
	calls := len(f.model.calls())
	turns := f.turnCount()
	f.sent = nil

	f.ask("and another")

	assert.Len(t, f.model.calls(), calls, "no gate and no model call")
	assert.Equal(t, turns, f.turnCount(), "a capped send stores nothing")
	assert.Equal(t, []string{"error"}, f.kinds())
	assert.Equal(t, "resting", f.sent[0].Code)
	assert.Equal(t, "Aaru is resting. Try again later.", f.sent[0].Text)
}

func TestRestingSharedWithMentions(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("no"))
	for range 15 {
		f.agentReply(f.user, "done", f.now)
	}
	f.userTurns(f.user, 15, f.now)
	f.ask("hello?")

	assert.Empty(t, f.model.calls(), "`@aaru` replies and chat turns share the cap")
	assert.Equal(t, "resting", f.event("error").Code)
}

func TestTurnCountsTowardMentions(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Hi."))
	f.ask("hello")

	load, err := f.store.Q.GroupAgentLoad(f.ctx, sqlc.GroupAgentLoadParams{
		Tagger: f.user, DayStart: dayStart(f.now), GroupID: uuid.New(), HourStart: f.now.Add(-time.Hour),
	})
	require.NoError(t, err)
	assert.EqualValues(t, 1, load.UserToday, "a turn the service stored counts toward @aaru's cap")
}

func TestTurnOtherUsersChat(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("no"))
	other, err := f.store.CreateChat(f.ctx, f.newUser())
	require.NoError(t, err)
	f.chat = other

	require.ErrorIs(t, f.send(f.ctx, "hello", agent.Hint{}), agent.ErrChatNotFound)
	assert.Empty(t, f.sent)
	assert.Empty(t, f.model.calls())
	assert.Equal(t, 0, f.turnCount())
}

func TestTurnBusy(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("no"))
	_, _, err := f.store.BeginTurn(f.ctx, f.chat, f.user, "first", f.now)
	require.NoError(t, err)

	require.ErrorIs(t, f.send(f.ctx, "second", agent.Hint{}), agent.ErrChatBusy)
	assert.Empty(t, f.sent)
	assert.Empty(t, f.model.calls())

	// At the cap too: the 30th turn still streaming is busy, not resting.
	f.userTurns(f.user, 30, f.now)
	require.ErrorIs(t, f.send(f.ctx, "third", agent.Hint{}), agent.ErrChatBusy)
	assert.Empty(t, f.sent)
}

func TestOutOfCredit(t *testing.T) {
	outOfCredit := &model.ProviderError{Status: 400, OutOfCredit: true}
	cases := map[string][]step{
		"at the gate": {{err: outOfCredit}},
		"main call":   {gate(true), {err: outOfCredit}},
	}
	for name, script := range cases {
		t.Run(name, func(t *testing.T) {
			f := newTurnFixture(t, script...)
			f.ask("what's airing?")
			assert.Equal(t, []string{"error"}, f.kinds())
			assert.Equal(t, "resting", f.sent[0].Code)
			assert.Equal(t, "Aaru is resting. Try again later.", f.sent[0].Text)
			assert.Equal(t, agent.TurnFailed, f.lastTurn().state)
		})
	}
}

func (f *turnFixture) withHits(ids ...string) {
	for _, id := range ids {
		f.withHit(id)
	}
}

func TestComponentsEvent(t *testing.T) {
	f := newTurnFixture(t)
	f.withHits("901", "902", "903", "904", "905")
	f.model.script = []step{
		gate(true),
		tool("search_titles", map[string]any{"query": "hit", "kind": "movie"}),
		tool("show_titles", map[string]any{"refs": []string{"r1", "r2", "r3", "r4", "r5"}}),
		says("Try these."),
	}
	f.ask("what should I watch?")

	assert.Equal(t, []string{"status", "delta", "components", "done"}, f.kinds())
	event := f.event("components")
	require.Len(t, event.Titles, agent.MaxCards)
	assert.Equal(t, "Title 901", event.Titles[0].Title)

	var stored struct {
		TitleIDs []uuid.UUID `json:"titleIds"`
	}
	require.NoError(t, json.Unmarshal(f.lastTurn().components, &stored))
	require.Len(t, stored.TitleIDs, agent.MaxCards)
	assert.Equal(t, event.Titles[0].ID, stored.TitleIDs[0])
}

func TestWriteInComponents(t *testing.T) {
	f := newTurnFixture(t)
	f.withHit("900")
	f.model.script = []step{
		gate(true),
		{response: toolCalls(
			call{"search_titles", map[string]any{"query": "hit", "kind": "movie"}, "a"},
			call{"apply_library_patch", map[string]any{"changes": []any{
				map[string]any{"op": "add", "ref": "r1", "status": "in_progress"},
			}}, "b"},
		)},
		says("Done."),
	}
	f.ask("add the hit")

	event := f.event("components")
	require.NotNil(t, event.ActionID)
	assert.False(t, strings.HasPrefix(event.ActionSummary, library.ChatAgentName+": "), event.ActionSummary)
	assert.Contains(t, event.ActionSummary, "Title 900")
	assert.Nil(t, event.Plan)
	var stored struct {
		ActionID      *uuid.UUID `json:"actionId"`
		ActionSummary string     `json:"actionSummary"`
	}
	require.NoError(t, json.Unmarshal(f.lastTurn().components, &stored))
	assert.Equal(t, event.ActionID, stored.ActionID)
	assert.Equal(t, event.ActionSummary, stored.ActionSummary)
}

// The whole turn, whichever way the model spreads the calls.
func TestTurnAppliesOneChange(t *testing.T) {
	search := call{"search_titles", map[string]any{"query": "hit", "kind": "movie"}, "a"}
	add := func(ref, id string) call {
		return call{"apply_library_patch", map[string]any{"changes": []any{
			map[string]any{"op": "add", "ref": ref, "status": "finished"},
		}}, id}
	}
	for name, script := range map[string][]step{
		"in one round": {
			gate(true), {response: toolCalls(search, add("r1", "b"), add("r2", "c"))}, says("One done."),
		},
		"across rounds": {
			gate(true), {response: toolCalls(search, add("r1", "b"))}, {response: toolCalls(add("r2", "c"))}, says("One done."),
		},
	} {
		t.Run(name, func(t *testing.T) {
			f := newTurnFixture(t, script...)
			f.withHits("910", "911")
			f.ask("mark both as watched")

			assert.Equal(t, 1, f.count(`SELECT count(*)::int FROM library_items WHERE user_id = $1`, f.user))
			actions, err := f.lib.Store.Actions(f.ctx, f.user, 10)
			require.NoError(t, err)
			require.Len(t, actions, 1, "one write in the journal")
			event := f.event("components")
			require.NotNil(t, event.ActionID)
			assert.Equal(t, actions[0].ID, *event.ActionID, "the Undo is the first write's")
			assert.Contains(t, event.ActionSummary, "Title 910")
			assert.Contains(t, f.model.everythingSeen(), "Nothing was changed", "the model is told")
		})
	}
}

func TestPlanInComponents(t *testing.T) {
	f := newTurnFixture(t)
	f.withHits("901", "902")
	f.model.script = []step{
		gate(true),
		{response: toolCalls(
			call{"search_titles", map[string]any{"query": "hit", "kind": "movie"}, "a"},
			call{"apply_library_patch", map[string]any{"changes": []any{
				map[string]any{"op": "add", "ref": "r1"}, map[string]any{"op": "add", "ref": "r2"},
			}}, "b"},
		)},
		says("It needs your yes in Aaru."),
	}
	f.ask("add both")

	event := f.event("components")
	require.NotNil(t, event.Plan)
	assert.Nil(t, event.ActionID)
	var stored struct {
		PlanID *uuid.UUID `json:"planId"`
	}
	require.NoError(t, json.Unmarshal(f.lastTurn().components, &stored))
	assert.Equal(t, &event.Plan.ID, stored.PlanID)
}

func TestUsageMetered(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Hi."))
	f.ask("hello")

	usage, err := agent.UsageOn(f.ctx, f.store.Q, f.user, f.now)
	require.NoError(t, err)
	assert.Equal(t, 2, usage.Requests)
	assert.Equal(t, 11+200, usage.InputTokens)
	assert.Equal(t, 3+30, usage.OutputTokens)
	assert.Positive(t, usage.CostMicros)
}

func TestUsageMeteredWhenOffTopic(t *testing.T) {
	f := newTurnFixture(t, gate(false))
	f.ask("stocks?")

	usage, err := agent.UsageOn(f.ctx, f.store.Q, f.user, f.now)
	require.NoError(t, err)
	assert.Equal(t, 1, usage.Requests)
}

func TestSystemPrompt(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Hi."))
	stranger := f.newUser()
	f.seed(stranger, "BBB", 1)
	title, err := f.kit.Resolver().Resolve(f.ctx, *movieRef("900"), nil)
	require.NoError(t, err)
	lisbon, err := time.LoadLocation("Europe/Lisbon")
	require.NoError(t, err)

	ctx := reqctx.WithTimeZone(f.ctx, lisbon)
	require.NoError(t, f.send(ctx, "is this any good?", agent.Hint{Screen: "title", TitleID: &title.ID}))

	system := f.model.calls()[1].System
	assert.Contains(t, system, "2026-11-04")
	assert.Contains(t, system, "Europe/Lisbon")
	assert.Contains(t, system, "Title 900")
	assert.Contains(t, system, "not started it", "the spoiler guard reads the user's own progress")
	assert.Contains(t, system, "films, shows, anime, books, music, sport and your Aaru library")
	assert.Contains(t, system, "I can't see that yet")
	assert.NotContains(t, f.model.everythingSeen(), "BBB", "another user's data")
}

func TestSystemPromptDefaultsToUTC(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Hi."))
	f.ask("hello")

	assert.Contains(t, f.model.calls()[1].System, "UTC")
}

func TestHintUnknownDropped(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Hi."), gate(true), says("Hi."))
	require.NoError(t, f.send(f.ctx, "hello", agent.Hint{Screen: "evil"}))
	assert.NotContains(t, f.model.everythingSeen(), "evil")

	require.NoError(t, f.send(f.ctx, "hello", agent.Hint{Screen: "calendar"}))
	assert.Contains(t, f.model.calls()[3].System, "calendar screen")
}

func TestHintUnknownTitleDropped(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Hi."))
	missing := uuid.New()
	require.NoError(t, f.send(f.ctx, "hello", agent.Hint{TitleID: &missing}))

	assert.Equal(t, agent.TurnDone, f.lastTurn().state)
	assert.NotContains(t, f.model.calls()[1].System, "looking at")
}

func TestMaxRounds(t *testing.T) {
	f := newTurnFixture(t, gate(true),
		tool("read_my_library", nil), tool("read_my_library", nil), tool("read_my_library", nil), tool("read_my_library", nil),
		says("too late"))
	f.ask("what's in my library?")

	assert.Len(t, f.model.calls(), 1+agent.MaxRounds)
	stored := f.lastTurn()
	assert.Equal(t, agent.FailureReply, stored.body)
	assert.Equal(t, agent.TurnDone, stored.state)
	assert.Equal(t, agent.FailureReply, f.event("delta").Text)
}

func TestEmptyAnswerStoresFailureReply(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("  "))
	f.ask("hello")

	assert.Equal(t, agent.FailureReply, f.lastTurn().body)
}

func TestRefusal(t *testing.T) {
	f := newTurnFixture(t, gate(true), step{response: model.Response{Stop: model.StopRefusal}})
	f.ask("hello")

	assert.Equal(t, agent.RefusalReply, f.lastTurn().body)
	assert.Equal(t, agent.RefusalReply, f.event("delta").Text)
}

func TestTitleFromFirstTurn(t *testing.T) {
	f := newTurnFixture(t, gate(false), gate(false))
	f.ask("  " + strings.Repeat("é", 100) + "\n")

	chat, err := f.store.Chat(f.ctx, f.chat, f.user)
	require.NoError(t, err)
	require.NotNil(t, chat.Title)
	assert.Equal(t, strings.Repeat("é", 80), *chat.Title)

	f.ask("something else")
	chat, err = f.store.Chat(f.ctx, f.chat, f.user)
	require.NoError(t, err)
	assert.Equal(t, strings.Repeat("é", 80), *chat.Title, "only the first turn names a chat")
}
