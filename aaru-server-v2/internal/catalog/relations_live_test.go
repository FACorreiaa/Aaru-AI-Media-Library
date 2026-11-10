package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"os"
	"sync"
	"testing"
	"time"
)

// GRAPH-001's "done when", against the live providers. Skipped unless AARU_LIVE=1: tests never
// reach a real service by default. TMDB joins only when TMDB_API_KEY is set; Wikidata and AniList
// need no key. Run: AARU_LIVE=1 go test -run TestLiveRelationGraphs -v ./internal/catalog

// tracedRelations records what one source answered, so a thin graph can be traced to its source.
type tracedRelations struct {
	RelationSource
	t  *testing.T
	mu *sync.Mutex
}

func (s tracedRelations) ChainOnly() bool { return chainOnly(s.RelationSource) }

func (s tracedRelations) Relations(ctx context.Context, n RelatedNode) (Relations, error) {
	started := time.Now()
	r, err := s.RelationSource.Relations(ctx, n)
	s.mu.Lock()
	defer s.mu.Unlock()
	if err != nil {
		s.t.Logf("    %-8s %-28s FAILED after %s: %v", s.RelationSourceName(), s.RelationKey(n), time.Since(started).Round(time.Millisecond), err)
		return r, err
	}
	s.t.Logf("    %-8s %-28s %d edges in %s", s.RelationSourceName(), s.RelationKey(n), len(r.Edges), time.Since(started).Round(time.Millisecond))
	return r, nil
}

func TestLiveRelationGraphs(t *testing.T) {
	if os.Getenv("AARU_LIVE") != "1" {
		t.Skip("live providers: set AARU_LIVE=1")
	}
	key := os.Getenv("TMDB_API_KEY")
	providers := NewProviders(key, config.DefaultProviderUserAgent, provider.NewHTTPTransport())
	var mu sync.Mutex
	var sources []RelationSource
	for _, p := range []any{providers.AniList, providers.TMDB, providers.Wikidata} {
		source, ok := p.(RelationSource)
		if !ok || (key == "" && source.RelationSourceName() == "tmdb") {
			continue
		}
		sources = append(sources, tracedRelations{RelationSource: source, t: t, mu: &mu})
	}
	if key == "" {
		t.Log("TMDB_API_KEY is not set: TMDB collections and Wikidata's poster enrichment are left out")
		if w, ok := providers.Wikidata.(*Wikidata); ok {
			w.Enrich = nil
		}
	}
	show := func(tmdb, anilist string, anime bool) RelatedNode {
		return RelatedNode{Type: core.MediaShow, IsAnime: anime, IDs: core.ExternalIDs{TMDB: tmdb, AniList: anilist}}
	}
	movie := func(tmdb string) RelatedNode {
		return RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: tmdb}}
	}
	cases := []struct {
		name   string
		centre RelatedNode
	}{
		{"The Fellowship of the Ring", movie("120")},
		{"Star Wars: A New Hope", movie("11")},
		{"Game of Thrones", show("1399", "", false)},
		{"Dragon Ball Z, no AniList id", show("12971", "", true)},
		{"Dragon Ball Z, mapped to AniList", show("12971", "813", true)},
		{"Attack on Titan", show("1429", "16498", true)},
		{"Frieren", show("209867", "154587", true)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			for _, s := range sources {
				s.(tracedRelations).t.Logf("") //nolint:forcetypeassert // built above
			}
			ctx, cancel := context.WithTimeout(context.Background(), RelationGraphDeadline)
			defer cancel()
			started := time.Now()
			graph := BuildRelationGraph(ctx, c.centre, sources, OrderRelease)
			touching := 0
			var centreKey string
			for _, n := range graph.Nodes {
				if n.Centre {
					centreKey = n.Key
				}
			}
			for _, e := range graph.Edges {
				if e.From == centreKey || e.To == centreKey {
					touching++
				}
			}
			t.Logf("  => %d nodes, %d edges, %d touching the centre, partial=%v, %s",
				len(graph.Nodes), len(graph.Edges), touching, graph.Partial, time.Since(started).Round(time.Millisecond))
			for _, n := range graph.Nodes {
				t.Logf("     rank %d lane %d chain=%-5v %-6s %q %s", n.Rank, n.Lane, n.MainChain, n.Type, n.Title, n.Key)
			}
			for _, e := range graph.Edges {
				t.Logf("     %s --%s--> %s", e.From, e.Relation, e.To)
			}
			if touching == 0 {
				t.Errorf("%s: nothing related to the centre, so the Related section would be hidden", c.name)
			}
		})
	}
}
