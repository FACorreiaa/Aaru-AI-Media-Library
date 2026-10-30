// Package stremio is SCR-003, the Stremio addon: a manifest, three personal catalogs, `meta` for
// titles without an IMDb id, and Stremio's `player` and `library` events. No `stream` resource, ever:
// Aaru does not touch stream sources. It is the port of Sources/App/Stremio.
package stremio

import (
	"aaru-go-api/internal/core"
	"net/url"
	"strconv"
	"strings"
	"unicode"

	"github.com/google/uuid"
)

// RouteKind is what a Stremio request asks for.
type RouteKind int

// The routes.
const (
	RouteManifest RouteKind = iota + 1
	RouteConfigure
	RouteResource
)

// Request is one request to the addon, parsed from its path. The protocol fixes the shapes:
// `/stremio/{token}/manifest.json`, `/stremio/{token}/{resource}/{type}/{id}.json` and
// `/stremio/{token}/{resource}/{type}/{id}/{extra}.json`, where `extra` is `a=b&c=d`.
type Request struct {
	Token string
	Kind  RouteKind
	// Name, Type, ID and Extra are set for a resource.
	Name  string
	Type  string
	ID    string
	Extra map[string]string
}

// ParseRequest parses a raw (still percent-encoded) path; false when it is not an addon path.
func ParseRequest(path string) (Request, bool) {
	rest, ok := strings.CutPrefix(path, "/stremio/")
	if !ok {
		return Request{}, false
	}
	segments := strings.Split(rest, "/")
	token := segments[0]
	if token == "" {
		return Request{}, false
	}
	r := Request{Token: token}
	parts := segments[1:]
	switch {
	case len(parts) == 0:
		r.Kind = RouteConfigure
	case len(parts) == 1 && parts[0] == "manifest.json":
		r.Kind = RouteManifest
	case len(parts) == 1 && (parts[0] == "configure" || parts[0] == ""):
		r.Kind = RouteConfigure
	case len(parts) == 3 || len(parts) == 4:
		last := parts[len(parts)-1]
		trimmed, isJSON := strings.CutSuffix(last, ".json")
		if !isJSON {
			return Request{}, false
		}
		id := trimmed
		if len(parts) == 4 {
			id = parts[2]
		}
		decoded, err := url.PathUnescape(id)
		if err != nil || decoded == "" {
			return Request{}, false
		}
		r.Kind, r.Name, r.Type, r.ID, r.Extra = RouteResource, parts[0], parts[1], decoded, map[string]string{}
		if len(parts) == 4 {
			r.Extra = Extra(trimmed)
		}
	default:
		return Request{}, false
	}
	return r, true
}

// Extra reads `action=stop&currentTime=1200&videoId=tt1%3A1%3A2` into keys and decoded values. A
// segment that arrives encoded whole (`action%3Dstop%26…`) is decoded once first.
func Extra(segment string) map[string]string {
	raw := segment
	if !strings.Contains(raw, "=") {
		if decoded, err := url.PathUnescape(raw); err == nil && strings.Contains(decoded, "=") {
			raw = decoded
		}
	}
	values := map[string]string{}
	for _, pair := range strings.Split(raw, "&") {
		if pair == "" {
			continue
		}
		// `a=` and `=b` are no pair: Swift's split drops the empty side.
		k, v, ok := strings.Cut(pair, "=")
		if !ok || k == "" || v == "" {
			continue
		}
		key, err := url.PathUnescape(k)
		if err != nil {
			continue
		}
		value, err := url.PathUnescape(strings.ReplaceAll(v, "+", " "))
		if err != nil {
			continue
		}
		values[key] = value
	}
	return values
}

// ID is a Stremio content id: an IMDb id (what Cinemeta and stream addons use) or Aaru's own
// `aaru:{titleId}` for titles without one; either with `:season:episode` for an episode.
type ID struct {
	// IMDB is set for an IMDb id; TitleID for an `aaru:` one.
	IMDB    string
	TitleID *uuid.UUID
	Episode *core.EpisodeKey
}

// ParseID reads a content id; false when it is neither form.
func ParseID(raw string) (ID, bool) {
	parts := strings.Split(raw, ":")
	var id ID
	switch first := parts[0]; {
	case first == "aaru":
		if len(parts) < 2 || len(parts[1]) != 36 {
			return ID{}, false
		}
		u, err := uuid.Parse(parts[1])
		if err != nil {
			return ID{}, false
		}
		id.TitleID = &u
		parts = parts[2:]
	case strings.HasPrefix(first, "tt") && len(first) > 2 && allNumbers(first[2:]):
		id.IMDB = first
		parts = parts[1:]
	default:
		return ID{}, false
	}
	switch len(parts) {
	case 0:
	case 2:
		season, err1 := strconv.Atoi(parts[0])
		number, err2 := strconv.Atoi(parts[1])
		if err1 != nil || err2 != nil {
			return ID{}, false
		}
		key, err := core.NewEpisodeKey(season, number)
		if err != nil {
			return ID{}, false
		}
		id.Episode = &key
	default:
		return ID{}, false
	}
	return id, true
}

func allNumbers(s string) bool {
	for _, r := range s {
		if !unicode.IsNumber(r) {
			return false
		}
	}
	return true
}

// SameBase is whether two ids name the same title.
func (id ID) SameBase(other ID) bool {
	if id.TitleID != nil || other.TitleID != nil {
		return id.TitleID != nil && other.TitleID != nil && *id.TitleID == *other.TitleID
	}
	return id.IMDB == other.IMDB
}

// ForTitle is the id Stremio should see for a title: its IMDb id when known, so Cinemeta supplies the
// details and stream addons recognise it; otherwise Aaru's own.
func ForTitle(t core.Title) string {
	if t.IDs.IMDB != "" {
		return t.IDs.IMDB
	}
	return "aaru:" + strings.ToLower(t.ID.String())
}

// Ref is the title id and external ids the id names.
func (id ID) Ref() (*uuid.UUID, core.ExternalIDs) {
	if id.TitleID != nil {
		return id.TitleID, core.ExternalIDs{}
	}
	return nil, core.ExternalIDs{IMDB: id.IMDB}
}
