package mcp

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/middleware"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"slices"
	"strings"

	"github.com/labstack/echo/v4"
)

const (
	// Path is the MCP endpoint.
	Path = "/v1/mcp"
	// MaxBody is the largest request body.
	MaxBody = 1 << 20
)

// ErrArguments marks a tool's arguments that do not decode as its input (Swift's DecodingError).
// The agent is told they do not match the input schema.
var ErrArguments = errors.New("arguments do not match the input schema")

// Tools runs one tool for an authenticated caller. It returns a JSON-encodable result, or an error:
// one with a ToolMessage() is shown to the agent as is, as is an apperr below 500; ErrArguments
// says the arguments do not match; anything else is logged and the agent hears the tool failed.
type Tools interface {
	Call(ctx context.Context, name string, args json.RawMessage, caller auth.AgentCaller) (any, error)
}

// Authenticator checks agent tokens (auth.AgentTokenService).
type Authenticator interface {
	Authenticate(ctx context.Context, secret string, group auth.TokenGroup) (auth.AgentCaller, bool, error)
	Allow(caller auth.AgentCaller) bool
}

// Handler is `POST /v1/mcp` (MCPRoutes). Stateless: no session id, no server stream, one JSON
// answer per request. It authenticates itself: only an MCP agent token (or a Claude connector's
// OAuth access token) gets in, never a session or a Stremio link, and the token is looked up once
// per request.
type Handler struct {
	Tokens Authenticator
	Tools  Tools
	// ResourceMetadataURL points an OAuth client (Claude's connector) at the resource metadata.
	ResourceMetadataURL string
	// AllowedOrigins are browser origins allowed to call, lowercased. Real MCP clients send none;
	// the Swift server allowed none.
	AllowedOrigins map[string]bool
	Log            *slog.Logger
}

func (h *Handler) log() *slog.Logger {
	if h.Log == nil {
		return slog.Default()
	}
	return h.Log
}

// Register adds the route; GET and DELETE answer 405 (no server-initiated stream, no sessions).
func (h *Handler) Register(e *echo.Echo) {
	e.POST(Path, h.post)
	notAllowed := func(c echo.Context) error {
		c.Response().Header().Set("Allow", "POST")
		return c.NoContent(http.StatusMethodNotAllowed)
	}
	e.GET(Path, notAllowed)
	e.DELETE(Path, notAllowed)
}

func plain(c echo.Context, status int, message string) error {
	h := c.Response().Header()
	h.Set("Content-Type", "text/plain; charset=utf-8")
	h.Set("Cache-Control", "no-store")
	c.Response().WriteHeader(status)
	_, err := c.Response().Write([]byte(message))
	return err
}

func (h *Handler) post(c echo.Context) error {
	req := c.Request()
	if origin := req.Header.Get("Origin"); origin != "" && !h.AllowedOrigins[strings.ToLower(origin)] {
		return plain(c, http.StatusForbidden, "This origin may not call Aaru's MCP endpoint.")
	}
	if values, ok := req.Header[http.CanonicalHeaderKey("MCP-Protocol-Version")]; ok && len(values) > 0 &&
		!slices.Contains(Versions, values[0]) {
		return plain(c, http.StatusBadRequest, "Unsupported MCP-Protocol-Version "+values[0]+".")
	}
	ctx := req.Context()
	secret := middleware.BearerToken(req.Header.Get("Authorization"))
	caller, ok, err := h.Tokens.Authenticate(ctx, secret, auth.GroupMCP)
	if err != nil {
		h.log().ErrorContext(ctx, "MCP request failed", "error", err.Error())
		return plain(c, http.StatusInternalServerError, "Something went wrong.")
	}
	if !ok {
		c.Response().Header().Set("WWW-Authenticate", `Bearer realm="aaru", resource_metadata="`+h.ResourceMetadataURL+`"`)
		return plain(c, http.StatusUnauthorized, "Connect this client in Aaru → Settings → Connections.")
	}
	if !h.Tokens.Allow(caller) {
		return plain(c, http.StatusTooManyRequests, "Too many requests. Wait a minute.")
	}
	body, err := io.ReadAll(io.LimitReader(req.Body, MaxBody+1))
	if err != nil || len(body) > MaxBody {
		return plain(c, http.StatusRequestEntityTooLarge, "Requests are at most 1 MiB.")
	}
	answer, err := h.handle(ctx, body, caller)
	if err != nil {
		h.log().ErrorContext(ctx, "MCP request failed", "error", err.Error())
		return plain(c, http.StatusInternalServerError, "Something went wrong.")
	}
	if answer == nil {
		// Notifications and client responses get 202 and no body.
		return c.NoContent(http.StatusAccepted)
	}
	data, err := encode(answer)
	if err != nil {
		return plain(c, http.StatusInternalServerError, "Something went wrong.")
	}
	hdr := c.Response().Header()
	hdr.Set("Content-Type", "application/json")
	hdr.Set("Cache-Control", "no-store")
	c.Response().WriteHeader(http.StatusOK)
	_, err = c.Response().Write(data)
	return err
}

// request is one JSON-RPC request, read as Swift's Decodable MCPRequest did: an object whose
// `method` is a string and whose `jsonrpc`, when present, is one too. An absent or null id is a
// notification.
type request struct {
	id     json.RawMessage
	method string
	params json.RawMessage
}

func parse(body []byte) (request, bool) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(body, &fields); err != nil || fields == nil {
		// A JSON-RPC batch (an array) lands here too: removed from the spec in 2025-06-18.
		return request{}, false
	}
	if raw, ok := fields["jsonrpc"]; ok && !isNull(raw) {
		var s string
		if json.Unmarshal(raw, &s) != nil {
			return request{}, false
		}
	}
	var r request
	raw, ok := fields["method"]
	if !ok || isNull(raw) || json.Unmarshal(raw, &r.method) != nil {
		return request{}, false
	}
	if id, ok := fields["id"]; ok && !isNull(id) {
		var compact bytes.Buffer
		if err := json.Compact(&compact, id); err != nil {
			return request{}, false
		}
		r.id = compact.Bytes()
	}
	if params, ok := fields["params"]; ok && !isNull(params) {
		r.params = params
	}
	return r, true
}

func isNull(raw json.RawMessage) bool { return string(bytes.TrimSpace(raw)) == "null" }

// handle answers one request; nil for a notification. An error is a failure outside JSON-RPC (500).
func (h *Handler) handle(ctx context.Context, body []byte, caller auth.AgentCaller) (*response, error) {
	r, ok := parse(body)
	if !ok {
		return &response{JSONRPC: "2.0", Error: &rpcError{Code: codeParseError, Message: "The body is not one JSON-RPC request."}}, nil
	}
	if r.id == nil {
		return nil, nil
	}
	result, err := h.dispatch(ctx, r, caller)
	if err != nil {
		var rpc *rpcError
		if errors.As(err, &rpc) {
			return &response{JSONRPC: "2.0", ID: r.id, Error: rpc}, nil
		}
		return nil, err
	}
	return &response{JSONRPC: "2.0", ID: r.id, Result: result}, nil
}

func objectOf(raw json.RawMessage) map[string]json.RawMessage {
	var m map[string]json.RawMessage
	if len(raw) == 0 || json.Unmarshal(raw, &m) != nil {
		return nil
	}
	return m
}

func stringOf(raw json.RawMessage) (string, bool) {
	var s string
	if raw == nil || isNull(raw) || json.Unmarshal(raw, &s) != nil {
		return "", false
	}
	return s, true
}

func (h *Handler) dispatch(ctx context.Context, r request, caller auth.AgentCaller) (any, error) {
	switch r.method {
	case "initialize":
		var requested *string
		if v, ok := stringOf(objectOf(r.params)["protocolVersion"]); ok {
			requested = &v
		}
		return map[string]any{
			"protocolVersion": Negotiate(requested),
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": ServerName, "title": ServerTitle, "version": ServerVersion},
			"instructions":    Instructions,
		}, nil
	case "ping":
		return map[string]any{}, nil
	case "tools/list":
		return map[string]any{"tools": Listing()}, nil
	case "tools/call":
		return h.call(ctx, r.params, caller)
	}
	return nil, &rpcError{Code: codeMethodNotFound, Message: "Aaru does not support " + r.method + "."}
}

func (h *Handler) call(ctx context.Context, rawParams json.RawMessage, caller auth.AgentCaller) (any, error) {
	params := objectOf(rawParams)
	name, ok := stringOf(params["name"])
	if params == nil || !ok {
		return nil, &rpcError{Code: codeInvalidParams, Message: "tools/call needs a name."}
	}
	tool, ok := ToolNamed(name)
	if !ok {
		return nil, &rpcError{Code: codeInvalidParams, Message: "Aaru has no tool named " + name + "."}
	}
	args := objectOf(params["arguments"])
	if args == nil {
		args = map[string]json.RawMessage{}
	}
	names := make([]string, 0, len(args))
	for k := range args {
		names = append(names, k)
	}
	if unknown, found := tool.UnknownArgument(names); found {
		return toolError(name + " has no argument " + unknown + "."), nil
	}
	argsJSON, err := json.Marshal(args)
	if err != nil {
		return nil, err
	}
	result, err := h.Tools.Call(ctx, name, argsJSON, caller)
	if err != nil {
		return h.failure(ctx, name, err)
	}
	return toolResult(result)
}

// failure turns a tool's error into what the agent reads. Never hand an agent an internal message
// it would repeat to the user.
func (h *Handler) failure(ctx context.Context, name string, err error) (any, error) {
	var messenger interface{ ToolMessage() string }
	if errors.As(err, &messenger) {
		return toolError(messenger.ToolMessage()), nil
	}
	if errors.Is(err, ErrArguments) {
		return toolError("The arguments for " + name + " do not match its input schema."), nil
	}
	if e := apperr.From(err); e != nil && e.Status < http.StatusInternalServerError {
		return toolError(e.Message), nil
	}
	if errors.Is(err, context.Canceled) {
		return nil, err
	}
	h.log().ErrorContext(ctx, "MCP tool failed", "tool", name, "error", err.Error())
	return toolError("Aaru could not finish " + name + ". Try again later."), nil
}

// toolResult is structured content plus a text rendering; clients differ in which they show. The
// result goes through plain JSON values first, as Swift's JSONValue did (every number a Double).
func toolResult(result any) (any, error) {
	data, err := json.Marshal(result)
	if err != nil {
		return nil, err
	}
	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		return nil, err
	}
	text, err := encode(value) // map keys sorted: Swift's .sortedKeys
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"content":           []any{map[string]any{"type": "text", "text": string(text)}},
		"structuredContent": value,
		"isError":           false,
	}, nil
}

func toolError(message string) any {
	return map[string]any{
		"content": []any{map[string]any{"type": "text", "text": message}},
		"isError": true,
	}
}

// encode is JSON without escaping slashes or HTML characters, as Foundation writes it.
func encode(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}
