package agent

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"strings"
)

// relationLimit bounds the related titles the owl reads beside the main chain.
const relationLimit = 24

// relations is title_relations (GRAPH-004): the title's graph as the owl reads it, the main chain in
// order with the user's own status, where to start, and the titles hanging off it, each with a ref.
// Catalog data and the user's own library only.
func (t *ChatTools) relations(ctx context.Context, args map[string]any) (string, error) {
	if t.Catalog == nil || t.Catalog.Relations == nil {
		return "Relations are not available.", nil
	}
	title, err := t.resolve(ctx, args)
	if err != nil {
		return "", err
	}
	order := catalog.OrderRelease
	if o, _ := str(args, "order"); o == string(catalog.OrderStory) {
		order = catalog.OrderStory
	}
	graph, err := t.Catalog.Relations.Graph(ctx, title.ID, order)
	if err != nil {
		return "", err
	}
	marks, err := t.Catalog.Relations.Marks(ctx, t.User, graph)
	if err != nil {
		return "", err
	}
	status := map[string]core.LibraryStatus{}
	for key, m := range marks {
		status[key] = m.Status
	}
	return t.describeGraph(graph, status), nil
}

func (t *ChatTools) describeGraph(graph catalog.RelationGraph, status map[string]core.LibraryStatus) string {
	name := func(n catalog.GraphNode) string {
		ref := t.remember(core.MediaRef{Type: n.Type, IDs: n.IDs, Title: &n.Title, Year: n.Year})
		parts := []string{n.Title}
		meta := []string{}
		if n.Year != nil {
			meta = append(meta, fmt.Sprint(*n.Year))
		}
		kind := string(n.Type)
		if n.IsAnime {
			kind = "anime"
		}
		if n.Format != "" && n.Format != kind {
			kind += ", " + n.Format
		}
		meta = append(meta, kind)
		if s, ok := status[n.Key]; ok {
			meta = append(meta, "the user's status: "+string(s))
		}
		parts = append(parts, "("+strings.Join(meta, "; ")+")", "ref "+ref)
		return strings.Join(parts, " ")
	}
	var chain, others []catalog.GraphNode
	for _, n := range graph.Nodes {
		if n.MainChain {
			chain = append(chain, n)
		} else {
			others = append(others, n)
		}
	}
	lines := []string{fmt.Sprintf("Main chain in %s order:", graph.Order)}
	for i, n := range chain {
		line := fmt.Sprintf("%d. %s", i+1, name(n))
		if n.Centre {
			line += " ← the title asked about"
		}
		lines = append(lines, line)
	}
	if start := graph.StartHere(status); start != nil {
		for _, n := range chain {
			if n.Key == *start {
				lines = append(lines, "Start here: "+n.Title)
			}
		}
	} else if len(chain) > 0 {
		lines = append(lines, "The user has finished or dropped the whole chain.")
	}
	if graph.StoryOrderAvailable && graph.Order == catalog.OrderRelease {
		lines = append(lines, "A story order also exists (ask with order story).")
	}
	if len(others) > 0 {
		lines = append(lines, "Related titles:")
		for _, n := range others[:min(len(others), relationLimit)] {
			lines = append(lines, "- "+relationTo(graph, n)+": "+name(n))
		}
	}
	if graph.Partial {
		lines = append(lines, "Some sources did not answer in time; the graph may be missing titles.")
	}
	return strings.Join(lines, "\n")
}

// relationTo is how an off-chain title relates to what it hangs from, in words.
func relationTo(graph catalog.RelationGraph, n catalog.GraphNode) string {
	for _, e := range graph.Edges {
		if e.To != n.Key && e.From != n.Key {
			continue
		}
		outward := e.From == n.Key
		switch e.Relation {
		case core.RelationAdaptation:
			if outward {
				return "source of a title here"
			}
			return "adaptation"
		case core.RelationSideStory:
			if outward {
				return "main story"
			}
			return "side story"
		case core.RelationSequel:
			return "in another chain"
		default:
			return strings.ReplaceAll(string(e.Relation), "_", " ")
		}
	}
	return "related"
}
