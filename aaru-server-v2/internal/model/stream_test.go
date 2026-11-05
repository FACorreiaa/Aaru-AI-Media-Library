package model

import (
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	dto "github.com/prometheus/client_model/go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func sse(events ...[2]string) string {
	var s string
	for _, e := range events {
		s += fmt.Sprintf("event: %s\ndata: %s\n\n", e[0], e[1])
	}
	return s
}

func streamServer(t *testing.T, status int, body string, got *map[string]any) *AnthropicMessages {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got != nil {
			_ = json.NewDecoder(r.Body).Decode(got)
		}
		w.Header().Set("content-type", "text/event-stream")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(srv.Close)
	base, err := url.Parse(srv.URL)
	require.NoError(t, err)
	return &AnthropicMessages{Transport: provider.NewHTTPTransport(), APIKey: "k", ModelName: "m", BaseURL: base}
}

var textStream = sse(
	[2]string{"message_start", `{"type":"message_start","message":{"usage":{"input_tokens":25,"output_tokens":1}}}`},
	[2]string{"content_block_start", `{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}`},
	[2]string{"ping", `{"type":"ping"}`},
	[2]string{"content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Sev"}}`},
	[2]string{"content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"erance"}}`},
	[2]string{"content_block_stop", `{"type":"content_block_stop","index":0}`},
	[2]string{"message_delta", `{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}`},
	[2]string{"message_stop", `{"type":"message_stop"}`},
)

func TestStreamText(t *testing.T) {
	a := streamServer(t, 200, textStream, nil)
	var pieces []string
	resp, err := a.Stream(context.Background(), Request{Turns: []Turn{UserText("hi")}, MaxTokens: 10}, func(s string) { pieces = append(pieces, s) })
	require.NoError(t, err)
	assert.Equal(t, []string{"Sev", "erance"}, pieces)
	assert.Equal(t, "Severance", resp.Text())
	assert.Equal(t, StopDone, resp.Stop)
	assert.Equal(t, 25, resp.InputTokens)
	assert.Equal(t, 7, resp.OutputTokens)
}

func TestStreamToolUse(t *testing.T) {
	a := streamServer(t, 200, sse(
		[2]string{"message_start", `{"type":"message_start","message":{"usage":{"input_tokens":9}}}`},
		[2]string{"content_block_start", `{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hm"}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}`},
		[2]string{"content_block_stop", `{"type":"content_block_stop","index":0}`},
		[2]string{"content_block_start", `{"type":"content_block_start","index":1,"content_block":{"type":"server_widget","id":"w1","data":{"a":1}}}`},
		[2]string{"content_block_stop", `{"type":"content_block_stop","index":1}`},
		[2]string{"content_block_start", `{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"t1","name":"search","input":{}}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":""}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"query\":"}}`},
		[2]string{"content_block_delta", `{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"dune\"}"}}`},
		[2]string{"content_block_stop", `{"type":"content_block_stop","index":2}`},
		[2]string{"message_delta", `{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":30}}`},
		[2]string{"message_stop", `{"type":"message_stop"}`},
	), nil)
	resp, err := a.Stream(context.Background(), Request{MaxTokens: 10}, func(string) {})
	require.NoError(t, err)
	assert.Equal(t, StopToolUse, resp.Stop)
	calls := resp.ToolCalls()
	require.Len(t, calls, 1)
	assert.Equal(t, "t1", calls[0].ID)
	assert.JSONEq(t, `{"query":"dune"}`, string(calls[0].Input))
	require.Len(t, resp.Content, 3)
	assert.JSONEq(t, `{"type":"thinking","thinking":"hm","signature":"sig"}`, string(resp.Content[0]))
	assert.JSONEq(t, `{"type":"server_widget","id":"w1","data":{"a":1}}`, string(resp.Content[1]))
	// The content replays as a valid assistant turn.
	body := AnthropicBody(Request{Turns: []Turn{UserText("x"), {Role: RoleAssistant, Content: resp.Content}}}, "m", "")
	_, err = json.Marshal(body)
	require.NoError(t, err)
}

func TestStreamNoSampling(t *testing.T) {
	var got map[string]any
	a := streamServer(t, 200, textStream, &got)
	_, err := a.Stream(context.Background(), Request{Turns: []Turn{UserText("hi")}, MaxTokens: 10}, func(string) {})
	require.NoError(t, err)
	assert.Equal(t, true, got["stream"])
	for _, banned := range []string{"temperature", "top_p", "top_k"} {
		assert.NotContains(t, got, banned)
	}
}

func TestStreamOutOfCredit(t *testing.T) {
	a := streamServer(t, 400, `{"error":{"message":"You have reached your workspace usage limit"}}`, nil)
	before := callCount(t, "out_of_credit")
	_, err := a.Stream(context.Background(), Request{MaxTokens: 10}, func(string) {})
	var pe *ProviderError
	require.ErrorAs(t, err, &pe)
	assert.True(t, pe.OutOfCredit)
	assert.Equal(t, 400, pe.Status)
	assert.Equal(t, before+1, callCount(t, "out_of_credit"))
}

func TestStreamErrorEvent(t *testing.T) {
	a := streamServer(t, 200, sse(
		[2]string{"message_start", `{"type":"message_start","message":{"usage":{"input_tokens":1}}}`},
		[2]string{"error", `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`},
	), nil)
	_, err := a.Stream(context.Background(), Request{MaxTokens: 10}, func(string) {})
	var pe *ProviderError
	require.ErrorAs(t, err, &pe)
	assert.False(t, pe.OutOfCredit)
}

func TestStreamCancel(t *testing.T) {
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("content-type", "text/event-stream")
		_, _ = io.WriteString(w, "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":1}}}\n\n")
		w.(http.Flusher).Flush()
		select {
		case <-release:
		case <-r.Context().Done():
		}
	}))
	defer srv.Close()
	defer close(release)
	base, _ := url.Parse(srv.URL)
	a := &AnthropicMessages{Transport: provider.NewHTTPTransport(), BaseURL: base}
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(50*time.Millisecond, cancel)
	start := time.Now()
	_, err := a.Stream(ctx, Request{MaxTokens: 10}, func(string) {})
	require.ErrorIs(t, err, context.Canceled)
	assert.Less(t, time.Since(start), 2*time.Second)
}

type completeOnly struct{ resp Response }

func (completeOnly) Model() string    { return "fake" }
func (completeOnly) Pricing() Pricing { return Pricing{} }
func (c completeOnly) Complete(context.Context, Request) (Response, error) {
	return c.resp, nil
}

func TestStreamOrCompleteFallback(t *testing.T) {
	p := completeOnly{resp: Response{Content: []Block{block(map[string]string{"type": "text", "text": "whole answer"})}, Stop: StopDone}}
	var pieces []string
	resp, err := StreamOrComplete(context.Background(), p, Request{}, func(s string) { pieces = append(pieces, s) })
	require.NoError(t, err)
	assert.Equal(t, []string{"whole answer"}, pieces)
	assert.Equal(t, "whole answer", resp.Text())
}

func TestStreamOrCompleteUsesStreamer(t *testing.T) {
	a := streamServer(t, 200, textStream, nil)
	var pieces []string
	_, err := StreamOrComplete(context.Background(), a, Request{MaxTokens: 10}, func(s string) { pieces = append(pieces, s) })
	require.NoError(t, err)
	assert.Equal(t, []string{"Sev", "erance"}, pieces)
}

func callCount(t *testing.T, result string) float64 {
	t.Helper()
	var m dto.Metric
	require.NoError(t, metrics.LLMCalls.WithLabelValues("anthropic", result).Write(&m))
	return m.GetCounter().GetValue()
}
