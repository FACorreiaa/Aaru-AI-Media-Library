package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"os"
	"testing"
	"time"
)

// GRAPH-005 against the live providers. Skipped unless AARU_LIVE=1: tests never reach a real
// service by default. TMDB joins only when TMDB_API_KEY is set; AniList, Open Library and
// MusicBrainz need no key. Run: AARU_LIVE=1 go test -run TestLiveCredits -v ./internal/catalog
func TestLiveCredits(t *testing.T) {
	if os.Getenv("AARU_LIVE") != "1" {
		t.Skip("live providers: set AARU_LIVE=1")
	}
	key := os.Getenv("TMDB_API_KEY")
	providers := NewProviders(key, config.DefaultProviderUserAgent, provider.NewHTTPTransport())
	year := func(y int) *int { return &y }
	cases := []struct {
		name   string
		source any
		node   RelatedNode
		tmdb   bool
	}{
		{"Arrival (film)", providers.TMDB, RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "329865"}, Year: year(2016)}, true},
		{"Breaking Bad (show)", providers.TMDB, RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "1396"}, Year: year(2008)}, true},
		{"Attack on Titan (anime)", providers.AniList, RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{AniList: "16498"}, Year: year(2013)}, false},
		{"Berserk (manga)", providers.AniList, RelatedNode{Type: core.MediaManga, IDs: core.ExternalIDs{AniList: "30002"}, Year: year(1989)}, false},
		{"Dune (book)", providers.OpenLibrary, RelatedNode{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: "OL893414W"}, Year: year(1965)}, false},
		{"OK Computer (album)", providers.Music, RelatedNode{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: "b1392450-e666-3926-a536-22c65f834433"}, Year: year(1997)}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if c.tmdb && key == "" {
				t.Skip("no TMDB_API_KEY")
			}
			source, ok := c.source.(CreditSource)
			if !ok {
				t.Fatal("not a credit source")
			}
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			people, err := source.People(ctx, c.node)
			if err != nil || len(people) == 0 {
				t.Fatalf("people: %v %v", people, err)
			}
			// Everyone the title credits: who made it, then a film's or show's first two billed.
			for _, person := range people {
				works, err := source.Works(ctx, person)
				if err != nil || len(works) == 0 {
					t.Fatalf("works of %s: %d %v", person.Name, len(works), err)
				}
				candidates := make([]core.TreeCandidate, 0, len(works))
				kept := make([]CreditedWork, 0, len(works))
				rootDate := treeDate(c.node)
				ranked := false
				for _, w := range works {
					if NodeKeys(w.RelatedNode)[0] == NodeKeys(c.node)[0] {
						rootDate = treeDate(w.RelatedNode)
						continue
					}
					kept = append(kept, w)
					candidates = append(candidates, core.TreeCandidate{Date: treeDate(w.RelatedNode), Score: w.Score})
					ranked = ranked || w.Score > 0
				}
				t.Logf("%s %s (%s): %d works, root dated %s", person.Kind, person.Name, person.ID, len(works), rootDate)
				for _, choice := range core.PickTreeBranch(candidates, rootDate, ranked) {
					w := kept[choice.Index]
					t.Logf("    %-10s %-10s %7d  %s", choice.Pick, treeDate(w.RelatedNode), w.Score, w.Title)
				}
			}
		})
	}
}
