package httpapi

import (
	"aaru-go-api/internal/catalog"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// PlanTests.swift: remote approval (AG-003, OUT-004).

type planAgent struct {
	secret string
	id     string
}

func (e *libEnv) planAgent() planAgent {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "claude_code", "name": "Laptop", "allowLibraryWrites": true})
	require.Equal(e.t, http.StatusCreated, rec.Code, rec.Body.String())
	body := decode[map[string]any](e.t, rec)
	return planAgent{secret: body["secret"].(string), id: body["token"].(map[string]any)["id"].(string)}
}

// propose asks over MCP and returns the plan id the tool answered.
func (e *libEnv) propose(agent planAgent, changes []any) string {
	e.t.Helper()
	result := e.callTool(agent.secret, "apply_library_patch", map[string]any{"changes": changes})
	s := structured(result)
	require.NotNil(e.t, s, "%v", result)
	require.Equal(e.t, false, s["applied"])
	return s["planId"].(string)
}

func episodeChanges(itemID string, keys ...[2]int) []any {
	eps := make([]any, len(keys))
	for i, k := range keys {
		eps[i] = map[string]any{"season": k[0], "episode": k[1]}
	}
	return []any{map[string]any{"op": "episodes", "libraryItemId": itemID, "watched": true, "episodes": eps}}
}

func TestPlanWritesNothingUntilApprovedThenOneUndoableAction(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Andor", catalog.StatusEnded, 2, 3, false))
	agent := env.planAgent()
	before := env.actionCount()
	planID := env.propose(agent, episodeChanges(itemID, [2]int{1, 1}, [2]int{1, 2}, [2]int{1, 3}))
	assert.Equal(t, before, env.actionCount(), "nothing written yet")

	pending := env.json(http.MethodGet, "/v1/plans", nil)["items"].([]any)
	require.Len(t, pending, 1)
	plan := pending[0].(map[string]any)
	assert.Equal(t, planID, plan["id"])
	assert.Equal(t, "Laptop", plan["agentName"])
	assert.Equal(t, "pending", plan["status"])
	assert.Equal(t, "Marked 3 episodes of Andor watched", plan["summary"])
	assert.InDelta(t, 3, plan["counts"].(map[string]any)["episodes"], 0)
	line := plan["changes"].([]any)[0].(map[string]any)
	assert.Equal(t, strings.ToUpper(itemID), line["libraryItemId"])
	assert.Equal(t, "show", line["type"])

	approved := env.send(http.MethodPost, "/v1/plans/"+planID+"/approve", nil)
	require.Equal(t, http.StatusOK, approved.Code, approved.Body.String())
	body := decode[map[string]any](t, approved)
	action := body["action"].(map[string]any)
	assert.Equal(t, "external_agent", action["actor"])
	assert.Equal(t, "Laptop: marked 3 episodes of Andor watched", action["summary"])
	assert.Equal(t, "plan", action["kind"])
	decided := body["plan"].(map[string]any)
	assert.Equal(t, "applied", decided["status"])
	assert.Equal(t, strings.ToLower(action["id"].(string)), decided["actionId"])
	assert.NotNil(t, decided["decidedAt"])
	assert.Equal(t, 3, env.watchedCount(itemID))
	again := env.send(http.MethodPost, "/v1/plans/"+planID+"/approve", nil)
	assert.Equal(t, http.StatusConflict, again.Code, "decided once")
	assert.Equal(t, "plan_decided", decode[map[string]any](t, again)["code"])
	assert.Empty(t, env.json(http.MethodGet, "/v1/plans", nil)["items"])
	assert.Len(t, env.json(http.MethodGet, "/v1/plans?status=all", nil)["items"], 1)

	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+action["id"].(string)+"/undo", nil).Code)
	assert.Equal(t, 0, env.watchedCount(itemID))
}

func TestPlanWhoseLibraryMovedIsStale(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Severance", catalog.StatusEnded, 2, 3, false))
	agent := env.planAgent()
	planID := env.propose(agent, episodeChanges(itemID, [2]int{1, 1}, [2]int{1, 2}))
	require.Equal(t, http.StatusOK, env.send(http.MethodPut, "/v1/library/items/"+itemID+"/episodes/2/1", map[string]any{"watched": true}).Code)
	reply := env.send(http.MethodPost, "/v1/plans/"+planID+"/approve", nil)
	assert.Equal(t, http.StatusConflict, reply.Code)
	stale := decode[map[string]any](t, reply)
	assert.Equal(t, "plan_stale", stale["code"])
	assert.Equal(t, "Your library changed since Laptop asked, so nothing was applied. Ask it again.", stale["message"])
	assert.Equal(t, "stale", env.json(http.MethodGet, "/v1/plans/"+planID, nil)["status"])
	assert.Equal(t, 1, env.watchedCount(itemID))

	first, second := env.stubMovie("Arrival"), env.stubMovie("Dune")
	adds := env.propose(agent, []any{
		map[string]any{"op": "add", "mediaRef": map[string]any{"type": "movie", "ids": map[string]any{"tmdb": first}}},
		map[string]any{"op": "add", "mediaRef": map[string]any{"type": "movie", "ids": map[string]any{"tmdb": second}}},
	})
	plan := env.json(http.MethodGet, "/v1/plans/"+adds, nil)
	assert.Equal(t, "Add 2 titles", plan["summary"])
	_, hasItem := plan["changes"].([]any)[0].(map[string]any)["libraryItemId"]
	assert.False(t, hasItem, "an add has no item yet")
	env.add("movie", second)
	assert.Equal(t, "plan_stale", decode[map[string]any](t, env.send(http.MethodPost, "/v1/plans/"+adds+"/approve", nil))["code"])
}

func TestPlanDenyExpiryAndRevokedTokens(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Dark", catalog.StatusEnded, 2, 3, false))
	agent := env.planAgent()
	before := env.actionCount()

	denied := env.propose(agent, []any{map[string]any{"op": "remove", "libraryItemId": itemID}})
	assert.Equal(t, "denied", env.json(http.MethodPost, "/v1/plans/"+denied+"/deny", nil)["status"])
	assert.Equal(t, http.StatusConflict, env.send(http.MethodPost, "/v1/plans/"+denied+"/approve", nil).Code)
	assert.Equal(t, "plan_decided", decode[map[string]any](t, env.send(http.MethodPost, "/v1/plans/"+denied+"/deny", nil))["code"])
	assert.Equal(t, http.StatusOK, env.send(http.MethodGet, "/v1/library/items/"+itemID, nil).Code, "never removed")

	old := env.propose(agent, episodeChanges(itemID, [2]int{1, 1}, [2]int{1, 2}))
	_, err := env.pool.Exec(context.Background(), `UPDATE agent_plans SET expires_at = now() - interval '1 minute' WHERE id = $1`, uuid.MustParse(old))
	require.NoError(t, err)
	assert.Equal(t, "plan_expired", decode[map[string]any](t, env.send(http.MethodPost, "/v1/plans/"+old+"/approve", nil))["code"])

	orphan := env.propose(agent, episodeChanges(itemID, [2]int{2, 1}, [2]int{2, 2}))
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/agent/tokens/"+agent.id, nil).Code)
	assert.Equal(t, "expired", env.json(http.MethodGet, "/v1/plans/"+orphan, nil)["status"])
	assert.Equal(t, before, env.actionCount(), "nothing applied")
}

func TestPlanOnlyTheSignedInOwnerDecides(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Andor", catalog.StatusEnded, 2, 3, false))
	agent := env.planAgent()
	planID := env.propose(agent, episodeChanges(itemID, [2]int{1, 1}, [2]int{1, 2}))
	assert.Equal(t, http.StatusUnauthorized, env.send(http.MethodPost, "/v1/plans/"+planID+"/approve", nil, agent.secret).Code)
	_, other := env.signIn()
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, "/v1/plans/"+planID+"/approve", nil, other).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/plans/"+planID, nil, other).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/plans/not-a-plan", nil).Code)
}

func TestPlanNothingToChangeAndPendingCap(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Andor", catalog.StatusEnded, 2, 3, false))
	agent := env.planAgent()
	noop := env.callTool(agent.secret, "apply_library_patch", map[string]any{"changes": []any{
		map[string]any{"op": "episodes", "libraryItemId": itemID, "watched": false, "episodes": []any{
			map[string]any{"season": 1, "episode": 1}, map[string]any{"season": 1, "episode": 2},
		}},
	}})
	assert.Equal(t, "Nothing to change: the library already looks like that.", toolText(noop))

	for i := 0; i < 20; i++ {
		_, err := env.pool.Exec(context.Background(), `INSERT INTO agent_plans (id, user_id, agent_token_id, agent_name, status,
			summary, changes, counts, op, basis, expires_at) VALUES ($1, $2, $3, 'Laptop', 'pending', 's', '{"items":[]}',
			'{"adds":0,"updates":0,"removes":0,"episodes":0}', '{"batch":{"_0":[]}}', '{"items":{},"absentTitles":[]}',
			now() + interval '1 hour')`, uuid.New(), env.user, uuid.MustParse(agent.id))
		require.NoError(t, err)
	}
	capped := env.callTool(agent.secret, "apply_library_patch", map[string]any{"changes": episodeChanges(itemID, [2]int{1, 1}, [2]int{1, 2})})
	assert.Equal(t, "20 changes from this connection are already waiting for the user. Ask them to review those in Aaru first.", toolText(capped))
}
