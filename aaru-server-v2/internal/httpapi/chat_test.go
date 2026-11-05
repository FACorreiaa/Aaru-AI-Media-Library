package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/telemetry"
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Chat with Aaru on /v1 (ASK-009). The turn itself is tested in internal/agent; these are the
// routes over it. Streaming tests go through a real listener, because a recorder cannot show when
// a frame was flushed or that a client hung up.

// chatMainCall is one call past the scope gate: it says words and answers.
type chatMainCall func(ctx context.Context, onText func(string)) (model.Response, error)

// chatModel lets the scope gate through and answers each main call from its script, streaming.
// Never a network call.
type chatModel struct {
	mu       sync.Mutex
	gates    int
	requests []model.Request
	script   []chatMainCall
}

func (m *chatModel) Model() string          { return "scripted" }
func (m *chatModel) Pricing() model.Pricing { return model.Pricing{} }

func (m *chatModel) Complete(context.Context, model.Request) (model.Response, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.gates++
	return toolResponse("record_scope", map[string]any{"in_scope": true}, "gate"), nil
}

func (m *chatModel) Stream(ctx context.Context, req model.Request, onText func(string)) (model.Response, error) {
	m.mu.Lock()
	m.requests = append(m.requests, req)
	if len(m.script) == 0 {
		m.mu.Unlock()
		return model.Response{}, &model.ProviderError{Status: 500}
	}
	next := m.script[0]
	m.script = m.script[1:]
	m.mu.Unlock()
	return next(ctx, onText)
}

func (m *chatModel) counts() (gates, mains int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.gates, len(m.requests)
}

// says is a main call that streams each piece and ends the turn.
func says(pieces ...string) chatMainCall {
	return func(_ context.Context, onText func(string)) (model.Response, error) {
		for _, p := range pieces {
			onText(p)
		}
		return textResponse(strings.Join(pieces, "")), nil
	}
}

// waits says first, then holds the call until release closes or the turn is cancelled.
func waits(first string, release <-chan struct{}, then string) chatMainCall {
	return func(ctx context.Context, onText func(string)) (model.Response, error) {
		onText(first)
		select {
		case <-release:
		case <-ctx.Done():
			return model.Response{}, ctx.Err()
		}
		onText(then)
		return textResponse(first + then), nil
	}
}

func callsTools(calls ...model.Response) chatMainCall {
	var blocks []model.Block
	for _, c := range calls {
		blocks = append(blocks, c.Content...)
	}
	return func(context.Context, func(string)) (model.Response, error) {
		return model.Response{Content: blocks, Stop: model.StopToolUse}, nil
	}
}

type chatEnv struct {
	*captureEnv
	model *chatModel
}

// newChatEnv is a signed-in user over a server with this model; nil leaves Aaru off.
func newChatEnv(t *testing.T, m *chatModel, tweak ...func(*Deps)) *chatEnv {
	t.Helper()
	env := newCaptureEnv(t, nil, nil)
	deps := env.server.Deps
	deps.Groups, deps.Realtime = nil, nil
	if m != nil {
		deps.Model = m
	}
	for _, f := range tweak {
		f(&deps)
	}
	env.server = New(deps)
	env.echo = env.server.Router(nil)
	return &chatEnv{captureEnv: env, model: m}
}

func (e *chatEnv) listen() *httptest.Server {
	e.t.Helper()
	srv := httptest.NewServer(e.echo)
	e.t.Cleanup(srv.Close)
	return srv
}

func (e *chatEnv) newChat(bearer string) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/chats", nil, bearer)
	require.Equal(e.t, http.StatusCreated, rec.Code, rec.Body.String())
	assert.Contains(e.t, rec.Header().Get("Content-Type"), "application/json")
	return decode[api.ChatCreated](e.t, rec).Id.String()
}

// openTurn posts a turn through the listener. A frame that never arrives fails on the deadline.
func (e *chatEnv) openTurn(ctx context.Context, srv *httptest.Server, chat, bearer string, payload any) *http.Response {
	e.t.Helper()
	data, err := json.Marshal(payload)
	require.NoError(e.t, err)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, srv.URL+"/v1/chats/"+chat+"/turns", bytes.NewReader(data))
	require.NoError(e.t, err)
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	res, err := srv.Client().Do(req)
	require.NoError(e.t, err)
	e.t.Cleanup(func() { _ = res.Body.Close() })
	return res
}

func chatDeadline(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)
	return ctx
}

type sseFrame struct {
	event string
	data  string
}

func sseOf(body io.Reader) *sseReader { return &sseReader{lines: bufio.NewScanner(body)} }

type sseReader struct{ lines *bufio.Scanner }

// next is the next frame, skipping heartbeats; false when the stream ends.
func (r *sseReader) next() (sseFrame, bool) {
	var f sseFrame
	for r.lines.Scan() {
		line := r.lines.Text()
		switch {
		case line == "":
			if f.event != "" {
				return f, true
			}
		case strings.HasPrefix(line, ":"):
		case strings.HasPrefix(line, "event: "):
			f.event = strings.TrimPrefix(line, "event: ")
		case strings.HasPrefix(line, "data: "):
			f.data = strings.TrimPrefix(line, "data: ")
		}
	}
	return sseFrame{}, false
}

func (r *sseReader) rest() []sseFrame {
	var out []sseFrame
	for {
		f, ok := r.next()
		if !ok {
			return out
		}
		out = append(out, f)
	}
}

func frameData[T any](t *testing.T, f sseFrame) T {
	t.Helper()
	var v T
	require.NoError(t, json.Unmarshal([]byte(f.data), &v), f.data)
	return v
}

func frameEvents(frames []sseFrame) []string {
	out := make([]string, 0, len(frames))
	for _, f := range frames {
		out = append(out, f.event)
	}
	return out
}

func (e *chatEnv) agentTurn(chat string) (state, body string) {
	e.t.Helper()
	err := e.pool.QueryRow(context.Background(), `SELECT state, body FROM chat_turns
WHERE chat_id = $1 AND role = 'agent' ORDER BY created_at DESC LIMIT 1`, chat).Scan(&state, &body)
	require.NoError(e.t, err)
	return state, body
}

func (e *chatEnv) count(sql string, args ...any) int {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(), sql, args...).Scan(&n))
	return n
}

type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func TestTurnSSE(t *testing.T) {
	release := make(chan struct{})
	m := &chatModel{script: []chatMainCall{waits("Hel", release, "lo")}}
	e := newChatEnv(t, m)
	// The heartbeat flushes too: this far off, only a flush per frame can deliver the first one.
	e.server.chatHeartbeat = time.Hour
	chat, srv := e.newChat(e.bearer), e.listen()
	ctx, hangUp := context.WithCancel(chatDeadline(t))
	defer hangUp()
	firstFrame := time.AfterFunc(5*time.Second, hangUp)
	res := e.openTurn(ctx, srv, chat, e.bearer, map[string]any{
		"body": "  what is on tonight?  ", "hint": map[string]any{"screen": "lists"},
	})
	require.Equal(t, http.StatusOK, res.StatusCode)
	assert.Equal(t, "text/event-stream", res.Header.Get("Content-Type"))
	assert.Equal(t, "no-store", res.Header.Get("Cache-Control"))
	assert.Equal(t, "no", res.Header.Get("X-Accel-Buffering"))

	// The model is still holding its next piece: this frame can only be here if it was flushed.
	frames := sseOf(res.Body)
	first, ok := frames.next()
	require.True(t, ok, "the first frame arrives while the model waits")
	require.True(t, firstFrame.Stop(), "the first frame arrives within 5 s")
	assert.Equal(t, "delta", first.event)
	assert.Equal(t, "Hel", frameData[api.ChatTextFrame](t, first).Text)
	close(release)

	rest := frames.rest()
	require.Equal(t, []string{"delta", "done"}, frameEvents(rest))
	assert.Equal(t, "lo", frameData[api.ChatTextFrame](t, rest[0]).Text)
	done := frameData[api.ChatDoneFrame](t, rest[1])
	assert.Equal(t, 1, e.count(`SELECT count(*)::int FROM chat_turns WHERE id = $1 AND role = 'agent' AND state = 'done' AND body = 'Hello'`,
		done.TurnId.ID()))
	assert.Equal(t, 1, e.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1 AND role = 'user' AND body = 'what is on tonight?'`, chat),
		"the body is stored trimmed")
	assert.Contains(t, m.requests[0].System, "on the lists screen", "the hint reaches the prompt")
}

func TestTurnComponentsFrame(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	e.captureFilm("Arrival")
	m.script = []chatMainCall{
		callsTools(
			toolResponse("search_titles", map[string]any{"query": "Arrival", "kind": "movie"}, "a"),
			toolResponse("show_titles", map[string]any{"refs": []string{"r1"}}, "b"),
			toolResponse("apply_library_patch", map[string]any{"changes": []any{map[string]any{"op": "add", "ref": "r1", "status": "wishlist"}}}, "c"),
		),
		says("Added Arrival."),
	}
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer, map[string]any{"body": "add arrival"})
	frames := sseOf(res.Body).rest()
	require.Equal(t, []string{"status", "status", "delta", "components", "done"}, frameEvents(frames))
	assert.Equal(t, "Searching the catalog", frameData[api.ChatTextFrame](t, frames[0]).Text)
	assert.Equal(t, "Added Arrival.", frameData[api.ChatTextFrame](t, frames[2]).Text)

	parts := frameData[api.ChatComponentsFrame](t, frames[3])
	require.NotNil(t, parts.Titles)
	require.Len(t, *parts.Titles, 1)
	assert.Equal(t, "Arrival", (*parts.Titles)[0].Title)
	require.NotNil(t, parts.ActionId)
	require.NotNil(t, parts.ActionSummary)
	assert.Contains(t, *parts.ActionSummary, "Arrival")
	assert.Nil(t, parts.Plan)
	undo := e.send(http.MethodPost, "/v1/actions/"+parts.ActionId.String()+"/undo", nil)
	assert.Equal(t, http.StatusOK, undo.Code, undo.Body.String())
}

func TestTurnPlanFrame(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	e.captureFilm("Arrival")
	e.captureFilm("Heat")
	e.search.searchMu.Lock()
	e.search.hits["both"] = append(append([]catalog.Hit{}, e.search.hits["Arrival"]...), e.search.hits["Heat"]...)
	e.search.searchMu.Unlock()
	m.script = []chatMainCall{
		callsTools(
			toolResponse("search_titles", map[string]any{"query": "both", "kind": "movie"}, "a"),
			toolResponse("apply_library_patch", map[string]any{"changes": []any{
				map[string]any{"op": "add", "ref": "r1"},
				map[string]any{"op": "add", "ref": "r2"},
			}}, "b"),
		),
		says("It needs your yes."),
	}
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer, map[string]any{"body": "add both"})
	frames := sseOf(res.Body).rest()
	require.Equal(t, []string{"status", "status", "delta", "components", "done"}, frameEvents(frames))
	parts := frameData[api.ChatComponentsFrame](t, frames[3])
	require.NotNil(t, parts.Plan, frames[3].data)
	assert.Nil(t, parts.ActionId)
	assert.Len(t, parts.Plan.Changes, 2)
	got := e.send(http.MethodGet, "/v1/plans/"+parts.Plan.Id.String(), nil)
	assert.Equal(t, http.StatusOK, got.Code, "the plan the card shows is the user's to approve")
}

func TestTurnUnauthenticated(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	chat := e.newChat(e.bearer)
	res := e.openTurn(chatDeadline(t), e.listen(), chat, "", map[string]any{"body": "hi"})
	assert.Equal(t, http.StatusUnauthorized, res.StatusCode)
	assert.Equal(t, http.StatusUnauthorized, e.do(http.MethodPost, "/v1/chats", "", nil).Code)
}

func TestTurnOtherUsersChat(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("never")}}
	e := newChatEnv(t, m)
	_, other := e.signIn()
	chat := e.newChat(other)
	srv := e.listen()
	for _, id := range []string{chat, uuid.NewString(), "not-a-uuid"} {
		res := e.openTurn(chatDeadline(t), srv, id, e.bearer, map[string]any{"body": "hi"})
		assert.Equal(t, http.StatusNotFound, res.StatusCode, id)
		assert.Contains(t, res.Header.Get("Content-Type"), "application/json", "JSON, not a stream")
	}
	gates, mains := m.counts()
	assert.Zero(t, gates+mains, "no model call")
}

func TestTurnBusy(t *testing.T) {
	release := make(chan struct{})
	m := &chatModel{script: []chatMainCall{waits("Working", release, ".")}}
	e := newChatEnv(t, m)
	chat, srv := e.newChat(e.bearer), e.listen()
	first := e.openTurn(chatDeadline(t), srv, chat, e.bearer, map[string]any{"body": "first"})
	frames := sseOf(first.Body)
	_, ok := frames.next()
	require.True(t, ok)

	second := e.openTurn(chatDeadline(t), srv, chat, e.bearer, map[string]any{"body": "second"})
	assert.Equal(t, http.StatusConflict, second.StatusCode)
	assert.Contains(t, second.Header.Get("Content-Type"), "application/json")
	var body api.ErrorResponse
	require.NoError(t, json.NewDecoder(second.Body).Decode(&body))
	assert.Equal(t, "chat_busy", body.Code)

	close(release)
	assert.Equal(t, []string{"delta", "done"}, frameEvents(frames.rest()))
	gates, mains := m.counts()
	assert.Equal(t, 1, gates, "the second send reached no model")
	assert.Equal(t, 1, mains)
}

func TestTurnHangup(t *testing.T) {
	never := make(chan struct{})
	m := &chatModel{script: []chatMainCall{waits("Half an", never, " answer")}}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)
	ctx, hangUp := context.WithCancel(chatDeadline(t))
	defer hangUp()
	res := e.openTurn(ctx, e.listen(), chat, e.bearer, map[string]any{"body": "tell me"})
	_, ok := sseOf(res.Body).next()
	require.True(t, ok)
	hangUp()

	require.Eventually(t, func() bool {
		state, _ := e.agentTurn(chat)
		return state == agent.TurnStopped
	}, 10*time.Second, 20*time.Millisecond, "the turn stops when the client leaves")
	_, body := e.agentTurn(chat)
	assert.Equal(t, "Half an", body, "what was written stays")
}

// Shutdown cancels no request's context, and the server wires StopChats the same way (app.serve).
func TestShutdownStopsATurn(t *testing.T) {
	never := make(chan struct{})
	m := &chatModel{script: []chatMainCall{waits("Half an", never, " answer"), says("Back.")}}
	e := newChatEnv(t, m)
	chat, srv := e.newChat(e.bearer), e.listen()
	srv.Config.RegisterOnShutdown(e.server.StopChats)
	res := e.openTurn(chatDeadline(t), srv, chat, e.bearer, map[string]any{"body": "tell me"})
	frames := sseOf(res.Body)
	for {
		f, ok := frames.next()
		require.True(t, ok, "a delta arrives while the model waits")
		if f.event == "delta" {
			break
		}
	}

	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	require.NoError(t, srv.Config.Shutdown(shutdown), "the turn does not hold the grace period")

	rest := frames.rest()
	require.Equal(t, []string{"error"}, frameEvents(rest))
	assert.Equal(t, api.ChatErrorFrameCodeTryAgain, frameData[api.ChatErrorFrame](t, rest[0]).Code)
	state, body := e.agentTurn(chat)
	assert.Equal(t, agent.TurnStopped, state)
	assert.Equal(t, "Half an", body)
}

func TestTurnNoDeadline(t *testing.T) {
	slow := func(_ context.Context, onText func(string)) (model.Response, error) {
		time.Sleep(2 * time.Second)
		onText("Worth the wait.")
		return textResponse("Worth the wait."), nil
	}
	m := &chatModel{script: []chatMainCall{slow}}
	e := newChatEnv(t, m, func(d *Deps) { d.Config.HTTP.RequestTimeoutSeconds = 1 })
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer, map[string]any{"body": "take your time"})
	assert.Equal(t, []string{"delta", "done"}, frameEvents(sseOf(res.Body).rest()))
}

func TestTurnHeartbeat(t *testing.T) {
	release := make(chan struct{})
	defer close(release)
	m := &chatModel{script: []chatMainCall{waits("Thinking", release, ".")}}
	e := newChatEnv(t, m)
	e.server.chatHeartbeat = 20 * time.Millisecond
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer, map[string]any{"body": "hi"})
	lines := bufio.NewScanner(res.Body)
	comments := 0
	for comments < 2 && lines.Scan() {
		if strings.HasPrefix(lines.Text(), ":") {
			comments++
		}
	}
	assert.Equal(t, 2, comments, "comment lines arrive while the model is quiet")
}

func TestTurnBodyIsChecked(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)
	path := "/v1/chats/" + chat + "/turns"
	for name, body := range map[string]string{
		"missing":    ``,
		"empty":      "",
		"whitespace": "  \n\t ",
		"too long":   strings.Repeat("é", 4001),
		"NUL":        "a\x00b",
	} {
		payload := map[string]any{"body": body}
		if name == "missing" {
			payload = map[string]any{"hint": map[string]any{"screen": "home"}}
		}
		rec := e.send(http.MethodPost, path, payload)
		assert.Contains(t, []int{http.StatusBadRequest, http.StatusUnprocessableEntity}, rec.Code, name)
	}
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, path, map[string]any{"body": "   "}).Code)
	assert.Equal(t, http.StatusUnsupportedMediaType, e.sendBytes(http.MethodPost, path, e.bearer, "text/plain", []byte(`{"body":"hi"}`), false).Code)
	gates, mains := m.counts()
	assert.Zero(t, gates+mains, "no model call")
	assert.Zero(t, e.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1`, chat), "nothing stored")

	// 4000 characters is allowed, counted as characters and after trimming.
	m.script = []chatMainCall{says("OK.")}
	res := e.openTurn(chatDeadline(t), e.listen(), chat, e.bearer, map[string]any{"body": " " + strings.Repeat("é", 4000) + " "})
	assert.Equal(t, http.StatusOK, res.StatusCode)
}

func TestTurnAgentUnavailable(t *testing.T) {
	e := newChatEnv(t, nil)
	chat := e.newChat(e.bearer)
	rec := e.send(http.MethodPost, "/v1/chats/"+chat+"/turns", map[string]any{"body": "hi"})
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "agent_unavailable", decode[api.ErrorResponse](t, rec).Code)
}

func TestTurnPastTheCapIsOneRestingFrame(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("never")}}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)
	for range 30 {
		_, err := e.pool.Exec(context.Background(), `INSERT INTO chat_turns (id, chat_id, user_id, role, body, state)
VALUES ($1, $2, $3, 'user', 'earlier', 'done')`, uuid.New(), chat, e.user)
		require.NoError(t, err)
	}
	res := e.openTurn(chatDeadline(t), e.listen(), chat, e.bearer, map[string]any{"body": "one more"})
	require.Equal(t, http.StatusOK, res.StatusCode)
	frames := sseOf(res.Body).rest()
	require.Equal(t, []string{"error"}, frameEvents(frames))
	failure := frameData[api.ChatErrorFrame](t, frames[0])
	assert.Equal(t, api.ChatErrorFrameCodeResting, failure.Code)
	assert.Equal(t, "Aaru is resting. Try again later.", failure.Message)
	gates, mains := m.counts()
	assert.Zero(t, gates+mains)
}

func TestTurnFailureIsAnErrorFrameAndKeepsTheWordsOutOfTheLog(t *testing.T) {
	logged := &lockedBuffer{}
	const secret = "my-very-private-question"
	m := &chatModel{} // an empty script fails the main call
	e := newChatEnv(t, m, func(d *Deps) { d.Log = slog.New(slog.NewTextHandler(logged, nil)) })
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer, map[string]any{"body": secret})
	frames := sseOf(res.Body).rest()
	require.Equal(t, []string{"error"}, frameEvents(frames))
	assert.Equal(t, api.ChatErrorFrameCodeTryAgain, frameData[api.ChatErrorFrame](t, frames[0]).Code)
	assert.Contains(t, logged.String(), "chat turn failed", "the log was captured")
	assert.NotContains(t, logged.String(), secret)
}

func TestTurnCountsOneEventWithNoText(t *testing.T) {
	sink := &recordingSinkG6{captured: map[uuid.UUID][]capturedG6{}}
	telemetry.Install(sink)
	defer telemetry.Install(nil)
	m := &chatModel{script: []chatMainCall{says("Hi.")}}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)
	missing := e.openTurn(chatDeadline(t), e.listen(), uuid.NewString(), e.bearer, map[string]any{"body": "nobody home"})
	require.Equal(t, http.StatusNotFound, missing.StatusCode)
	res := e.openTurn(chatDeadline(t), e.listen(), chat, e.bearer, map[string]any{"body": "hello"})
	sseOf(res.Body).rest()

	count := 0
	for _, event := range sink.events(e.user) {
		if event.event == telemetry.AssistantTurn {
			count++
			assert.Empty(t, event.properties, "a count only")
		}
	}
	assert.Equal(t, 1, count)
}

// MARK: Transcription

type whisperCall struct {
	prompt   string
	filename string
	audio    []byte
}

type whisperStub struct {
	mu     sync.Mutex
	calls  []whisperCall
	status int
	text   string
	srv    *httptest.Server
}

func newWhisperStub(t *testing.T, text string) *whisperStub {
	t.Helper()
	w := &whisperStub{status: http.StatusOK, text: text}
	w.srv = httptest.NewServer(http.HandlerFunc(func(res http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/v1/audio/transcriptions", r.URL.Path)
		assert.Empty(t, r.Header.Get("Authorization"))
		call := whisperCall{}
		if assert.NoError(t, r.ParseMultipartForm(16<<20)) {
			call.prompt = r.FormValue("prompt")
			file, header, err := r.FormFile("file")
			if assert.NoError(t, err) {
				call.filename = header.Filename
				call.audio, _ = io.ReadAll(file)
				_ = file.Close()
			}
		}
		w.mu.Lock()
		defer w.mu.Unlock()
		w.calls = append(w.calls, call)
		res.WriteHeader(w.status)
		_ = json.NewEncoder(res).Encode(map[string]string{"text": w.text, "language": "pt"})
	}))
	t.Cleanup(w.srv.Close)
	return w
}

func (w *whisperStub) seen() []whisperCall {
	w.mu.Lock()
	defer w.mu.Unlock()
	return append([]whisperCall(nil), w.calls...)
}

func (w *whisperStub) on(t *testing.T) func(*Deps) {
	t.Helper()
	base, err := url.Parse(w.srv.URL + "/v1")
	require.NoError(t, err)
	return func(d *Deps) {
		d.Config.Transcription = &config.Transcription{BaseURL: base, Model: "Systran/faster-whisper-small"}
	}
}

// transcribe posts audio with the given headers.
func (e *chatEnv) transcribe(bearer, contentType string, audio []byte, seconds string) *httptest.ResponseRecorder {
	e.t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/chats/transcribe", bytes.NewReader(audio))
	req.Header.Set("Content-Type", contentType)
	if seconds != "" {
		req.Header.Set("X-Audio-Seconds", seconds)
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

func errorCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	return decode[api.ErrorResponse](t, rec).Code
}

func TestTranscribeOK(t *testing.T) {
	stub := newWhisperStub(t, " Olá Aaru ")
	e := newChatEnv(t, nil, stub.on(t))
	audio := []byte("fake-audio-bytes")
	for _, contentType := range []string{"audio/mp4", "audio/webm; codecs=opus", "application/octet-stream"} {
		rec := e.transcribe(e.bearer, contentType, audio, "12.5")
		require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
		got := decode[api.ChatTranscript](t, rec)
		assert.Equal(t, "Olá Aaru", got.Text)
		assert.Equal(t, "pt", got.Language)
	}
	seen := stub.seen()
	require.Len(t, seen, 3)
	assert.Equal(t, audio, seen[0].audio)
	assert.Equal(t, "audio.m4a", seen[0].filename)
	assert.Equal(t, "audio.webm", seen[1].filename)
}

func TestTranscribeTooLarge(t *testing.T) {
	stub := newWhisperStub(t, "never")
	e := newChatEnv(t, nil, stub.on(t))
	big := make([]byte, 8<<20+1)
	for _, chunked := range []bool{false, true} {
		rec := e.sendBytes(http.MethodPost, "/v1/chats/transcribe", e.bearer, "audio/mp4", big, chunked)
		assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code, "chunked=%v", chunked)
		assert.Equal(t, "file_too_large", errorCode(t, rec), "chunked=%v", chunked)
	}
	assert.Empty(t, stub.seen())
	assert.Equal(t, http.StatusOK, e.transcribe(e.bearer, "audio/mp4", big[:8<<20], "").Code, "8 MB is allowed")
}

func TestTranscribeTooLong(t *testing.T) {
	stub := newWhisperStub(t, "fine")
	e := newChatEnv(t, nil, stub.on(t))
	rec := e.transcribe(e.bearer, "audio/mp4", []byte("a"), "60.5")
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "audio_too_long", errorCode(t, rec))
	assert.Empty(t, stub.seen())
	assert.Equal(t, http.StatusOK, e.transcribe(e.bearer, "audio/mp4", []byte("a"), "60").Code)
	assert.Equal(t, http.StatusOK, e.transcribe(e.bearer, "audio/mp4", []byte("a"), "soon").Code, "not a length: the size still bounds it")
}

func TestTranscribeEmpty(t *testing.T) {
	stub := newWhisperStub(t, "  \n")
	e := newChatEnv(t, nil, stub.on(t))
	rec := e.transcribe(e.bearer, "audio/mp4", []byte("silence"), "")
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Equal(t, "transcription_empty", errorCode(t, rec))

	calls := len(stub.seen())
	none := e.transcribe(e.bearer, "audio/mp4", nil, "")
	assert.Equal(t, "transcription_empty", errorCode(t, none), "no audio has no words")
	assert.Len(t, stub.seen(), calls, "and is not sent")
}

func TestTranscribeOff(t *testing.T) {
	e := newChatEnv(t, nil)
	rec := e.transcribe(e.bearer, "audio/mp4", []byte("a"), "")
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "transcription_unavailable", errorCode(t, rec))
}

func TestTranscribeRefusesOtherTypes(t *testing.T) {
	stub := newWhisperStub(t, "never")
	e := newChatEnv(t, nil, stub.on(t))
	assert.Equal(t, http.StatusUnsupportedMediaType, e.transcribe(e.bearer, "text/plain", []byte("a"), "").Code)
	assert.Empty(t, stub.seen())
}

func TestTranscribeRateLimited(t *testing.T) {
	stub := newWhisperStub(t, "fine")
	e := newChatEnv(t, nil, stub.on(t))
	for i := range 40 {
		require.Equal(t, http.StatusOK, e.transcribe(e.bearer, "audio/mp4", []byte("a"), "").Code, "call %d", i)
	}
	rec := e.transcribe(e.bearer, "audio/mp4", []byte("a"), "")
	assert.Equal(t, http.StatusTooManyRequests, rec.Code)
	assert.Equal(t, "rate_limited", errorCode(t, rec))
	assert.Len(t, stub.seen(), 40, "the refused one reached no service")

	_, other := e.signIn()
	assert.Equal(t, http.StatusOK, e.transcribe(other, "audio/mp4", []byte("a"), "").Code, "per user")
}

func TestTranscribeVocabulary(t *testing.T) {
	stub := newWhisperStub(t, "fine")
	e := newChatEnv(t, nil, stub.on(t))
	ctx := context.Background()
	other, _ := e.signIn()
	item := func(user uuid.UUID, name, status string, updated time.Time) {
		title := uuid.New()
		_, err := e.pool.Exec(ctx, `INSERT INTO titles (id, type, title, year, tmdb) VALUES ($1, 'movie', $2, 2016, $3)`, title, name, uuid.NewString())
		require.NoError(t, err)
		_, err = e.pool.Exec(ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5)`,
			uuid.New(), user, title, status, updated)
		require.NoError(t, err)
	}
	now := time.Now()
	for i := range 31 {
		item(e.user, fmt.Sprintf("Watching %02d", i), "in_progress", now.Add(time.Duration(i)*time.Minute))
	}
	item(e.user, "Finished one", "finished", now)
	item(other, "Someone else's", "in_progress", now)

	require.Equal(t, http.StatusOK, e.transcribe(e.bearer, "audio/mp4", []byte("a"), "").Code)
	seen := stub.seen()
	require.Len(t, seen, 1)
	names := strings.Split(seen[0].prompt, ", ")
	assert.Len(t, names, 30)
	assert.Equal(t, "Watching 30", names[0], "latest first")
	assert.NotContains(t, seen[0].prompt, "Watching 00", "the oldest is the one left out")
	assert.NotContains(t, seen[0].prompt, "Finished one")
	assert.NotContains(t, seen[0].prompt, "Someone else")
}

func TestTranscribeFailureIsAnUpstreamErrorAndKeepsAudioOutOfTheLog(t *testing.T) {
	logged := &lockedBuffer{}
	stub := newWhisperStub(t, "never read")
	stub.status = http.StatusInternalServerError
	e := newChatEnv(t, nil, stub.on(t), func(d *Deps) { d.Log = slog.New(slog.NewTextHandler(logged, nil)) })
	const secret = "SECRET-AUDIO-BYTES"
	rec := e.transcribe(e.bearer, "audio/mp4", []byte(secret), "")
	assert.Equal(t, http.StatusBadGateway, rec.Code)
	assert.Equal(t, "provider_unavailable", errorCode(t, rec))
	assert.Contains(t, logged.String(), "transcription failed", "the log was captured")
	assert.NotContains(t, logged.String(), secret)
}

// MARK: The rest

func TestDeleteChats(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("Hi.")}}
	e := newChatEnv(t, m)
	other, otherBearer := e.signIn()
	mine, theirs := e.newChat(e.bearer), e.newChat(otherBearer)
	res := e.openTurn(chatDeadline(t), e.listen(), mine, e.bearer, map[string]any{"body": "hello"})
	sseOf(res.Body).rest()

	rec := e.send(http.MethodDelete, "/v1/chats", nil)
	assert.Equal(t, http.StatusNoContent, rec.Code)
	assert.Zero(t, e.count(`SELECT count(*)::int FROM chats WHERE user_id = $1`, e.user))
	assert.Zero(t, e.count(`SELECT count(*)::int FROM chat_turns WHERE user_id = $1`, e.user))
	assert.Equal(t, 1, e.count(`SELECT count(*)::int FROM chats WHERE id = $1 AND user_id = $2`, theirs, other), "only the caller's")
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/chats/"+mine+"/turns", map[string]any{"body": "hi"}).Code)
}

func TestChatStatus(t *testing.T) {
	status := func(e *chatEnv) api.ChatStatus {
		rec := e.send(http.MethodGet, "/v1/chats/status", nil)
		require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
		return decode[api.ChatStatus](t, rec)
	}
	assert.Equal(t, api.ChatStatus{Assistant: false, Voice: false}, status(newChatEnv(t, nil)))
	assert.Equal(t, api.ChatStatus{Assistant: true, Voice: false}, status(newChatEnv(t, &chatModel{})))
	stub := newWhisperStub(t, "x")
	assert.Equal(t, api.ChatStatus{Assistant: false, Voice: true}, status(newChatEnv(t, nil, stub.on(t))))
}

func TestAgentTokenRefused(t *testing.T) {
	stub := newWhisperStub(t, "never")
	e := newChatEnv(t, &chatModel{}, stub.on(t))
	chat := e.newChat(e.bearer)
	for _, kind := range []string{"browser", "music", "stremio", "codex"} {
		created := decode[api.AgentTokenCreated](t, e.send(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": kind}))
		for _, route := range [][2]string{
			{http.MethodPost, "/v1/chats"},
			{http.MethodDelete, "/v1/chats"},
			{http.MethodGet, "/v1/chats/status"},
			{http.MethodPost, "/v1/chats/transcribe"},
			{http.MethodPost, "/v1/chats/" + chat + "/turns"},
		} {
			rec := e.do(route[0], route[1], created.Secret, map[string]any{"body": "hi"})
			assert.Equal(t, http.StatusUnauthorized, rec.Code, "%s %s %s", kind, route[0], route[1])
		}
	}
	assert.Empty(t, stub.seen())
}

// The stream and the upload are served raw, so the embedded spec leaves them out (oapi-codegen.yaml);
// the file the clients generate from must still document them.
func TestChatRoutesInSpec(t *testing.T) {
	document, err := os.ReadFile("../../../aaru-server/Sources/AppAPI/openapi.yaml")
	require.NoError(t, err)
	e := newChatEnv(t, nil)
	routes := map[string]bool{}
	for _, r := range e.echo.Routes() {
		routes[r.Method+" "+r.Path] = true
	}
	for _, route := range []struct{ method, path, echo, operation string }{
		{http.MethodPost, "/v1/chats", "/v1/chats", "createChat"},
		{http.MethodDelete, "/v1/chats", "/v1/chats", "deleteChats"},
		{http.MethodGet, "/v1/chats/status", "/v1/chats/status", "getChatStatus"},
		{http.MethodPost, "/v1/chats/transcribe", "/v1/chats/transcribe", "transcribeChatAudio"},
		{http.MethodPost, "/v1/chats/{id}/turns", "/v1/chats/:id/turns", "createChatTurn"},
	} {
		assert.Contains(t, string(document), "\n  "+route.path+":\n", route.path)
		assert.Contains(t, string(document), "operationId: "+route.operation+"\n", route.operation)
		assert.True(t, routes[route.method+" "+route.echo], "%s %s served", route.method, route.echo)
	}
	assert.True(t, noDeadline["POST /v1/chats/:id/turns"])
	assert.True(t, noDeadline["POST /v1/chats/transcribe"])
	assert.Equal(t, int64(8<<20), ownBodyLimits["POST /v1/chats/transcribe"])
}

// A nil Quota means no limit at all on a many-title plan: the real server must wire the real one.
func TestChatToolsHaveTheCaptureQuota(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	quota := e.server.chatService().Deps.Tools.Quota
	require.NotNil(t, quota)
	assert.NotNil(t, e.server.chatService().Deps.Q, "title_details reads the caller's progress through it")
	ctx := context.Background()
	require.NoError(t, quota(ctx, e.server.q, e.user))

	tmdb := e.captureFilm("Quota " + uuid.NewString())
	for range 3 {
		link := map[string]any{"url": "https://www.themoviedb.org/movie/" + tmdb}
		require.Equal(t, http.StatusAccepted, e.send(http.MethodPost, "/v1/imports/capture", link).Code)
	}
	err := quota(ctx, e.server.q, e.user)
	var refused *apperr.Error
	require.True(t, errors.As(err, &refused), "%v", err)
	assert.Equal(t, "capture_quota", refused.Code)
}
