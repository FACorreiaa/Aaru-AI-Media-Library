package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"

	"github.com/google/uuid"
)

// GetTitleRelations is GET /v1/titles/{id}/relations (GRAPH-001): the title's relation graph,
// marked with the caller's own library. Reading it writes nothing.
func (s *Server) GetTitleRelations(ctx context.Context, req api.GetTitleRelationsRequestObject) (api.GetTitleRelationsResponseObject, error) {
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	order := catalog.OrderRelease
	if req.Params.Order != nil {
		switch *req.Params.Order {
		case api.RelationOrderRelease:
		case api.RelationOrderStory:
			order = catalog.OrderStory
		default:
			return nil, apperr.Validation("order", "Unknown order.")
		}
	}
	graph, err := s.Catalog.Relations.Graph(ctx, req.Id.ID(), order)
	if err != nil {
		return nil, err
	}
	marks, err := s.Catalog.Relations.Marks(ctx, userID, graph)
	if err != nil {
		return nil, err
	}
	return api.GetTitleRelations200JSONResponse(RelationGraphDTO(graph, marks)), nil
}

// RelationGraphDTO is the graph's wire shape, with "Start here" read from the caller's marks.
func RelationGraphDTO(graph catalog.RelationGraph, marks map[string]catalog.RelationMark) api.RelationGraph {
	status := map[string]core.LibraryStatus{}
	for key, m := range marks {
		status[key] = m.Status
	}
	out := api.RelationGraph{
		Nodes: make([]api.RelationNode, 0, len(graph.Nodes)), Edges: make([]api.RelationEdge, 0, len(graph.Edges)),
		Order: api.RelationOrder(graph.Order), StoryOrderAvailable: graph.StoryOrderAvailable, Partial: graph.Partial,
		StartHere: graph.StartHere(status),
	}
	for _, n := range graph.Nodes {
		ids := ExternalIDsDTO(n.IDs)
		title := n.Title
		node := api.RelationNode{
			Key: n.Key, Rank: n.Rank, Lane: n.Lane, MainChain: n.MainChain, Centre: n.Centre,
			Ref:       api.MediaRef{Type: api.MediaType(n.Type), Ids: &ids, Title: &title, Year: n.Year},
			PosterUrl: n.PosterURL, ReleaseDate: n.ReleaseDate,
		}
		if n.IsAnime {
			anime := true
			node.IsAnime = &anime
		}
		if n.Format != "" {
			format := n.Format
			node.Format = &format
		}
		if m, ok := marks[n.Key]; ok {
			item := apiid.From(m.LibraryItemID)
			st := api.LibraryStatus(m.Status)
			node.LibraryItemId, node.Status = &item, &st
		}
		out.Nodes = append(out.Nodes, node)
	}
	for _, e := range graph.Edges {
		out.Edges = append(out.Edges, api.RelationEdge{From: e.From, To: e.To, Relation: api.Relation(e.Relation)})
	}
	return out
}
