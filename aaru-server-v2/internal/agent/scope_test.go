package agent_test

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/model"
	"encoding/json"
	"errors"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestScopeVerdict(t *testing.T) {
	for _, inScope := range []bool{true, false} {
		m := &scriptedModel{script: []step{gate(inScope)}}
		got, err := agent.InScope(t.Context(), m, nil, "what's airing tonight?")
		require.NoError(t, err)
		assert.Equal(t, inScope, got)
	}
}

func TestScopeForcesItsToolAndSendsNoSampling(t *testing.T) {
	m := &scriptedModel{script: []step{gate(true)}}
	_, err := agent.InScope(t.Context(), m, nil, "hello")
	require.NoError(t, err)
	req := m.calls()[0]
	assert.Equal(t, "record_scope", req.ToolChoice)
	assert.Equal(t, 256, req.MaxTokens)
	require.Len(t, req.Tools, 1)
	assert.Equal(t, "record_scope", req.Tools[0].Name)

	body, err := json.Marshal(model.AnthropicBody(req, "claude-haiku-5-5", "low"))
	require.NoError(t, err)
	var sent map[string]any
	require.NoError(t, json.Unmarshal(body, &sent))
	for _, field := range []string{"temperature", "top_p", "top_k"} {
		assert.NotContains(t, sent, field)
	}
	last := sent["messages"].([]any)[len(sent["messages"].([]any))-1].(map[string]any)
	assert.Equal(t, "user", last["role"], "an assistant turn last would be a prefill")
}

func TestScopeFailsClosed(t *testing.T) {
	noCall := textResponse("It is about films.")
	malformed := toolCalls(call{"record_scope", map[string]any{"verdict": "yes"}, "g"})
	otherTool := toolCalls(call{"read_my_library", map[string]any{"in_scope": true}, "g"})
	cases := map[string]step{
		"provider error": {err: errors.New("boom")},
		"no call":        {response: noCall},
		"malformed":      {response: malformed},
		"other tool":     {response: otherTool},
	}
	for name, s := range cases {
		t.Run(name, func(t *testing.T) {
			got, err := agent.InScope(t.Context(), &scriptedModel{script: []step{s}}, nil, "hello")
			require.Error(t, err)
			assert.False(t, got)
		})
	}
}

func TestScopeReadsOnlyTheLastTurns(t *testing.T) {
	recent := make([]agent.ChatTurn, 0, 12)
	for i := range 12 {
		recent = append(recent, agent.ChatTurn{Role: "user", Body: "turn" + strconv.Itoa(i) + "."})
	}
	m := &scriptedModel{script: []step{gate(true)}}
	_, err := agent.InScope(t.Context(), m, recent, "e a segunda temporada?")
	require.NoError(t, err)
	seen := m.everythingSeen()
	assert.Contains(t, seen, "turn11.")
	assert.Contains(t, seen, "e a segunda temporada?")
	assert.NotContains(t, seen, "turn0.")
}
