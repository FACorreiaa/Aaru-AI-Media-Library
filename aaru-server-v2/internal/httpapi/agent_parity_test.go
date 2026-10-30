package httpapi

import (
	"aaru-go-api/internal/imports"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AgentTokenTests.mcpTokens: an MCP token is read-only unless imports are allowed, and its
// secret is not a Stremio link.
func TestMCPTokenIsReadOnlyByDefaultAndNoStremioLink(t *testing.T) {
	env := newLibEnv(t)
	created := env.json(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "codex"})
	assert.Equal(t, []any{"library:read"}, created["token"].(map[string]any)["scopes"], "never scrobble:write")
	assert.NotContains(t, created, "stremio")
	secret := created["secret"].(string)
	manifest := env.do(http.MethodGet, "/stremio/"+secret+"/manifest.json", "", nil)
	assert.Equal(t, http.StatusNotFound, manifest.Code, "an MCP secret is not a Stremio link")
}

// MCPTests.planImport over the real import service: the queued job is one the user sees in
// /v1/imports, and nothing lands before they approve it.
func TestMCPPlanImportQueuesAJobTheUserSees(t *testing.T) {
	env, _ := newMCPEnv(t)
	env.server.AgentImports = imports.AgentImporter{Service: env.server.Imports}
	env.echo = env.server.Router(nil) // the MCP tools are built with the router
	csv := "Title,Year\nArrival,2016\nDune,2021\n"
	plain := env.connect(map[string]any{"kind": "claude_code", "allowLibraryWrites": true})
	assert.Equal(t, true, env.callTool(plain, "plan_import", map[string]any{"text": csv, "source": "csv"})["isError"])

	importer := env.connect(map[string]any{"kind": "codex", "allowImports": true})
	before := env.actionCount()
	queued := structured(env.callTool(importer, "plan_import", map[string]any{"text": csv, "source": "csv"}))
	assert.Equal(t, false, queued["applied"])
	importID, _ := queued["importId"].(string)
	require.NotEmpty(t, importID)
	jobs := env.json(http.MethodGet, "/v1/imports", nil)["items"].([]any)
	assert.Contains(t, ids(jobs), importID)
	assert.Equal(t, before, env.actionCount(), "nothing lands before the user approves the import")
}

// AuthFlowTests.accountDeleteLeavesNothing with the rows Swift seeded: a library item, a list
// with a member, a shelf, an import job and a Stremio token.
func TestAccountDeleteLeavesNothingOfALibraryListsShelvesAndImports(t *testing.T) {
	env := newLibEnv(t)
	tmdb := env.stubMovie("Dune")
	env.add("movie", tmdb)
	list := env.json(http.MethodPost, "/v1/lists", map[string]any{"name": "L"})["id"].(string)
	env.json(http.MethodPost, "/v1/lists/"+list+"/items", movieRef(tmdb))
	env.json(http.MethodPost, "/v1/shelves", map[string]any{"name": "S", "filter": map[string]any{}})
	env.uploadJob("/v1/imports/csv?source=csv&filename=export.csv", "text/csv", []byte("Title,Year\nArrival,2016\n"))
	require.Equal(t, http.StatusCreated, env.send(http.MethodPost, "/v1/agent/tokens", map[string]string{"kind": "stremio"}).Code)
	require.NotEmpty(t, rowsReferencing(t, env.harness, env.user))

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/me", nil).Code)
	assert.Empty(t, rowsReferencing(t, env.harness, env.user))
	assert.Equal(t, http.StatusUnauthorized, env.send(http.MethodGet, "/v1/me", nil).Code)
}
