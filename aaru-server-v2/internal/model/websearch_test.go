package model

import (
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"net/url"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBodyAddsWebSearchAfterTheTools(t *testing.T) {
	body := AnthropicBody(Request{
		Turns: []Turn{UserText("hi")}, MaxTokens: 512, WebSearch: &WebSearch{MaxUses: 0},
		Tools: []Tool{{Name: "look", Description: "d", InputSchema: json.RawMessage(`{"type":"object"}`)}},
	}, "claude-haiku-5-5", "")
	data, err := json.Marshal(body["tools"])
	require.NoError(t, err)
	assert.JSONEq(t, `[
		{"name":"look","description":"d","input_schema":{"type":"object"}},
		{"type":"web_search_20250305","name":"web_search","max_uses":1}]`, string(data), "never fewer than one use")
}

func TestBodyWithOnlyWebSearch(t *testing.T) {
	body := AnthropicBody(Request{Turns: []Turn{UserText("hi")}, WebSearch: &WebSearch{MaxUses: 3}}, "m", "")
	data, err := json.Marshal(body["tools"])
	require.NoError(t, err)
	assert.JSONEq(t, `[{"type":"web_search_20250305","name":"web_search","max_uses":3}]`, string(data))
}

func TestProviderNotSetToSearchSendsNoSearch(t *testing.T) {
	var got map[string]any
	base, _ := url.Parse("https://stub.test")
	a := &AnthropicMessages{BaseURL: base, Transport: provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
		require.NoError(t, json.Unmarshal(req.Body, &got))
		return &provider.Response{Status: 200, Body: []byte(`{"content":[],"stop_reason":"end_turn"}`)}, nil
	})}
	assert.False(t, SearchesWeb(a))
	_, err := a.Complete(context.Background(), Request{Turns: []Turn{UserText("hi")}, WebSearch: &WebSearch{MaxUses: 3}})
	require.NoError(t, err)
	assert.NotContains(t, got, "tools")
	a.WebSearch = true
	assert.True(t, SearchesWeb(a))
}

// searchAnswer is a whole answer that searched once and cites two pages, one twice.
const searchAnswer = `{"content":[
	{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"severance season 3"}},
	{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[
		{"type":"web_search_result","url":"https://a.test/s3","title":"A","encrypted_content":"E1"}]},
	{"type":"text","text":"Season 3 starts in March","citations":[
		{"type":"web_search_result_location","url":"https://a.test/s3","title":"A","encrypted_index":"I1","cited_text":"x"}]},
	{"type":"text","text":" and runs ten episodes.","citations":[
		{"type":"web_search_result_location","url":"https://b.test/ep","title":"B","encrypted_index":"I2","cited_text":"y"},
		{"type":"web_search_result_location","url":"https://a.test/s3","title":"A","encrypted_index":"I3","cited_text":"z"}]}],
	"stop_reason":"end_turn",
	"usage":{"input_tokens":1000,"output_tokens":100,"server_tool_use":{"web_search_requests":1}}}`

func TestCompleteCountsSearchesAndSources(t *testing.T) {
	base, _ := url.Parse("https://stub.test")
	a := &AnthropicMessages{BaseURL: base, Transport: provider.TransportFunc(func(context.Context, provider.Request) (*provider.Response, error) {
		return &provider.Response{Status: 200, Body: []byte(searchAnswer)}, nil
	})}
	resp, err := a.Complete(context.Background(), Request{})
	require.NoError(t, err)
	assert.Equal(t, 1, resp.WebSearches)
	assert.Equal(t, []Source{{URL: "https://a.test/s3", Title: "A"}, {URL: "https://b.test/ep", Title: "B"}}, resp.Sources())
	assert.Empty(t, resp.ToolCalls(), "a server tool call is not the caller's to run")
	assert.Len(t, resp.Content, 4, "search blocks are kept for replay")
	price := Pricing{InputPerMTok: 0.10, OutputPerMTok: 0.50, WebSearchMicros: AnthropicWebSearchMicros}
	assert.Equal(t, 100+50+10_000, price.Micros(resp))
}

func TestPauseTurnIsPaused(t *testing.T) {
	reason := "pause_turn"
	assert.Equal(t, StopPaused, mapStop(&reason))
}

func TestStreamRebuildsSearchBlocks(t *testing.T) {
	body := sse(
		[2]string{"message_start", `{"type":"message_start","message":{"usage":{"input_tokens":30}}}`},
		[2]string{"content_block_start", `{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":"}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"dune 3\"}"}}`},
		[2]string{"content_block_stop", `{"type":"content_block_stop","index":0}`},
		[2]string{"content_block_start", `{"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","url":"https://c.test","title":"C","encrypted_content":"E"}]}}`},
		[2]string{"content_block_stop", `{"type":"content_block_stop","index":1}`},
		[2]string{"content_block_start", `{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://c.test","title":"C","encrypted_index":"I","cited_text":"q"}}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"December 2026."}}`},
		[2]string{"content_block_stop", `{"type":"content_block_stop","index":2}`},
		[2]string{"message_delta", `{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9,"server_tool_use":{"web_search_requests":1}}}`},
		[2]string{"message_stop", `{"type":"message_stop"}`},
	)
	var sent map[string]any
	a := streamServer(t, 200, body, &sent)
	a.WebSearch = true
	var text string
	resp, err := a.Stream(context.Background(), Request{Turns: []Turn{UserText("hi")}, WebSearch: &WebSearch{MaxUses: 2}}, func(s string) { text += s })
	require.NoError(t, err)
	assert.Equal(t, "December 2026.", text)
	assert.Contains(t, sent, "tools")
	assert.Equal(t, 1, resp.WebSearches)
	assert.Equal(t, []Source{{URL: "https://c.test", Title: "C"}}, resp.Sources())
	require.Len(t, resp.Content, 3)
	assert.JSONEq(t, `{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"dune 3"}}`, string(resp.Content[0]))
	assert.Contains(t, string(resp.Content[1]), `"encrypted_content":"E"`, "results replay unchanged")
	assert.JSONEq(t, `{"type":"text","text":"December 2026.","citations":[
		{"type":"web_search_result_location","url":"https://c.test","title":"C","encrypted_index":"I","cited_text":"q"}]}`, string(resp.Content[2]))
}

func TestTextJoinsCitedFragmentsAsOnePassage(t *testing.T) {
	resp := Response{Content: []Block{
		json.RawMessage(`{"type":"thinking","thinking":""}`),
		TextBlock("Let me look."),
		json.RawMessage(`{"type":"server_tool_use","id":"s","name":"web_search","input":{}}`),
		TextBlock("It opens in December"),
		TextBlock(" 2026."),
	}}
	assert.Equal(t, "Let me look.\nIt opens in December 2026.", resp.Text())
}
