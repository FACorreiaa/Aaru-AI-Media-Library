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

func TestBodyHasNoSamplingFieldsOrPrefill(t *testing.T) {
	body := AnthropicBody(Request{
		System: "s", Turns: []Turn{UserText("hi")}, MaxTokens: 512, ToolChoice: "pick",
		Tools: []Tool{{Name: "pick", Description: "d", InputSchema: json.RawMessage(`{"type":"object"}`)}},
	}, "claude-haiku-5-5", "low")
	data, err := json.Marshal(body)
	require.NoError(t, err)
	assert.JSONEq(t, `{
		"model":"claude-haiku-5-5","max_tokens":512,"system":"s",
		"messages":[{"role":"user","content":[{"type":"text","text":"hi"}]}],
		"tools":[{"name":"pick","description":"d","input_schema":{"type":"object"}}],
		"tool_choice":{"type":"tool","name":"pick"},
		"output_config":{"effort":"low"}}`, string(data))
	for _, banned := range []string{"temperature", "top_p", "top_k"} {
		assert.NotContains(t, body, banned)
	}
}

func TestCompleteSendsHeadersAndParses(t *testing.T) {
	var got provider.Request
	base, _ := url.Parse("https://stub.test")
	a := &AnthropicMessages{
		APIKey: "k", ModelName: "m", BaseURL: base, WorkspaceID: "ws",
		Transport: provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
			got = req
			return &provider.Response{Status: 200, Body: []byte(`{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"a"},{"type":"tool_use","id":"t1","name":"look","input":{"q":1}}],"stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":4}}`)}, nil
		}),
	}
	resp, err := a.Complete(context.Background(), Request{Turns: []Turn{UserText("hi")}, MaxTokens: 10})
	require.NoError(t, err)
	assert.Equal(t, "https://stub.test/v1/messages", got.URL)
	assert.Contains(t, got.Headers, [2]string{"anthropic-workspace-id", "ws"})
	assert.Contains(t, got.Headers, [2]string{"anthropic-version", AnthropicVersion})
	assert.Equal(t, StopToolUse, resp.Stop)
	assert.Equal(t, "a", resp.Text())
	require.Len(t, resp.ToolCalls(), 1)
	assert.JSONEq(t, `{"q":1}`, string(resp.ToolCalls()[0].Input))
	assert.Len(t, resp.Content, 3, "unknown blocks are kept for replay")
	assert.Equal(t, 3, Pricing{InputPerMTok: 0.10, OutputPerMTok: 0.50}.Micros(resp))
}

func TestOutOfCredit(t *testing.T) {
	base, _ := url.Parse("https://stub.test")
	a := &AnthropicMessages{BaseURL: base, Transport: provider.TransportFunc(func(context.Context, provider.Request) (*provider.Response, error) {
		return &provider.Response{Status: 400, Body: []byte(`{"error":{"message":"Your credit balance is too low"}}`)}, nil
	})}
	_, err := a.Complete(context.Background(), Request{})
	var pe *ProviderError
	require.ErrorAs(t, err, &pe)
	assert.True(t, pe.OutOfCredit)
	assert.Equal(t, 400, pe.Status)
}
