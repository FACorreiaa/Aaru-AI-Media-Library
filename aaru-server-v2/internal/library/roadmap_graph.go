package library

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"slices"
	"strings"

	"github.com/google/uuid"
)

// roadmapEntry is one member in roadmap order.
type roadmapEntry struct {
	member   ListMember
	optional bool
	pair     int
	step     int
}

// entries are the members in roadmap order: each step's titles in list order, then any title no
// step names, which was added by hand. A plain list is its members in order.
func (d ListDetail) entries() []roadmapEntry {
	position := map[uuid.UUID]int{}
	for i, m := range d.Members {
		position[m.Title.ID] = i
	}
	var out []roadmapEntry
	placed := map[uuid.UUID]bool{}
	if d.Roadmap != nil {
		for s, step := range d.Roadmap.Steps {
			var inStep []roadmapEntry
			for _, item := range step.Items {
				i, ok := position[item.TitleID]
				if !ok || placed[item.TitleID] {
					continue
				}
				placed[item.TitleID] = true
				inStep = append(inStep, roadmapEntry{member: d.Members[i], optional: item.Optional, pair: item.Pair, step: s})
			}
			slices.SortStableFunc(inStep, func(a, b roadmapEntry) int {
				return position[a.member.Title.ID] - position[b.member.Title.ID]
			})
			out = append(out, inStep...)
		}
	}
	for _, m := range d.Members {
		if !placed[m.Title.ID] {
			out = append(out, roadmapEntry{member: m, step: -1})
		}
	}
	return out
}

// Graph is the list drawn as a relation graph (GRAPH-004), in the shape a title's graph has, so the
// clients draw it the same way. The roadmap reads left to right, a column per title; titles read
// side by side share a column, one under the other; an optional title hangs under the title before
// it, off the main chain. "Start here" is then the first main-chain title not finished or dropped.
func (d ListDetail) Graph() catalog.RelationGraph {
	graph := catalog.RelationGraph{Order: catalog.OrderRelease, Nodes: []catalog.GraphNode{}, Edges: []catalog.GraphEdge{}}
	rank, lane := -1, 0
	lanes := map[int]int{}
	prevPair, prevStep := 0, -2
	var columns [][]catalog.GraphNode
	for _, e := range d.entries() {
		t := e.member.Title
		node := catalog.GraphNode{
			RelatedNode: catalog.RelatedNode{
				Type: t.Type, IsAnime: t.IsAnime, IDs: t.IDs, Title: t.Title, Year: t.Year, PosterURL: t.PosterURL,
			},
			Key: strings.ToUpper(t.ID.String()), MainChain: !e.optional,
		}
		switch {
		case e.optional && rank >= 0:
			lanes[rank]++
			lane = lanes[rank]
		case e.pair > 0 && e.pair == prevPair && e.step == prevStep && rank >= 0:
			lanes[rank]++
			lane = lanes[rank]
		default:
			rank++
			lane = 0
			lanes[rank] = 0
			columns = append(columns, nil)
		}
		if !e.optional {
			prevPair, prevStep = e.pair, e.step
		}
		node.Rank, node.Lane = rank, lane
		columns[rank] = append(columns[rank], node)
		graph.Nodes = append(graph.Nodes, node)
	}
	for r, column := range columns {
		var chain []catalog.GraphNode
		for _, n := range column {
			if n.MainChain {
				chain = append(chain, n)
			}
		}
		for _, n := range column {
			if !n.MainChain && len(chain) > 0 {
				graph.Edges = append(graph.Edges, catalog.GraphEdge{From: chain[0].Key, To: n.Key, Relation: core.RelationOther})
			}
		}
		if r+1 >= len(columns) {
			continue
		}
		for _, from := range chain {
			for _, to := range columns[r+1] {
				if to.MainChain {
					graph.Edges = append(graph.Edges, catalog.GraphEdge{From: from.Key, To: to.Key, Relation: core.RelationSequel})
				}
			}
		}
	}
	slices.SortStableFunc(graph.Nodes, func(a, b catalog.GraphNode) int {
		if a.Rank != b.Rank {
			return a.Rank - b.Rank
		}
		return a.Lane - b.Lane
	})
	return graph
}

// Marks are the caller's items among the list's titles, by graph key.
func (d ListDetail) Marks() map[string]catalog.RelationMark {
	marks := map[string]catalog.RelationMark{}
	for _, m := range d.Members {
		if m.Entry != nil {
			marks[strings.ToUpper(m.Title.ID.String())] = catalog.RelationMark{
				LibraryItemID: m.Entry.Item.ID, Status: m.Entry.Item.Status,
			}
		}
	}
	return marks
}
