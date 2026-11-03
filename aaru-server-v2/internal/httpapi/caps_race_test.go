package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/plans"
	"context"
	"fmt"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// DB-008: the owned-groups and pending-plans caps are counted under a lock, with the insert.

// parallel runs n calls of f at once and waits for them.
func parallel(n int, f func(i int)) {
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			f(i)
		}()
	}
	close(start)
	wg.Wait()
}

func TestGroupCreateParallelKeepsTheOwnedCap(t *testing.T) {
	env := newGroupEnv(t)
	env.claimHandle()
	for i := range groups.MaxOwnedGroups - 2 {
		env.createGroup(fmt.Sprint("Group ", i))
	}
	codes := make([]int, 5)
	parallel(len(codes), func(i int) {
		codes[i] = env.send(http.MethodPost, "/v1/groups", map[string]any{"name": fmt.Sprint("Race ", i)}).Code
	})
	created := 0
	for _, c := range codes {
		if c == http.StatusOK {
			created++
		}
	}
	assert.Equal(t, 2, created, codes)
	var owned int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM group_members WHERE user_id = $1 AND role = 'owner'`, env.user).Scan(&owned))
	assert.Equal(t, groups.MaxOwnedGroups, owned)
}

func TestPlanProposeParallelKeepsThePendingCap(t *testing.T) {
	env, _ := newMCPEnv(t)
	itemID := env.add("show", env.stubShow("Andor", catalog.StatusEnded, 2, 3, false))
	agent := env.planAgent()
	for range plans.MaxPendingPerToken - 1 {
		_, err := env.pool.Exec(context.Background(), `INSERT INTO agent_plans (id, user_id, agent_token_id, agent_name, status,
			summary, changes, counts, op, basis, expires_at) VALUES ($1, $2, $3, 'Laptop', 'pending', 's', '{"items":[]}',
			'{"adds":0,"updates":0,"removes":0,"episodes":0}', '{"batch":{"_0":[]}}', '{"items":{},"absentTitles":[]}',
			now() + interval '1 hour')`, uuid.New(), env.user, uuid.MustParse(agent.id))
		require.NoError(t, err)
	}
	planned := make([]bool, 5)
	parallel(len(planned), func(i int) {
		result := env.callTool(agent.secret, "apply_library_patch", map[string]any{"changes": episodeChanges(itemID, [2]int{1, 1}, [2]int{1, 2})})
		s := structured(result)
		planned[i] = s != nil && s["planId"] != nil
	})
	n := 0
	for _, p := range planned {
		if p {
			n++
		}
	}
	assert.Equal(t, 1, n, "one proposal fits under the cap")
	var pending int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM agent_plans WHERE agent_token_id = $1 AND status = 'pending'`, uuid.MustParse(agent.id)).Scan(&pending))
	assert.Equal(t, plans.MaxPendingPerToken, pending)
}
