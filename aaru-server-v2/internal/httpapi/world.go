package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"cmp"
	"context"
	"slices"

	"github.com/google/uuid"
)

// Worlds (GRAPH-007): one story universe across every kind, marked with the caller's own library.
// Every read is from the database; a World that is not built yet is queued and reads as building.

// GetTitleWorld is GET /v1/titles/{id}/world.
func (s *Server) GetTitleWorld(ctx context.Context, req api.GetTitleWorldRequestObject) (api.GetTitleWorldResponseObject, error) {
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	world, state, err := s.Catalog.Worlds.For(ctx, req.Id.ID())
	if err != nil {
		return nil, err
	}
	if state != catalog.WorldReady {
		return api.GetTitleWorld200JSONResponse(api.World{
			State: api.WorldState(state), Kinds: []api.WorldLaneKind{}, Lanes: []api.WorldLane{}, Links: []api.RelationEdge{},
		}), nil
	}
	marks, err := s.Catalog.Worlds.Marks(ctx, userID, world.World)
	if err != nil {
		return nil, err
	}
	return api.GetTitleWorld200JSONResponse(WorldDTO(world, marks)), nil
}

// WorldDTO is a built World's wire shape, with the caller's marks, counts and next steps.
func WorldDTO(world catalog.StoredWorld, marks map[string]catalog.RelationMark) api.World {
	progress := world.Progress(worldStatus(marks))
	id, name := apiid.From(world.ID), world.Name
	out := api.World{
		State: api.WorldStateReady, Id: &id, Name: &name, Total: progress.Total, Finished: progress.Finished,
		Kinds: []api.WorldLaneKind{}, Lanes: []api.WorldLane{}, Links: make([]api.RelationEdge, 0, len(world.Links)),
		StartHere: progress.StartHere, Truncated: world.Truncated, Partial: world.Partial,
	}
	if world.Anchor != "" {
		anchor := world.Anchor
		out.Anchor = &anchor
	}
	for _, t := range world.Titles {
		kind := api.WorldLaneKind(t.Lane)
		if len(out.Lanes) == 0 || out.Lanes[len(out.Lanes)-1].Kind != kind {
			out.Kinds = append(out.Kinds, kind)
			out.Lanes = append(out.Lanes, api.WorldLane{Kind: kind, Titles: []api.WorldTitle{}})
		}
		title := api.WorldTitle{
			Key: t.Key, Ref: worldRef(t), PosterUrl: t.PosterURL, ReleaseDate: t.ReleaseDate, Side: t.Side,
			Next: progress.Next[t.Lane] == t.Key,
		}
		if t.Format != "" {
			format := t.Format
			title.Format = &format
		}
		if m, ok := marks[t.Key]; ok {
			item := apiid.From(m.LibraryItemID)
			st := api.LibraryStatus(m.Status)
			title.LibraryItemId, title.Status = &item, &st
		}
		lane := &out.Lanes[len(out.Lanes)-1]
		lane.Titles = append(lane.Titles, title)
	}
	for _, e := range world.Links {
		out.Links = append(out.Links, api.RelationEdge{From: e.From, To: e.To, Relation: api.Relation(e.Relation)})
	}
	return out
}

func worldRef(t catalog.WorldTitle) api.MediaRef {
	ids := ExternalIDsDTO(t.IDs)
	name := t.Title
	return api.MediaRef{Type: api.MediaType(t.Type), Ids: &ids, Title: &name, Year: t.Year}
}

func worldStatus(marks map[string]catalog.RelationMark) map[string]core.LibraryStatus {
	status := make(map[string]core.LibraryStatus, len(marks))
	for key, m := range marks {
		status[key] = m.Status
	}
	return status
}

// ListMyWorlds is GET /v1/me/worlds: the caller's Worlds, those with something left first and the
// furthest along leading, then the finished ones.
func (s *Server) ListMyWorlds(ctx context.Context, _ api.ListMyWorldsRequestObject) (api.ListMyWorldsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	worlds, err := s.Catalog.Worlds.Mine(ctx, userID)
	if err != nil {
		return nil, err
	}
	all := make([]catalog.World, len(worlds))
	for i, w := range worlds {
		all[i] = w.World
	}
	marks, err := s.Catalog.Worlds.Marks(ctx, userID, all...)
	if err != nil {
		return nil, err
	}
	status := worldStatus(marks)
	out := make([]api.WorldSummary, 0, len(worlds))
	for _, w := range worlds {
		out = append(out, WorldSummaryDTO(w, w.Progress(status)))
	}
	slices.SortStableFunc(out, func(a, b api.WorldSummary) int {
		doneA, doneB := a.Finished >= a.Total, b.Finished >= b.Total
		if doneA != doneB {
			if doneA {
				return 1
			}
			return -1
		}
		// The larger share finished first: a/b compared without dividing.
		return cmp.Or(cmp.Compare(b.Finished*a.Total, a.Finished*b.Total), cmp.Compare(a.Name, b.Name))
	})
	return api.ListMyWorlds200JSONResponse(api.MyWorlds{Worlds: out}), nil
}

// WorldSummaryDTO is one row of the caller's Worlds.
func WorldSummaryDTO(world catalog.StoredWorld, progress catalog.WorldProgress) api.WorldSummary {
	out := api.WorldSummary{
		Id: apiid.From(world.ID), Name: world.Name, Total: progress.Total, Finished: progress.Finished,
		Kinds: []api.WorldLaneKind{}, TitleId: apiid.From(world.TitleID),
	}
	for _, lane := range world.Kinds() {
		out.Kinds = append(out.Kinds, api.WorldLaneKind(lane))
	}
	if world.Truncated {
		truncated := true
		out.Truncated = &truncated
	}
	if len(world.Titles) > 0 {
		out.PosterUrl = world.Titles[0].PosterURL
	}
	if progress.StartHere != nil {
		for _, t := range world.Titles {
			if t.Key == *progress.StartHere {
				ref := worldRef(t)
				out.StartHere = &ref
				if t.PosterURL != nil {
					out.PosterUrl = t.PosterURL
				}
				break
			}
		}
	}
	return out
}

// PlanWorldRest is POST /v1/titles/{id}/world/plan: the World's titles the caller does not have,
// in the World's order, as a capture they review, by exact ids. Nothing is written until they
// approve it; each lands as Plan to watch or read.
func (s *Server) PlanWorldRest(ctx context.Context, req api.PlanWorldRestRequestObject) (api.PlanWorldRestResponseObject, error) {
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	world, state, err := s.Catalog.Worlds.For(ctx, req.Id.ID())
	if err != nil {
		return nil, err
	}
	if state != catalog.WorldReady {
		return nil, apperr.Validation("id", "This title has no World to add.")
	}
	marks, err := s.Catalog.Worlds.Marks(ctx, userID, world.World)
	if err != nil {
		return nil, err
	}
	titles := worldRest(world.World, marks)
	if len(titles) == 0 {
		return nil, apperr.Validation("id", "Every title of this World is in your library.")
	}
	job, err := s.Imports.CreateCapture(ctx, userID, imports.CaptureRequest{Titles: titles})
	if err != nil {
		return nil, err
	}
	return api.PlanWorldRest202JSONResponse(ImportJobDTO(job)), nil
}

// worldRest are the World's titles with no library item, in its order, up to a capture's size.
func worldRest(world catalog.World, marks map[string]catalog.RelationMark) []capture.Title {
	var titles []capture.Title
	for _, t := range world.Titles {
		if _, has := marks[t.Key]; has || t.Title == "" {
			continue
		}
		titles = append(titles, capture.Title{Type: t.Type, Title: t.Title, Year: t.Year, IDs: t.IDs})
		if len(titles) == capture.MaxTitles {
			break
		}
	}
	return titles
}
