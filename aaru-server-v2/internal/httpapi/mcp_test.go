package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/mcp"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MCPTests.swift: the MCP endpoint (OUT-004).

// mcpSearchFake is the library fake with search results stubbed by query.
type mcpSearchFake struct {
	*libraryFake
	hits map[string][]catalog.Hit
}

func (f *mcpSearchFake) Search(_ context.Context, query string, mediaType core.MediaType) ([]catalog.Hit, error) {
	var out []catalog.Hit
	for _, h := range f.hits[query] {
		if h.Type == mediaType {
			out = append(out, h)
		}
	}
	return out, nil
}

func (f *mcpSearchFake) SearchMulti(_ context.Context, query string) ([]catalog.Hit, error) {
	return f.hits[query], nil
}

// newMCPEnv is a library env whose catalog search answers stubbed hits.
func newMCPEnv(t *testing.T, tweak ...func(*Deps)) (*libEnv, *mcpSearchFake) {
	t.Helper()
	fake := &mcpSearchFake{libraryFake: &libraryFake{episodes: map[string]catalog.Episodes{}}, hits: map[string][]catalog.Hit{}}
	providers := catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}
	h := newHarness(t, append([]func(*Deps){func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) }}, tweak...)...)
	user, bearer := h.signIn()
	return &libEnv{harness: h, fake: fake.libraryFake, user: user, bearer: bearer}, fake
}

// connect mints an MCP token through the route, as Settings does, and returns its secret.
func (e *libEnv) connect(body map[string]any) string {
	e.t.Helper()
	if body == nil {
		body = map[string]any{"kind": "claude_code"}
	}
	rec := e.send(http.MethodPost, "/v1/agent/tokens", body)
	require.Equal(e.t, http.StatusCreated, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)["secret"].(string)
}

func (e *libEnv) rpc(token, method string, params map[string]any) map[string]any {
	e.t.Helper()
	body := map[string]any{"jsonrpc": "2.0", "id": 1, "method": method}
	if params != nil {
		body["params"] = params
	}
	rec := e.send(http.MethodPost, mcp.Path, body, token)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

func (e *libEnv) callTool(token, tool string, args map[string]any) map[string]any {
	e.t.Helper()
	reply := e.rpc(token, "tools/call", map[string]any{"name": tool, "arguments": args})
	result, ok := reply["result"].(map[string]any)
	require.True(e.t, ok, "%v", reply)
	return result
}

func structured(result map[string]any) map[string]any {
	m, _ := result["structuredContent"].(map[string]any)
	return m
}

func toolText(result map[string]any) string {
	content, _ := result["content"].([]any)
	if len(content) == 0 {
		return ""
	}
	first, _ := content[0].(map[string]any)
	text, _ := first["text"].(string)
	return text
}

func (e *libEnv) raw(method, bearer string, headers map[string]string, body string) *httptest.ResponseRecorder {
	e.t.Helper()
	var reader *strings.Reader
	if body != "" {
		reader = strings.NewReader(body)
	} else {
		reader = strings.NewReader("")
	}
	req := httptest.NewRequest(method, mcp.Path, reader)
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

func TestMCPHandshake(t *testing.T) {
	env, _ := newMCPEnv(t)
	token := env.connect(nil)
	reply := env.rpc(token, "initialize", map[string]any{
		"protocolVersion": "2025-06-18", "capabilities": map[string]any{}, "clientInfo": map[string]any{"name": "test", "version": "0"},
	})
	result := reply["result"].(map[string]any)
	assert.Equal(t, "2025-06-18", result["protocolVersion"])
	assert.Equal(t, "aaru", result["serverInfo"].(map[string]any)["name"])
	assert.Equal(t, mcp.Instructions, result["instructions"])
	newer := env.rpc(token, "initialize", map[string]any{"protocolVersion": "1999-01-01"})
	assert.Equal(t, mcp.Versions[0], newer["result"].(map[string]any)["protocolVersion"])

	listed := env.rpc(token, "tools/list", nil)
	var names []string
	for _, tool := range listed["result"].(map[string]any)["tools"].([]any) {
		names = append(names, tool.(map[string]any)["name"].(string))
	}
	assert.Equal(t, []string{"search_titles", "read_library", "list_airs", "apply_library_patch", "plan_import"}, names)
	unknown := env.rpc(token, "resources/list", nil)
	assert.InDelta(t, -32601, unknown["error"].(map[string]any)["code"], 0)
	assert.Equal(t, "Aaru does not support resources/list.", unknown["error"].(map[string]any)["message"])

	pong := env.send(http.MethodPost, mcp.Path, []byte(`{"jsonrpc":"2.0","id":"a/b","method":"ping"}`), token)
	assert.Equal(t, `{"jsonrpc":"2.0","id":"a/b","result":{}}`, pong.Body.String())
	assert.Equal(t, "no-store", pong.Header().Get("Cache-Control"))
	batch := env.send(http.MethodPost, mcp.Path, []byte(`[{"jsonrpc":"2.0","id":1,"method":"ping"}]`), token)
	assert.Equal(t, `{"jsonrpc":"2.0","error":{"code":-32700,"message":"The body is not one JSON-RPC request."}}`, batch.Body.String())
	noName := env.rpc(token, "tools/call", map[string]any{"arguments": map[string]any{}})
	assert.Equal(t, "tools/call needs a name.", noName["error"].(map[string]any)["message"])
	noTool := env.rpc(token, "tools/call", map[string]any{"name": "drop_tables"})
	assert.Equal(t, "Aaru has no tool named drop_tables.", noTool["error"].(map[string]any)["message"])
}

func TestMCPOnlyALiveMCPTokenGetsIn(t *testing.T) {
	env, _ := newMCPEnv(t)
	ping := `{"jsonrpc":"2.0","id":1,"method":"ping"}`
	anonymous := env.raw(http.MethodPost, "", nil, ping)
	assert.Equal(t, http.StatusUnauthorized, anonymous.Code)
	assert.Equal(t, `Bearer realm="aaru", resource_metadata="https://api.aaruapp.com/.well-known/oauth-protected-resource/v1/mcp"`,
		anonymous.Header().Get("WWW-Authenticate"))
	assert.Equal(t, "Connect this client in Aaru → Settings → Connections.", anonymous.Body.String())

	assert.Equal(t, http.StatusUnauthorized, env.raw(http.MethodPost, env.bearer, nil, ping).Code, "a session")
	stremio := env.connect(map[string]any{"kind": "stremio"})
	assert.Equal(t, http.StatusUnauthorized, env.raw(http.MethodPost, stremio, nil, ping).Code, "a Stremio link")

	token := env.connect(nil)
	assert.Equal(t, http.StatusOK, env.raw(http.MethodPost, token, nil, ping).Code)
	get := env.raw(http.MethodGet, token, nil, "")
	assert.Equal(t, http.StatusMethodNotAllowed, get.Code)
	assert.Equal(t, "POST", get.Header().Get("Allow"))
	notification := env.raw(http.MethodPost, token, nil, `{"jsonrpc":"2.0","method":"notifications/initialized"}`)
	assert.Equal(t, http.StatusAccepted, notification.Code)
	assert.Empty(t, notification.Body.String())

	browser := env.raw(http.MethodPost, token, map[string]string{"Origin": "https://evil.example"}, ping)
	assert.Equal(t, http.StatusForbidden, browser.Code)
	version := env.raw(http.MethodPost, token, map[string]string{"MCP-Protocol-Version": "1999-01-01"}, ping)
	assert.Equal(t, http.StatusBadRequest, version.Code)
	assert.Equal(t, "Unsupported MCP-Protocol-Version 1999-01-01.", version.Body.String())
	big := env.raw(http.MethodPost, token, nil, `{"jsonrpc":"2.0","id":1,"method":"ping","x":"`+strings.Repeat("a", mcp.MaxBody)+`"}`)
	assert.Equal(t, http.StatusRequestEntityTooLarge, big.Code)

	items := env.json(http.MethodGet, "/v1/agent/tokens?for=mcp", nil)["items"].([]any)
	require.Len(t, items, 1)
	id := items[0].(map[string]any)["id"].(string)
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/agent/tokens/"+id, nil).Code)
	assert.Equal(t, http.StatusUnauthorized, env.raw(http.MethodPost, token, nil, ping).Code, "revoked")
}

func TestMCPReadsComeBackAsV1DTOs(t *testing.T) {
	env, fake := newMCPEnv(t)
	tmdb := env.stubShow("Andor", catalog.StatusEnded, 2, 3, false)
	year := 2022
	fake.hits["Andor"] = []catalog.Hit{{Type: core.MediaShow, Title: "Andor", Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}}}
	itemID := env.add("show", tmdb)
	token := env.connect(nil)

	search := env.callTool(token, "search_titles", map[string]any{"query": "Andor", "type": "show"})
	assert.Equal(t, false, search["isError"])
	hits := structured(search)["items"].([]any)
	require.NotEmpty(t, hits)
	assert.Equal(t, "Andor", hits[0].(map[string]any)["title"])
	assert.True(t, strings.HasPrefix(toolText(search), `{"incomplete":false,"items":[`), "text is sorted-key JSON: %s", toolText(search))

	badType := env.callTool(token, "search_titles", map[string]any{"query": "Andor", "type": "comic"})
	assert.Equal(t, "type must be one of all, movie, show, anime, book.", toolText(badType))
	both := env.callTool(token, "search_titles", map[string]any{"query": "Andor", "titleId": uuid.NewString()})
	assert.Equal(t, "Pass either query or titleId, not both.", toolText(both))

	library := env.callTool(token, "read_library", map[string]any{"status": "wishlist"})
	assert.Equal(t, []string{itemID}, ids(structured(library)["items"]))
	one := env.callTool(token, "read_library", map[string]any{"libraryItemId": itemID})
	_, isList := structured(one)["watchedEpisodes"].([]any)
	assert.True(t, isList)
	badStatus := env.callTool(token, "read_library", map[string]any{"status": "watching"})
	assert.Equal(t, "The arguments for read_library do not match its input schema.", toolText(badStatus))
	badLimit := env.callTool(token, "read_library", map[string]any{"limit": 51})
	assert.Equal(t, "limit must be between 1 and 50.", toolText(badLimit))
	whole := env.callTool(token, "read_library", map[string]any{"limit": 2.0})
	assert.Equal(t, false, whole["isError"])

	airs := env.callTool(token, "list_airs", map[string]any{"view": "up_next"})
	assert.NotNil(t, structured(airs)["counts"])
	calendar := env.callTool(token, "list_airs", map[string]any{"from": "2026-01-01", "to": "2026-03-01"})
	assert.Equal(t, true, calendar["isError"], "more than 42 days")
	assert.Equal(t, "to must be after from, and at most 42 days later.", toolText(calendar))
	week := env.callTool(token, "list_airs", map[string]any{"from": "2026-01-01T00:00:00Z"})
	assert.Equal(t, false, week["isError"])
	_, isItems := structured(week)["items"].([]any)
	assert.True(t, isItems)

	typo := env.callTool(token, "read_library", map[string]any{"stauts": "wishlist"})
	assert.Equal(t, true, typo["isError"])
	assert.Equal(t, "read_library has no argument stauts.", toolText(typo))
	missing := env.callTool(token, "read_library", map[string]any{"libraryItemId": uuid.NewString()})
	assert.Equal(t, true, missing["isError"], "a 404 is the agent's message, not a protocol error")
}

func TestMCPTapSizedWritesApplyBiggerOnesWaitReadOnlyNeverWrites(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Severance", catalog.StatusEnded, 2, 3, false))
	readOnly := env.connect(nil)
	tick := map[string]any{"changes": []any{map[string]any{
		"op": "episodes", "libraryItemId": itemID, "watched": true,
		"episodes": []any{map[string]any{"season": 1, "episode": 1}},
	}}}
	before := env.actionCount()
	refused := env.callTool(readOnly, "apply_library_patch", tick)
	assert.Equal(t, true, refused["isError"])
	assert.Equal(t, "This connection is read-only. The user can allow changes for it in Aaru → Settings → Connections.", toolText(refused))
	assert.Equal(t, before, env.actionCount())

	writer := env.connect(map[string]any{"kind": "claude_code", "allowLibraryWrites": true})
	applied := env.callTool(writer, "apply_library_patch", tick)
	assert.Equal(t, false, applied["isError"])
	assert.Equal(t, true, structured(applied)["applied"])
	assert.NotNil(t, structured(applied)["item"])
	assert.Equal(t, before+1, env.actionCount())

	actions := env.json(http.MethodGet, "/v1/actions?limit=1", nil)["items"].([]any)
	first := actions[0].(map[string]any)
	assert.Equal(t, "external_agent", first["actor"])
	assert.Equal(t, "Claude Code: marked S01E01 of Severance watched", first["summary"])
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+first["id"].(string)+"/undo", nil).Code)

	many := map[string]any{"changes": []any{map[string]any{
		"op": "episodes", "libraryItemId": itemID, "watched": true,
		"episodes": []any{map[string]any{"season": 1, "episode": 1}, map[string]any{"season": 1, "episode": 2}},
	}}}
	big := env.callTool(writer, "apply_library_patch", many)
	proposed := structured(big)
	assert.Equal(t, false, proposed["applied"])
	assert.Equal(t, "pending_approval", proposed["status"])
	planID, _ := proposed["planId"].(string)
	assert.Equal(t, strings.ToLower(planID), planID, "planId is lowercase")
	assert.NotEmpty(t, planID, "bigger than a tap: a plan, not a write")
	assert.Equal(t, before+2, env.actionCount(), "the tick and its undo only")

	for _, c := range []struct {
		changes []any
		message string
	}{
		{[]any{}, "changes must hold 1 to 100 entries."},
		{[]any{map[string]any{"op": "drop"}}, "changes[0]: op must be add, update, episodes or remove."},
		{[]any{map[string]any{"op": "update", "libraryItemId": itemID}}, "changes[0]: update needs a patch."},
		{[]any{map[string]any{"op": "remove", "libraryItemId": "nope"}}, "changes[0]: needs a valid libraryItemId."},
		{[]any{map[string]any{"op": "episodes", "libraryItemId": itemID}}, "changes[0]: episodes needs watched: true or false."},
		{
			[]any{map[string]any{"op": "episodes", "libraryItemId": itemID, "watched": true, "season": 1, "episodes": []any{}}},
			"changes[0]: season marks a whole season watched; pass either season or episodes.",
		},
		{
			[]any{map[string]any{"op": "episodes", "libraryItemId": itemID, "watched": true, "episodes": []any{map[string]any{"season": 1, "episode": 0}}}},
			"changes[0]: S1E0 is not a valid episode.",
		},
		{
			[]any{map[string]any{"op": "remove", "libraryItemId": itemID}, map[string]any{"op": "remove", "libraryItemId": itemID}},
			"Each libraryItemId may appear once; combine its changes.",
		},
	} {
		result := env.callTool(writer, "apply_library_patch", map[string]any{"changes": c.changes})
		assert.Equal(t, c.message, toolText(result))
	}
	noOp := env.callTool(writer, "apply_library_patch", map[string]any{"changes": []any{map[string]any{"op": "update"}}})
	assert.Equal(t, "changes[0]: update needs a patch.", toolText(noOp))
	missingOp := env.callTool(writer, "apply_library_patch", map[string]any{"changes": []any{map[string]any{"libraryItemId": itemID}}})
	assert.Equal(t, "The arguments for apply_library_patch do not match its input schema.", toolText(missingOp))
}

// fakeImporter is the imports area's side of plan_import, until imports is ported.
type fakeImporter struct {
	created []core.ImportSource
}

func (f *fakeImporter) DetectSource(text string) (core.ImportSource, error) {
	if strings.HasPrefix(text, "Title,Year") {
		return core.SourceGenericCSV, nil
	}
	return "", errors.New("Aaru could not tell which site this file is from.") //nolint:revive // the user-facing message
}

func (f *fakeImporter) IsCATCalendar(text string) bool {
	return strings.HasPrefix(text, "BEGIN:VCALENDAR")
}

func (f *fakeImporter) CreateFileImport(_ context.Context, _ uuid.UUID, source core.ImportSource, _ *string, _ string) (uuid.UUID, error) {
	f.created = append(f.created, source)
	return uuid.New(), nil
}

func TestMCPPlanImportQueuesForReviewAndNeedsTheImportsScope(t *testing.T) {
	importer := &fakeImporter{}
	env, _ := newMCPEnv(t, func(d *Deps) { d.AgentImports = importer })
	csv := "Title,Year\nArrival,2016\nDune,2021\n"
	plain := env.connect(map[string]any{"kind": "claude_code", "allowLibraryWrites": true})
	refused := env.callTool(plain, "plan_import", map[string]any{"text": csv, "source": "csv"})
	assert.Equal(t, true, refused["isError"])
	assert.Empty(t, importer.created)

	rec := env.send(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "codex", "allowImports": true})
	body := decode[map[string]any](t, rec)
	assert.Equal(t, []any{"imports:write", "library:read"}, body["token"].(map[string]any)["scopes"])
	importer2 := body["secret"].(string)
	before := env.actionCount()
	queued := structured(env.callTool(importer2, "plan_import", map[string]any{"text": csv, "source": "csv"}))
	assert.Equal(t, false, queued["applied"])
	assert.Equal(t, "csv", queued["source"])
	importID, _ := queued["importId"].(string)
	assert.Equal(t, strings.ToUpper(importID), importID)
	assert.Equal(t, before, env.actionCount(), "nothing lands before the user approves the import")

	auto := structured(env.callTool(importer2, "plan_import", map[string]any{"text": csv}))
	assert.Equal(t, "csv", auto["source"])
	cat := structured(env.callTool(importer2, "plan_import", map[string]any{"text": "Andor\nSeverance", "source": "cat"}))
	assert.Equal(t, "cat_list", cat["source"])
	unknown := env.callTool(importer2, "plan_import", map[string]any{"text": "???"})
	assert.Equal(t, "Aaru could not tell which site this file is from.", toolText(unknown))
	badSource := env.callTool(importer2, "plan_import", map[string]any{"text": csv, "source": "excel"})
	assert.Equal(t, "source must be auto, imdb, letterboxd, netflix, tvtime, goodreads, mal, csv or cat.", toolText(badSource))
	noText := env.callTool(importer2, "plan_import", map[string]any{"source": "csv"})
	assert.Equal(t, "The arguments for plan_import do not match its input schema.", toolText(noText))
	assert.Equal(t, []core.ImportSource{core.SourceGenericCSV, core.SourceGenericCSV, core.SourceCATList}, importer.created)
}

func TestMCPPlanImportWithoutImporterFailsQuietly(t *testing.T) {
	env, _ := newMCPEnv(t)
	token := env.connect(map[string]any{"kind": "codex", "allowImports": true})
	result := env.callTool(token, "plan_import", map[string]any{"text": "Title\nArrival\n"})
	assert.Equal(t, "Aaru could not finish plan_import. Try again later.", toolText(result))
}

var _ = json.Marshal
