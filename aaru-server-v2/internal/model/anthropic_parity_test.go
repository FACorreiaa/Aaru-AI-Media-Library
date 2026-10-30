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

// AgentTests.wireBody (GRP-010): the Messages API body has no sampling fields or prefill,
// the headers name the key and version (no workspace unless configured), and replies parse.
func TestMessagesWireBodyAndReplyParse(t *testing.T) {
	var sent []provider.Request
	status, reply := 200, `{"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"Hi"}],
		"stop_reason":"end_turn","usage":{"input_tokens":12,"output_tokens":3}}`
	base, _ := url.Parse("http://stub.test")
	a := &AnthropicMessages{
		APIKey: "test-key", ModelName: "claude-haiku-5-5", BaseURL: base, Effort: "low",
		Transport: provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
			sent = append(sent, req)
			return &provider.Response{Status: status, Body: []byte(reply)}, nil
		}),
	}
	tools := []Tool{{Name: "search_titles", Description: "d", InputSchema: json.RawMessage(`{"type":"object"}`)}}
	resp, err := a.Complete(context.Background(), Request{System: "sys", Turns: []Turn{UserText("hello")}, Tools: tools, MaxTokens: 2048})
	require.NoError(t, err)
	assert.Equal(t, "Hi", resp.Text())
	assert.Equal(t, StopDone, resp.Stop)
	assert.Equal(t, 12, resp.InputTokens)
	require.NotEmpty(t, resp.Content)
	var first struct{ Type string }
	require.NoError(t, json.Unmarshal(resp.Content[0], &first))
	assert.Equal(t, "thinking", first.Type, "thinking blocks are kept to replay unchanged")

	require.Len(t, sent, 1)
	req := sent[0]
	assert.Equal(t, "http://stub.test/v1/messages", req.URL)
	assert.Contains(t, req.Headers, [2]string{"x-api-key", "test-key"})
	assert.Contains(t, req.Headers, [2]string{"anthropic-version", "2023-06-01"})
	for _, h := range req.Headers {
		assert.NotEqual(t, "anthropic-workspace-id", h[0])
	}
	var body map[string]any
	require.NoError(t, json.Unmarshal(req.Body, &body))
	for _, banned := range []string{"temperature", "top_p", "top_k"} {
		assert.NotContains(t, body, banned)
	}
	assert.InDelta(t, 2048, body["max_tokens"], 0)
	assert.Equal(t, "low", body["output_config"].(map[string]any)["effort"])
	messages := body["messages"].([]any)
	assert.Equal(t, "user", messages[len(messages)-1].(map[string]any)["role"], "no assistant prefill")

	status, reply = 400, `{"error":{"message":"You have reached your usage limit"}}`
	_, err = a.Complete(context.Background(), Request{System: "s", Turns: []Turn{UserText("x")}, MaxTokens: 10})
	var pe *ProviderError
	require.ErrorAs(t, err, &pe)
	assert.Equal(t, ProviderError{Status: 400, OutOfCredit: true}, *pe)
}

// AgentTests.workspaceHeader (GRP-010): a key not scoped to a workspace sends the workspace id.
func TestMessagesSendsTheWorkspaceID(t *testing.T) {
	var sent provider.Request
	base, _ := url.Parse("http://stub.test")
	a := &AnthropicMessages{
		APIKey: "test-key", ModelName: "claude-haiku-5-5", BaseURL: base, WorkspaceID: "wrkspc_test",
		Transport: provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
			sent = req
			return &provider.Response{Status: 200, Body: []byte(`{"content":[],"stop_reason":"end_turn"}`)}, nil
		}),
	}
	_, err := a.Complete(context.Background(), Request{System: "s", Turns: []Turn{UserText("x")}, MaxTokens: 10})
	require.NoError(t, err)
	assert.Contains(t, sent.Headers, [2]string{"anthropic-workspace-id", "wrkspc_test"})
}
