package catalog

import (
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"net/url"
	"os"
	"strconv"
	"time"
)

// DefaultAnimeMappingsSource is the pinned source `aaru --anime-mappings` reads when
// given no other path or URL.
const DefaultAnimeMappingsSource = "https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-full.json"

// animeMappingsMaxBytes bounds the downloaded list (it is about 10 MB today).
const animeMappingsMaxBytes = 64 << 20

// ParseAnimeMappings (CAT-010) parses Fribb's `anime-list-full.json` (MIT,
// github.com/Fribb/anime-lists) into AniList to TMDB/TVDB/MAL/AniDB mappings.
// Catalog data only, no user rows.
//
// Only a TMDB TV id is kept: the resolver resolves a mapping as a TMDB show, so a
// film's TMDB movie id would attach the anime to whichever show shares that number.
func ParseAnimeMappings(data []byte) ([]AnimeMapping, error) {
	var entries []fribbEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return nil, err
	}
	mappings := []AnimeMapping{}
	for _, e := range entries {
		if e.AniList == nil {
			continue
		}
		tmdb := e.TMDB.show()
		m := AnimeMapping{
			AniList: strconv.Itoa(*e.AniList), MAL: itoaPtr(e.MAL), AniDB: itoaPtr(e.AniDB), TVDB: itoaPtr(e.TVDB),
			TMDB: itoaPtr(tmdb),
		}
		if tmdb != nil && e.Season != nil {
			m.TMDBSeason = e.Season.TMDB
		}
		mappings = append(mappings, m)
	}
	return mappings, nil
}

// LoadAnimeMappings reads a local path or an http(s) URL.
func LoadAnimeMappings(ctx context.Context, source string, transport provider.Transport) ([]byte, error) {
	u, err := url.Parse(source)
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") {
		return os.ReadFile(source) //nolint:gosec // the operator names the file on the command line
	}
	resp, err := transport.Send(ctx, provider.Request{Method: "GET", URL: source, Timeout: 120 * time.Second})
	if err != nil {
		return nil, err
	}
	if resp.Status != 200 {
		return nil, provider.NewError("anime-lists", provider.KindUnavailable)
	}
	return resp.Body, nil
}

// NewAnimeMappingsTransport is the transport LoadAnimeMappings uses for a URL: the
// shared HTTP transport with a body limit big enough for the whole list.
func NewAnimeMappingsTransport() provider.Transport {
	t := provider.NewHTTPTransport()
	t.MaxBodyBytes = animeMappingsMaxBytes
	return t
}

func itoaPtr(n *int) *string {
	if n == nil {
		return nil
	}
	s := strconv.Itoa(*n)
	return &s
}

// fribbEntry is one row of Fribb's `anime-list-full.json`.
type fribbEntry struct {
	AniList *int       `json:"anilist_id"`
	MAL     *int       `json:"mal_id"`
	AniDB   *int       `json:"anidb_id"`
	TVDB    *int       `json:"tvdb_id"`
	TMDB    *fribbTMDB `json:"themoviedb_id"`
	Season  *struct {
		TMDB *int `json:"tmdb"`
	} `json:"season"`
}

// fribbTMDB is the TMDB TV id; a movie id is never read. It is a single id, or a
// list when one entry spans several TMDB records.
type fribbTMDB struct {
	TV json.RawMessage `json:"tv"`
}

func (f *fribbTMDB) show() *int {
	if f == nil || len(f.TV) == 0 {
		return nil
	}
	var one int
	if json.Unmarshal(f.TV, &one) == nil {
		return &one
	}
	var many []int
	if json.Unmarshal(f.TV, &many) == nil && len(many) > 0 {
		return &many[0]
	}
	return nil
}
