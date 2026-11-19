package model

import (
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// AnthropicVersion is the `anthropic-version` header.
const AnthropicVersion = "2023-06-01"

// AnthropicWebSearchTool is the web search tool's type: the basic one, which Claude Haiku 5.5
// takes and which runs no code (ASK-004). The `_20260209` variant filters results with code
// execution, at more tokens.
const AnthropicWebSearchTool = "web_search_20250305"

// AnthropicWebSearchMicros is one web search on the Claude API: $10 per 1,000.
const AnthropicWebSearchMicros = 10_000

// AnthropicMessages is Provider over Anthropic's Messages API (`POST /v1/messages`).
// Named for the wire format, so pointing ANTHROPIC_BASE_URL at a compatible
// endpoint is configuration, not code.
//
// Claude Haiku 5.5 answers any non-default `temperature`, `top_p` or `top_k`,
// and an assistant prefill, with a 400 (platform/infra/docs/llm-haiku-trial.md),
// so the body never carries them. Thinking is left to the model's adaptive
// default; its blocks come back in Content and are replayed unchanged.
type AnthropicMessages struct {
	Transport provider.Transport
	APIKey    string
	ModelName string
	Price     Pricing
	BaseURL   *url.URL
	// Effort is `output_config.effort`; "" leaves the model's default.
	Effort string
	// WorkspaceID is `anthropic-workspace-id`, which a key not scoped to one workspace must send.
	WorkspaceID string
	Timeout     time.Duration
	// WebSearch says the key's organization allows web search, so a Request's WebSearch is sent.
	WebSearch bool
}

// SearchesWeb is the WebSearch setting.
func (a *AnthropicMessages) SearchesWeb() bool { return a.WebSearch }

// Model is the configured model id.
func (a *AnthropicMessages) Model() string { return a.ModelName }

// Pricing is the configured price.
func (a *AnthropicMessages) Pricing() Pricing { return a.Price }

// Complete makes one call and counts it in `aaru_llm_calls_total`.
func (a *AnthropicMessages) Complete(ctx context.Context, req Request) (Response, error) {
	resp, err := a.call(ctx, req)
	metrics.LLMCalls.WithLabelValues("anthropic", llmResult(err)).Inc()
	return resp, err
}

func (a *AnthropicMessages) call(ctx context.Context, req Request) (Response, error) {
	body, err := json.Marshal(a.body(req))
	if err != nil {
		return Response{}, fmt.Errorf("encode messages request: %w", err)
	}
	resp, err := a.Transport.Send(ctx, provider.Request{
		Method:  "POST",
		URL:     a.BaseURL.JoinPath("v1/messages").String(),
		Headers: a.headers(),
		Body:    body,
		Timeout: cmpDuration(a.Timeout, 60*time.Second),
	})
	if err != nil {
		return Response{}, fmt.Errorf("messages request: %w", err)
	}
	if resp.Status < 200 || resp.Status >= 300 {
		return Response{}, statusError(resp.Status, string(resp.Body))
	}
	return ParseAnthropic(resp.Body)
}

func cmpDuration(d, fallback time.Duration) time.Duration {
	if d == 0 {
		return fallback
	}
	return d
}

func (a *AnthropicMessages) headers() [][2]string {
	headers := [][2]string{
		{"content-type", "application/json"},
		{"x-api-key", a.APIKey},
		{"anthropic-version", AnthropicVersion},
	}
	if a.WorkspaceID != "" {
		headers = append(headers, [2]string{"anthropic-workspace-id", a.WorkspaceID})
	}
	return headers
}

// statusError is the error for a non-2xx answer; a 400 that names the usage limit or
// credit balance is the trial cap being hit.
func statusError(status int, text string) *ProviderError {
	return &ProviderError{
		Status:      status,
		OutOfCredit: strings.Contains(text, "usage limit") || strings.Contains(text, "credit balance"),
	}
}

// llmResult is the `aaru_llm_calls_total` result label for a call's error.
func llmResult(err error) string {
	if err == nil {
		return "ok"
	}
	var pe *ProviderError
	switch {
	case errors.As(err, &pe) && pe.OutOfCredit:
		return "out_of_credit"
	case errors.As(err, &pe):
		return "http_error"
	default:
		return "error"
	}
}

// mapStop maps the API's stop_reason onto Stop.
func mapStop(reason *string) Stop {
	if reason == nil {
		return Stop("none")
	}
	switch *reason {
	case "end_turn", "stop_sequence":
		return StopDone
	case "tool_use":
		return StopToolUse
	case "max_tokens":
		return StopMaxTokens
	case "refusal":
		return StopRefusal
	case "pause_turn":
		return StopPaused
	default:
		return Stop(*reason)
	}
}

// AnthropicBody is the request body. Deliberately no sampling fields and no prefill.
func AnthropicBody(req Request, model, effort string) map[string]any {
	messages := make([]map[string]any, len(req.Turns))
	for i, t := range req.Turns {
		content := t.Content
		if content == nil {
			content = []Block{}
		}
		messages[i] = map[string]any{"role": string(t.Role), "content": content}
	}
	body := map[string]any{
		"model":      model,
		"max_tokens": req.MaxTokens,
		"system":     req.System,
		"messages":   messages,
	}
	tools := make([]map[string]any, 0, len(req.Tools)+1)
	for _, t := range req.Tools {
		tools = append(tools, map[string]any{"name": t.Name, "description": t.Description, "input_schema": t.InputSchema})
	}
	if req.WebSearch != nil {
		search := map[string]any{
			"type": AnthropicWebSearchTool, "name": "web_search", "max_uses": max(req.WebSearch.MaxUses, 1),
		}
		if len(req.WebSearch.BlockedDomains) > 0 {
			search["blocked_domains"] = req.WebSearch.BlockedDomains
		}
		tools = append(tools, search)
	}
	if len(tools) > 0 {
		body["tools"] = tools
	}
	if req.ToolChoice != "" {
		body["tool_choice"] = map[string]string{"type": "tool", "name": req.ToolChoice}
	}
	if req.Effort != "" {
		effort = req.Effort
	}
	if effort != "" {
		body["output_config"] = map[string]string{"effort": effort}
	}
	return body
}

// body is AnthropicBody, without the web search when the provider is not set to send it.
func (a *AnthropicMessages) body(req Request) map[string]any {
	if !a.WebSearch {
		req.WebSearch = nil
	}
	return AnthropicBody(req, a.ModelName, a.Effort)
}

// anthropicUsage is a Messages API answer's `usage`.
type anthropicUsage struct {
	InputTokens   *int `json:"input_tokens"`
	OutputTokens  int  `json:"output_tokens"`
	ServerToolUse struct {
		WebSearchRequests int `json:"web_search_requests"`
	} `json:"server_tool_use"`
}

// ParseAnthropic reads a Messages API answer.
func ParseAnthropic(data []byte) (Response, error) {
	var raw struct {
		Content    []Block        `json:"content"`
		StopReason *string        `json:"stop_reason"`
		Usage      anthropicUsage `json:"usage"`
	}
	if err := json.Unmarshal(data, &raw); err != nil || raw.Content == nil {
		return Response{}, &ProviderError{Status: 200}
	}
	stop := mapStop(raw.StopReason)
	out := Response{
		Content: raw.Content, Stop: stop, OutputTokens: raw.Usage.OutputTokens,
		WebSearches: raw.Usage.ServerToolUse.WebSearchRequests,
	}
	if raw.Usage.InputTokens != nil {
		out.InputTokens = *raw.Usage.InputTokens
	}
	return out, nil
}
