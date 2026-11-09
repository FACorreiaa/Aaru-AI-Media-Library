package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/safe"
	"cmp"
	"context"
	"net/http"
	"slices"
	"strconv"
	"time"

	"github.com/google/uuid"
)

// Related titles for the first-run flow (ONB-001): what each picked title's relation graph
// (GRAPH-001) holds around it. Catalog data joined by id, never a recommendation: nothing is read
// from other users and nothing is ranked by taste.

// Onboarding related limits.
const (
	// MaxOnboardingRelatedPicks is the most titles one call reads graphs for.
	MaxOnboardingRelatedPicks = 30
	// MaxOnboardingRelated is the most related titles one call answers.
	MaxOnboardingRelated = 30
	// OnboardingRelatedDeadline bounds every graph of one call together; graphs not cached yet are
	// cut short there, marked partial, and keep warming for the next call.
	OnboardingRelatedDeadline = 5 * time.Second
	onboardingRelatedFanOut   = 4
)

// onboardingRelations are the relations a related title may stand in to the pick.
var onboardingRelations = map[core.Relation]bool{
	core.RelationPrequel: true, core.RelationSequel: true, core.RelationSideStory: true,
	core.RelationSpinOff: true, core.RelationAdaptation: true, core.RelationSource: true,
}

// RelatedPick is one title related to a pick: Hit is the pick's Relation.
type RelatedPick struct {
	Hit         Hit
	Relation    core.Relation
	FromTitleID uuid.UUID
	FromTitle   string
}

// RelatedPicks are the titles related to a step's picks. Partial is true when a graph failed or
// ran out of time.
type RelatedPicks struct {
	Items   []RelatedPick
	Partial bool
}

// OnboardingRelated is the titles related to the picked titles, in the order the picks came, each
// pick's main chain first. Titles already in the user's library, and the picks themselves, are
// left out; each title comes once, at most MaxOnboardingRelated, shared across the picks.
func (s *RelationService) OnboardingRelated(ctx context.Context, userID uuid.UUID, titleIDs []uuid.UUID) (RelatedPicks, error) {
	if len(titleIDs) < 1 || len(titleIDs) > MaxOnboardingRelatedPicks {
		return RelatedPicks{}, apperr.Validation("titleIds", "Send between 1 and "+strconv.Itoa(MaxOnboardingRelatedPicks)+" titles.")
	}
	var picks []uuid.UUID
	for _, id := range titleIDs {
		if id != uuid.Nil && !slices.Contains(picks, id) {
			picks = append(picks, id)
		}
	}
	graphs := make([]*RelationGraph, len(picks))
	failed := make([]bool, len(picks))
	deadline := time.Now().Add(cmp.Or(s.OnboardingDeadline, OnboardingRelatedDeadline))
	g, gctx := safe.WithContext(ctx)
	g.SetLimit(onboardingRelatedFanOut)
	for i, id := range picks {
		g.Go(func() error {
			graph, err := s.graphBy(gctx, id, OrderStory, deadline)
			switch {
			case err == nil:
				graphs[i] = &graph
			case isNotFound(err):
				// A title Aaru does not hold has no graph; it is not a failure.
			case ctx.Err() != nil:
				return ctx.Err()
			default:
				s.log.WarnContext(ctx, "Onboarding relation graph failed", "title", id, "error", err.Error())
				failed[i] = true
			}
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return RelatedPicks{}, err
	}
	result := RelatedPicks{Items: []RelatedPick{}}
	// The picks themselves are never related titles, whichever graph they turn up in.
	picked := map[string]bool{}
	var all []GraphNode
	for i, graph := range graphs {
		if failed[i] || (graph != nil && graph.Partial) {
			result.Partial = true
		}
		if graph == nil {
			continue
		}
		for _, n := range graph.Nodes {
			if n.Centre {
				for _, k := range NodeKeys(n.RelatedNode) {
					picked[k] = true
				}
			}
		}
		all = append(all, graph.Nodes...)
	}
	marks, err := s.Marks(ctx, userID, RelationGraph{Nodes: all})
	if err != nil {
		return RelatedPicks{}, err
	}
	// Each title once, under the first pick it relates to.
	seen := map[string]bool{}
	perPick := make([][]RelatedPick, len(graphs))
	for i, graph := range graphs {
		if graph == nil {
			continue
		}
		for _, r := range relatedAround(*graph) {
			keys := NodeKeys(r.node.RelatedNode)
			if _, owned := marks[r.node.Key]; owned || anyKey(keys, picked) || anyKey(keys, seen) {
				continue
			}
			for _, k := range keys {
				seen[k] = true
			}
			perPick[i] = append(perPick[i], RelatedPick{
				Hit: r.node.hit(), Relation: r.relation, FromTitleID: picks[i], FromTitle: r.from,
			})
		}
	}
	result.Items = shareRelated(perPick, MaxOnboardingRelated)
	return result, nil
}

// shareRelated takes at most limit items, one from each pick in turn so one long franchise cannot
// fill the screen, and returns them grouped by pick in the picks' order, each pick's in its own.
func shareRelated(perPick [][]RelatedPick, limit int) []RelatedPick {
	taken := make([]int, len(perPick))
	for total, more := 0, true; more && total < limit; {
		more = false
		for i := range perPick {
			if total < limit && taken[i] < len(perPick[i]) {
				taken[i]++
				total++
				more = true
			}
		}
	}
	out := []RelatedPick{}
	for i, items := range perPick {
		out = append(out, items[:taken[i]]...)
	}
	return out
}

func isNotFound(err error) bool {
	e := apperr.From(err)
	return e != nil && e.Status == http.StatusNotFound
}

func anyKey(keys []string, set map[string]bool) bool {
	return slices.ContainsFunc(keys, func(k string) bool { return set[k] })
}

type relatedNode struct {
	node     GraphNode
	relation core.Relation
	from     string
}

// relatedAround is the graph's titles other than its centre, each with how it stands to the
// centre, when that is one onboarding keeps: the main chain first in its order, then the rest.
func relatedAround(graph RelationGraph) []relatedNode {
	var centre *GraphNode
	byKey := map[string]GraphNode{}
	for i, n := range graph.Nodes {
		byKey[n.Key] = n
		if n.Centre {
			centre = &graph.Nodes[i]
		}
	}
	if centre == nil {
		return nil
	}
	nodes := slices.Clone(graph.Nodes)
	slices.SortStableFunc(nodes, func(a, b GraphNode) int {
		if a.MainChain != b.MainChain {
			if a.MainChain {
				return -1
			}
			return 1
		}
		return cmp.Or(cmp.Compare(a.Rank, b.Rank), cmp.Compare(a.Lane, b.Lane))
	})
	var out []relatedNode
	for _, n := range nodes {
		if n.Centre || n.Title == "" {
			continue
		}
		relation, ok := relationToCentre(graph, *centre, n, byKey)
		if !ok || !onboardingRelations[relation] {
			continue
		}
		out = append(out, relatedNode{node: n, relation: relation, from: centre.Title})
	}
	return out
}

// relationToCentre is how n stands to the centre, read "n is the centre's relation". Edges are
// written forward, so an edge from n to the centre is read backward. A title on the main chain is
// a prequel or a sequel by its place; one further out takes its edge to the chain (else any edge).
func relationToCentre(graph RelationGraph, centre, n GraphNode, byKey map[string]GraphNode) (core.Relation, bool) {
	for _, e := range graph.Edges {
		switch {
		case e.From == centre.Key && e.To == n.Key:
			return e.Relation, true
		case e.From == n.Key && e.To == centre.Key:
			return inverseRelation(e.Relation)
		}
	}
	if n.MainChain {
		if n.Rank < centre.Rank {
			return core.RelationPrequel, true
		}
		return core.RelationSequel, true
	}
	var fallback *GraphEdge
	for i, e := range graph.Edges {
		if e.From != n.Key && e.To != n.Key {
			continue
		}
		other := e.From
		if other == n.Key {
			other = e.To
		}
		if byKey[other].MainChain {
			fallback = &graph.Edges[i]
			break
		}
		if fallback == nil {
			fallback = &graph.Edges[i]
		}
	}
	if fallback == nil {
		return "", false
	}
	if fallback.To == n.Key {
		return fallback.Relation, true
	}
	return inverseRelation(fallback.Relation)
}

// inverseRelation is how A stands to B when B is A's relation. A spin-off's original has no word of
// its own, so it has none.
func inverseRelation(r core.Relation) (core.Relation, bool) {
	switch r {
	case core.RelationSequel:
		return core.RelationPrequel, true
	case core.RelationPrequel:
		return core.RelationSequel, true
	case core.RelationAdaptation:
		return core.RelationSource, true
	case core.RelationSource:
		return core.RelationAdaptation, true
	case core.RelationSideStory:
		return core.RelationParent, true
	case core.RelationParent:
		return core.RelationSideStory, true
	case core.RelationSpinOff:
		return "", false
	}
	return r, true
}

// hit is the node as a catalog card.
func (n GraphNode) hit() Hit {
	year := n.Year
	if year == nil {
		year = ParseYear(n.ReleaseDate)
	}
	return Hit{
		Type: n.Type, Title: n.Title, Year: year, ReleaseDate: n.ReleaseDate, PosterURL: n.PosterURL,
		IsAnime: n.IsAnime, IDs: n.IDs,
	}
}
