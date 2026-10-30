// Package apiid is the wire form of every OpenAPI `format: uuid`.
//
// The Swift server wrote ids with Foundation's `uuidString`, which is
// uppercase, and clients keep those strings (caches, links, the web compares
// them as text), so ids leave this server uppercase too. swift-openapi-generator
// typed `format: uuid` as a plain String, so a malformed id never failed
// decoding there: here it reads as uuid.Nil, which matches no row, and the
// route answers its usual 404 instead of a 400.
package apiid

import (
	"strings"

	"github.com/google/uuid"
)

// UUID is an id in a request or response.
type UUID uuid.UUID

// From wraps a domain id for a response.
func From(id uuid.UUID) UUID { return UUID(id) }

// Ptr wraps a domain id for an optional response field.
func Ptr(id uuid.UUID) *UUID {
	u := UUID(id)
	return &u
}

// PtrOrNil wraps an optional domain id.
func PtrOrNil(id *uuid.UUID) *UUID {
	if id == nil {
		return nil
	}
	return Ptr(*id)
}

// Slice wraps a list of domain ids.
func Slice(ids []uuid.UUID) []UUID {
	out := make([]UUID, len(ids))
	for i, id := range ids {
		out[i] = UUID(id)
	}
	return out
}

// IDs unwraps a list of request ids.
func IDs(ids []UUID) []uuid.UUID {
	out := make([]uuid.UUID, len(ids))
	for i, id := range ids {
		out[i] = uuid.UUID(id)
	}
	return out
}

// ID is the domain id.
func (u UUID) ID() uuid.UUID { return uuid.UUID(u) }

// String is the uppercase form Swift's `uuidString` produced.
func (u UUID) String() string { return strings.ToUpper(uuid.UUID(u).String()) }

// MarshalText writes the uppercase form (JSON strings and map keys use it).
func (u UUID) MarshalText() ([]byte, error) { return []byte(u.String()), nil }

// UnmarshalText reads any case; a malformed id reads as uuid.Nil.
func (u *UUID) UnmarshalText(data []byte) error {
	parsed, err := uuid.ParseBytes(data)
	if err != nil {
		*u = UUID(uuid.Nil)
		return nil
	}
	*u = UUID(parsed)
	return nil
}

// Bind lets oapi-codegen's runtime bind a path or query parameter.
func (u *UUID) Bind(src string) error { return u.UnmarshalText([]byte(src)) }
