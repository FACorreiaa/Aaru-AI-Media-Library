package agent_test

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/model"
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// searchingModel is a scriptedModel whose provider may search the web (ASK-004).
type searchingModel struct{ *scriptedModel }

func (searchingModel) SearchesWeb() bool { return true }

func (f *turnFixture) searching() { f.svc.Model = searchingModel{f.model} }

func rawBlock(t *testing.T, v any) model.Block {
	t.Helper()
	data, err := json.Marshal(v)
	require.NoError(t, err)
	return data
}

// pausedSearch is an answer the provider paused after one search.
func pausedSearch(t *testing.T) step {
	t.Helper()
	return step{response: model.Response{
		Content: []model.Block{
			rawBlock(t, map[string]any{"type": "server_tool_use", "id": "srvtoolu_1", "name": "web_search", "input": map[string]any{"query": "dune part three"}}),
			rawBlock(t, map[string]any{"type": "web_search_tool_result", "tool_use_id": "srvtoolu_1", "content": []any{
				map[string]any{"type": "web_search_result", "url": "https://a.test/dune", "title": "Dune news", "encrypted_content": "E"},
			}}),
		},
		Stop: model.StopPaused, InputTokens: 500, OutputTokens: 20, WebSearches: 1,
	}}
}

// citedAnswer is text citing two pages, one of them twice.
func citedAnswer(t *testing.T) step {
	t.Helper()
	cite := func(url, title string) map[string]any {
		return map[string]any{"type": "web_search_result_location", "url": url, "title": title, "encrypted_index": "I", "cited_text": "x"}
	}
	return step{response: model.Response{
		Content: []model.Block{
			rawBlock(t, map[string]any{"type": "text", "text": "It opens in December", "citations": []any{cite("https://a.test/dune", "Dune news")}}),
			rawBlock(t, map[string]any{"type": "text", "text": " 2026.", "citations": []any{
				cite("https://b.test/dates", "Release dates"), cite("https://a.test/dune", "Dune news"),
			}}),
		},
		Stop: model.StopDone, InputTokens: 900, OutputTokens: 30, WebSearches: 1,
	}}
}

func TestNoWebSearchWhenTheModelCannotSearch(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("Not that I know."))
	f.ask("when does dune 3 come out?")
	calls := f.model.calls()
	require.Len(t, calls, 2)
	assert.Nil(t, calls[1].WebSearch)
	assert.NotContains(t, calls[1].System, "web_search")
}

func TestWebSearchPausedTurnCarriesOnAndCitesSources(t *testing.T) {
	f := newTurnFixture(t, gate(true), pausedSearch(t), citedAnswer(t))
	f.searching()
	f.ask("when does dune 3 come out?")

	calls := f.model.calls()
	require.Len(t, calls, 3)
	assert.Nil(t, calls[0].WebSearch, "the gate never searches")
	require.NotNil(t, calls[1].WebSearch)
	assert.Equal(t, agent.WebSearchesPerTurn, calls[1].WebSearch.MaxUses)
	assert.Contains(t, calls[1].System, "web_search")
	require.NotNil(t, calls[2].WebSearch, "a transcript with searches keeps the tool")
	assert.Equal(t, agent.WebSearchesPerTurn-1, calls[2].WebSearch.MaxUses, "the turn's searches are counted")

	// The paused blocks go back as the assistant's, with no user turn after them.
	last := calls[2].Turns[len(calls[2].Turns)-1]
	assert.Equal(t, model.RoleAssistant, last.Role)
	assert.Contains(t, string(last.Content[1]), `"encrypted_content":"E"`)

	assert.Equal(t, "It opens in December 2026.", f.deltas())
	sources := []model.Source{{URL: "https://a.test/dune", Title: "Dune news"}, {URL: "https://b.test/dates", Title: "Release dates"}}
	assert.Equal(t, sources, f.event(agent.ChatEventComponents).Sources)

	stored := f.lastTurn()
	assert.Equal(t, agent.TurnDone, stored.state)
	assert.Equal(t, "It opens in December 2026.", stored.body, "sources are never read aloud with the body")
	var components agent.StoredComponents
	require.NoError(t, json.Unmarshal(stored.components, &components))
	assert.Equal(t, sources, components.Sources)

	usage, err := agent.UsageOn(f.ctx, f.store.Q, f.user, f.now)
	require.NoError(t, err)
	assert.Equal(t, 2, usage.WebSearches)
	// Each search is a cent at the provider's price (the scripted model prices none), so only tokens here.
	assert.Positive(t, usage.CostMicros)
}

func TestWebSearchStopsAtTheDailyCap(t *testing.T) {
	f := newTurnFixture(t, gate(true), says("I can't see that yet."))
	f.searching()
	require.NoError(t, agent.RecordResponse(f.ctx, f.store.Q, f.user, f.now, f.model,
		model.Response{WebSearches: agent.WebSearchesPerDay - 1}))
	f.ask("when does dune 3 come out?")
	require.Len(t, f.model.calls(), 2)
	require.NotNil(t, f.model.calls()[1].WebSearch)
	assert.Equal(t, 1, f.model.calls()[1].WebSearch.MaxUses, "what is left of the day")

	f.model.script = []step{gate(true), says("Still nothing.")}
	require.NoError(t, agent.RecordResponse(f.ctx, f.store.Q, f.user, f.now, f.model, model.Response{WebSearches: 1}))
	f.ask("and dune 4?")
	calls := f.model.calls()
	require.Len(t, calls, 4)
	assert.Nil(t, calls[3].WebSearch, "a spent day offers no search")
	assert.False(t, strings.Contains(calls[3].System, "web_search"))
}
