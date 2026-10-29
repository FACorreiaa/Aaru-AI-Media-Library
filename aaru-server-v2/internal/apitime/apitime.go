// Package apitime is the wire form of every OpenAPI `date-time`.
//
// The Apple clients decode dates with swift-openapi-runtime's plain ISO-8601
// transcoder, which rejects fractional seconds, so a date always leaves the
// server as whole seconds in UTC (`2026-10-29T12:00:00Z`), as the Swift server
// sent it. Reading is lenient: a browser's `toISOString()` sends milliseconds.
package apitime

import (
	"encoding/json"
	"fmt"
	"time"
)

// Time is a `date-time` in a request or response body, query or path.
type Time struct {
	time.Time
}

// From wraps t for a response.
func From(t time.Time) Time {
	return Time{t}
}

// Ptr wraps t for an optional response field.
func Ptr(t time.Time) *Time {
	return &Time{t}
}

// PtrOrNil wraps t, or returns nil for a nil t.
func PtrOrNil(t *time.Time) *Time {
	if t == nil {
		return nil
	}
	return &Time{*t}
}

// Format is the whole-second UTC form the clients read.
func Format(t time.Time) string {
	return t.UTC().Truncate(time.Second).Format(time.RFC3339)
}

// Parse reads RFC 3339 with or without fractional seconds.
func Parse(s string) (time.Time, error) {
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t, nil
	}
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("parse date-time %q: %w", s, err)
	}
	return t, nil
}

// MarshalJSON writes whole seconds in UTC.
func (t Time) MarshalJSON() ([]byte, error) {
	return json.Marshal(Format(t.Time))
}

// UnmarshalJSON reads RFC 3339, fractional seconds allowed.
func (t *Time) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return fmt.Errorf("date-time must be a string: %w", err)
	}
	parsed, err := Parse(s)
	if err != nil {
		return err
	}
	t.Time = parsed
	return nil
}

// MarshalText is the query and path form.
func (t Time) MarshalText() ([]byte, error) {
	return []byte(Format(t.Time)), nil
}

// UnmarshalText reads a query or path value.
func (t *Time) UnmarshalText(data []byte) error {
	parsed, err := Parse(string(data))
	if err != nil {
		return err
	}
	t.Time = parsed
	return nil
}

// Bind lets oapi-codegen's runtime bind a parameter.
func (t *Time) Bind(src string) error {
	return t.UnmarshalText([]byte(src))
}
