// Package model is the agent's language model (AG-007): a wire-format adapter
// behind Provider, so no vendor name appears outside its adapter. Used by
// capture, `@aaru` replies in groups, and the agent tools.
package model

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"strings"
)

// Block is one raw content block. Blocks travel raw so one the adapter does not
// know (thinking, anything the API adds later) is replayed unchanged.
type Block = json.RawMessage

// Tool is one the model may call. Every agent tool is a read; none writes (X-009).
type Tool struct {
	Name        string
	Description string
	// InputSchema is the tool input's JSON Schema.
	InputSchema json.RawMessage
}

// Role of a turn.
type Role string

// Roles.
const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Turn is one turn of the transcript.
type Turn struct {
	Role    Role
	Content []Block
}

func block(v any) Block {
	data, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("model: encode block: %v", err))
	}
	return data
}

// UserText is a user turn of one text block.
func UserText(text string) Turn {
	return Turn{Role: RoleUser, Content: []Block{block(map[string]string{"type": "text", "text": text})}}
}

// UserImage is one base64 image and the words about it, in that order.
func UserImage(image []byte, mediaType, text string) Turn {
	return Turn{Role: RoleUser, Content: []Block{
		block(map[string]any{
			"type":   "image",
			"source": map[string]string{"type": "base64", "media_type": mediaType, "data": base64.StdEncoding.EncodeToString(image)},
		}),
		block(map[string]string{"type": "text", "text": text}),
	}}
}

// Request is one model call.
type Request struct {
	System    string
	Turns     []Turn
	Tools     []Tool
	MaxTokens int
	// ToolChoice forces a tool by name; "" lets the model choose. Claude Haiku 5.5
	// accepts a forced call; Opus 5.5, Sonnet 5.5 and Fable 5.1 answer it with a 400.
	ToolChoice string
}

// Stop is why the model stopped.
type Stop string

// Stops. Anything else arrives as its raw reason ("none" when absent).
const (
	StopDone      Stop = "done"
	StopToolUse   Stop = "tool_use"
	StopMaxTokens Stop = "max_tokens"
	StopRefusal   Stop = "refusal"
)

// Response is one answer.
type Response struct {
	// Content is the assistant's blocks, appended to the transcript as they are.
	Content      []Block
	Stop         Stop
	InputTokens  int
	OutputTokens int
}

type blockHead struct {
	Type  string          `json:"type"`
	Text  string          `json:"text"`
	ID    string          `json:"id"`
	Name  string          `json:"name"`
	Input json.RawMessage `json:"input"`
}

// Text is the text blocks, joined by newlines.
func (r Response) Text() string {
	var parts []string
	for _, b := range r.Content {
		var h blockHead
		if json.Unmarshal(b, &h) == nil && h.Type == "text" {
			parts = append(parts, h.Text)
		}
	}
	return strings.Join(parts, "\n")
}

// ToolCall is one `tool_use` block.
type ToolCall struct {
	ID    string
	Name  string
	Input json.RawMessage
}

// ToolCalls are the `tool_use` blocks.
func (r Response) ToolCalls() []ToolCall {
	var calls []ToolCall
	for _, b := range r.Content {
		var h blockHead
		if json.Unmarshal(b, &h) != nil || h.Type != "tool_use" || h.ID == "" || h.Name == "" {
			continue
		}
		input := h.Input
		if len(input) == 0 || string(input) == "null" {
			input = json.RawMessage(`{}`)
		}
		calls = append(calls, ToolCall{ID: h.ID, Name: h.Name, Input: input})
	}
	return calls
}

// Provider is the agent's model.
type Provider interface {
	Model() string
	// Pricing is what a call costs, for `agent_usage`.
	Pricing() Pricing
	Complete(ctx context.Context, req Request) (Response, error)
}

// Pricing is dollars per million tokens, the same number as millionths of a dollar per token.
type Pricing struct {
	InputPerMTok  float64
	OutputPerMTok float64
}

// Micros is one response's cost in millionths of a dollar, rounded up.
func (p Pricing) Micros(r Response) int {
	return int(math.Ceil(float64(r.InputTokens)*p.InputPerMTok + float64(r.OutputTokens)*p.OutputPerMTok))
}

// ProviderError is an error status, or nothing usable, from the provider.
type ProviderError struct {
	Status      int
	OutOfCredit bool
}

func (e *ProviderError) Error() string {
	return fmt.Sprintf("model provider answered %d (out of credit: %t)", e.Status, e.OutOfCredit)
}
