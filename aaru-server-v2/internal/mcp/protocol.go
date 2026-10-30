// Package mcp is OUT-004 · MCP over streamable HTTP at `POST /v1/mcp` (MCP/*.swift), hand-rolled
// rather than from an SDK: the wire format is small, and the part an SDK would own (transport and
// auth) is exactly what must stay ours, because every call is one user's library through one
// revocable token.
//
// This package is the transport only: JSON-RPC, the tool catalog (names, descriptions and input
// schemas exactly as the Swift server advertised them; Claude's connector depends on them) and
// the route. The tools themselves run through the Tools interface, which internal/httpapi
// implements over internal/agent. Deleting this package and its route leaves every feature
// reachable through `/v1`.
package mcp

import (
	"encoding/json"
	"slices"
)

// Versions are the spec revisions this server speaks, newest first. `initialize` echoes the
// client's when it is one of these, else offers the newest.
var Versions = []string{"2025-11-25", "2025-06-18", "2025-03-26"}

const (
	// ServerName is the server's name in `initialize`.
	ServerName = "aaru"
	// ServerTitle is its display name.
	ServerTitle = "Aaru"
	// ServerVersion is the MCP surface's version, not the server's. Bump when a tool or schema changes.
	ServerVersion = "1.0.0"
)

// Negotiate is the protocol version to answer `initialize` with.
func Negotiate(requested *string) string {
	if requested != nil && slices.Contains(Versions, *requested) {
		return *requested
	}
	return Versions[0]
}

// Instructions tell the agent how to use the tools.
const Instructions = "Aaru is one person's private media library: movies, shows, anime and books, with what they plan " +
	"to watch or read, what they are in the middle of, and what they finished.\n\n" +
	"Read with read_library (their items, by status, type or list), list_airs (episodes of shows they " +
	"track airing soon, or their Up Next) and search_titles (the public catalog). Search before " +
	"adding, and add by the mediaRef a search hit gives you.\n\n" +
	"apply_library_patch changes the library only if the user allowed changes for this connection. " +
	"One item at a time applies at once, like a tap in the app, and the user can undo it there. " +
	"Anything larger, and any removal, becomes a request the user approves or denies inside Aaru: " +
	"the tool answers applied: false with a planId. Never tell the user something changed unless " +
	"the tool answered applied: true."

// JSON-RPC error codes. A tool that cannot do what was asked answers a normal result with
// `isError: true` instead, so the agent can react.
const (
	codeParseError     = -32700
	codeMethodNotFound = -32601
	codeInvalidParams  = -32602
)

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *rpcError) Error() string { return e.Message }

// response is one JSON-RPC answer. A nil id (a parse error) is left out, as Swift's
// encodeIfPresent did.
type response struct {
	JSONRPC string    `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  any       `json:"result,omitempty"`
	Error   *rpcError `json:"error,omitempty"`
}
