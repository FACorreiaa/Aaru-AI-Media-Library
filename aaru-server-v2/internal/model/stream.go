package model

import (
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/provider"
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
)

// streamTransport is a provider.Transport that can also hand back an unbuffered body.
type streamTransport interface {
	Stream(ctx context.Context, req provider.Request) (*provider.StreamResponse, error)
}

// defaultStreamTimeout bounds a whole streamed answer.
const defaultStreamTimeout = 120 * time.Second

// maxSSELine is the longest event line read; a tool input can be large.
const maxSSELine = 4 * 1024 * 1024

// Stream is Complete over the Messages API's server-sent events: onText gets each
// text delta in order, and the Response is rebuilt whole, thinking and unknown
// blocks included, so it replays as an assistant turn. Counted in
// `aaru_llm_calls_total` like Complete. The Transport must support streaming
// (provider.HTTPTransport does).
func (a *AnthropicMessages) Stream(ctx context.Context, req Request, onText func(string)) (Response, error) {
	resp, err := a.stream(ctx, req, onText)
	metrics.LLMCalls.WithLabelValues("anthropic", llmResult(err)).Inc()
	return resp, err
}

func (a *AnthropicMessages) stream(ctx context.Context, req Request, onText func(string)) (Response, error) {
	st, ok := a.Transport.(streamTransport)
	if !ok {
		return Response{}, errors.New("messages stream: transport cannot stream")
	}
	payload := AnthropicBody(req, a.ModelName, a.Effort)
	payload["stream"] = true
	body, err := json.Marshal(payload)
	if err != nil {
		return Response{}, fmt.Errorf("encode messages request: %w", err)
	}
	resp, err := st.Stream(ctx, provider.Request{
		Method:  "POST",
		URL:     a.BaseURL.JoinPath("v1/messages").String(),
		Headers: a.headers(),
		Body:    body,
		Timeout: cmpDuration(a.Timeout, defaultStreamTimeout),
	})
	if err != nil {
		return Response{}, fmt.Errorf("messages stream: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.Status < 200 || resp.Status >= 300 {
		text, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
		return Response{}, statusError(resp.Status, string(text))
	}
	out, err := readStream(resp.Body, onText)
	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return Response{}, fmt.Errorf("messages stream: %w", ctxErr)
		}
		return Response{}, err
	}
	return out, nil
}

// streamBlock is a content block being rebuilt from its deltas.
type streamBlock struct {
	fields map[string]json.RawMessage
	text   strings.Builder
	input  strings.Builder
	think  strings.Builder
	sig    strings.Builder
	kind   string
}

func (b *streamBlock) raw() (Block, error) {
	switch b.kind {
	case "text":
		b.fields["text"] = mustJSON(b.text.String())
	case "tool_use":
		if in := strings.TrimSpace(b.input.String()); in != "" {
			if !json.Valid([]byte(in)) {
				return nil, fmt.Errorf("messages stream: tool input is not JSON")
			}
			b.fields["input"] = json.RawMessage(in)
		} else {
			b.fields["input"] = json.RawMessage(`{}`)
		}
	case "thinking":
		b.fields["thinking"] = mustJSON(b.think.String())
		if b.sig.Len() > 0 {
			b.fields["signature"] = mustJSON(b.sig.String())
		}
	}
	return json.Marshal(b.fields)
}

func mustJSON(v any) json.RawMessage {
	data, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("model: encode: %v", err))
	}
	return data
}

type sseEvent struct {
	Type  string `json:"type"`
	Index int    `json:"index"`
	// message_start
	Message struct {
		Usage struct {
			InputTokens int `json:"input_tokens"`
		} `json:"usage"`
	} `json:"message"`
	// content_block_start
	ContentBlock json.RawMessage `json:"content_block"`
	// content_block_delta and message_delta
	Delta struct {
		Type        string  `json:"type"`
		Text        string  `json:"text"`
		PartialJSON string  `json:"partial_json"`
		Thinking    string  `json:"thinking"`
		Signature   string  `json:"signature"`
		StopReason  *string `json:"stop_reason"`
	} `json:"delta"`
	Usage struct {
		InputTokens  *int `json:"input_tokens"`
		OutputTokens int  `json:"output_tokens"`
	} `json:"usage"`
	Error struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

// readStream folds an SSE body into a Response.
func readStream(r io.Reader, onText func(string)) (Response, error) {
	var (
		out     Response
		blocks  = map[int]*streamBlock{}
		order   []int
		stop    *string
		stopped bool
		data    bytes.Buffer
	)
	finish := func() (bool, error) {
		if data.Len() == 0 {
			return false, nil
		}
		defer data.Reset()
		var ev sseEvent
		if err := json.Unmarshal(data.Bytes(), &ev); err != nil {
			return false, &ProviderError{Status: 200}
		}
		switch ev.Type {
		case "message_start":
			out.InputTokens = ev.Message.Usage.InputTokens
		case "content_block_start":
			b := &streamBlock{fields: map[string]json.RawMessage{}}
			if err := json.Unmarshal(ev.ContentBlock, &b.fields); err != nil {
				return false, &ProviderError{Status: 200}
			}
			_ = json.Unmarshal(b.fields["type"], &b.kind)
			if b.kind == "text" {
				var seed string
				_ = json.Unmarshal(b.fields["text"], &seed)
				b.text.WriteString(seed)
			}
			blocks[ev.Index] = b
			order = append(order, ev.Index)
		case "content_block_delta":
			b := blocks[ev.Index]
			if b == nil {
				return false, &ProviderError{Status: 200}
			}
			switch ev.Delta.Type {
			case "text_delta":
				b.text.WriteString(ev.Delta.Text)
				if ev.Delta.Text != "" && onText != nil {
					onText(ev.Delta.Text)
				}
			case "input_json_delta":
				b.input.WriteString(ev.Delta.PartialJSON)
			case "thinking_delta":
				b.think.WriteString(ev.Delta.Thinking)
			case "signature_delta":
				b.sig.WriteString(ev.Delta.Signature)
			}
		case "message_delta":
			stop = ev.Delta.StopReason
			out.OutputTokens = ev.Usage.OutputTokens
			if ev.Usage.InputTokens != nil {
				out.InputTokens = *ev.Usage.InputTokens
			}
		case "message_stop":
			return true, nil
		case "error":
			return false, fmt.Errorf("messages stream: %w", &ProviderError{
				Status:      200,
				OutOfCredit: strings.Contains(ev.Error.Message, "usage limit") || strings.Contains(ev.Error.Message, "credit balance"),
			})
		}
		return false, nil
	}

	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), maxSSELine)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case line == "":
			done, err := finish()
			if err != nil {
				return Response{}, err
			}
			if done {
				stopped = true
			}
		case strings.HasPrefix(line, "data:"):
			data.WriteString(strings.TrimPrefix(strings.TrimPrefix(line, "data:"), " "))
		}
		if stopped {
			break
		}
	}
	if !stopped {
		// A final event may lack its blank line.
		done, err := finish()
		if err != nil {
			return Response{}, err
		}
		stopped = done
	}
	if err := sc.Err(); err != nil && !stopped {
		return Response{}, fmt.Errorf("messages stream: read: %w", err)
	}
	if !stopped {
		return Response{}, &ProviderError{Status: 200}
	}
	for _, i := range order {
		raw, err := blocks[i].raw()
		if err != nil {
			return Response{}, err
		}
		out.Content = append(out.Content, raw)
	}
	if out.Content == nil {
		out.Content = []Block{}
	}
	out.Stop = mapStop(stop)
	return out, nil
}
