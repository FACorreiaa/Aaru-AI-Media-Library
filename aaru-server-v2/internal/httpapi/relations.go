package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
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

// PlanRelationChain is POST /v1/titles/{id}/relations/chain (GRAPH-003): the graph's main chain, in
// its order, as a capture the person reviews, by exact ids. The list is named for the title.
func (s *Server) PlanRelationChain(ctx context.Context, req api.PlanRelationChainRequestObject) (api.PlanRelationChainResponseObject, error) {
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	order := catalog.OrderRelease
	if req.Params.Order != nil && *req.Params.Order == api.RelationOrderStory {
		order = catalog.OrderStory
	}
	graph, err := s.Catalog.Relations.Graph(ctx, req.Id.ID(), order)
	if err != nil {
		return nil, err
	}
	titles, listName := chainTitles(graph)
	if len(titles) < 2 {
		return nil, apperr.Validation("id", "This title has no chain to add.")
	}
	job, err := s.Imports.CreateCapture(ctx, userID, imports.CaptureRequest{Titles: titles, ListName: listName})
	if err != nil {
		return nil, err
	}
	return api.PlanRelationChain202JSONResponse(ImportJobDTO(job)), nil
}

// chainTitles are the main chain's titles in the graph's order, by their ids, and the list they
// join: "<title> in release order" or "… in story order".
func chainTitles(graph catalog.RelationGraph) ([]capture.Title, string) {
	var titles []capture.Title
	centre := ""
	for _, n := range graph.Nodes {
		if n.Centre {
			centre = n.Title
		}
		if !n.MainChain || len(titles) == capture.MaxTitles {
			continue
		}
		title := n.Title
		if title == "" {
			continue
		}
		titles = append(titles, capture.Title{Type: n.Type, Title: title, Year: n.Year, IDs: n.IDs})
	}
	name := []rune(centre + " in " + string(graph.Order) + " order")
	return titles, string(name[:min(len(name), capture.MaxListName)])
}
