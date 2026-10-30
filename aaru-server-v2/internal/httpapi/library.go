package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"

	"github.com/google/uuid"
)

// Library routes (API/LibraryHandlers.swift): items, progress, sync and the action journal.
// A malformed item id reads as uuid.Nil, which no item has: the route's 404.

// ListLibraryItems is GET /v1/library/items.
func (s *Server) ListLibraryItems(ctx context.Context, req api.ListLibraryItemsRequestObject) (api.ListLibraryItemsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	p := req.Params
	filter, err := libraryFilter(p.Type, p.Anime, p.Status, p.Owned, p.List)
	if err != nil {
		return nil, err
	}
	entries, next, err := s.Library.List(ctx, user, filter, p.Cursor, intOr(p.Limit, 50))
	if err != nil {
		return nil, err
	}
	return api.ListLibraryItems200JSONResponse(api.LibraryPage{
		Items: LibraryEntriesDTO(entries), Page: api.PageInfo{NextCursor: next},
	}), nil
}

func libraryFilter(typ *api.MediaType, anime *bool, status *api.LibraryStatus, owned *bool, list *apiid.UUID) (library.Filter, error) {
	var f library.Filter
	if typ != nil {
		t := core.MediaType(*typ)
		f.Type = &t
	}
	f.IsAnime = anime
	if status != nil {
		st := core.LibraryStatus(*status)
		f.Status = &st
	}
	f.IsOwned = owned
	if list != nil {
		id := list.ID()
		if id == uuid.Nil {
			return library.Filter{}, apperr.BadRequest("That list id is not valid.")
		}
		f = f.WithList(&id)
	}
	return f, nil
}

func intOr(p *int, def int) int {
	if p == nil {
		return def
	}
	return *p
}

// AddLibraryItem is POST /v1/library/items.
func (s *Server) AddLibraryItem(ctx context.Context, req api.AddLibraryItemRequestObject) (api.AddLibraryItemResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var status *core.LibraryStatus
	if req.Body.Status != nil {
		st := core.LibraryStatus(*req.Body.Status)
		status = &st
	}
	entry, err := s.Library.Add(ctx, MediaRefFromAPI(req.Body.MediaRef), status, user, library.UserCaller)
	if err != nil {
		return nil, err
	}
	return api.AddLibraryItem200JSONResponse(LibraryEntryDTO(entry)), nil
}

// GetLibraryItem is GET /v1/library/items/{id}.
func (s *Server) GetLibraryItem(ctx context.Context, req api.GetLibraryItemRequestObject) (api.GetLibraryItemResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	entry, err := s.Library.Entry(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	dto, err := LibraryEntryWithWatchedDTO(ctx, s.Library.Store, entry)
	if err != nil {
		return nil, err
	}
	return api.GetLibraryItem200JSONResponse(dto), nil
}

// UpdateLibraryItem is PATCH /v1/library/items/{id}. Aaru-Action names the action, when one was made.
func (s *Server) UpdateLibraryItem(ctx context.Context, req api.UpdateLibraryItemRequestObject) (api.UpdateLibraryItemResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	write, err := s.Library.PatchWrite(ctx, req.Id.ID(), user, ItemPatchFromAPI(*req.Body), library.UserCaller)
	if err != nil {
		return nil, err
	}
	resp := api.UpdateLibraryItem200JSONResponse{Body: LibraryEntryDTO(write.Entry)}
	if write.Action != nil {
		resp.Headers.AaruAction = apiid.Ptr(write.Action.ID)
	}
	return resp, nil
}

// DeleteLibraryItem is DELETE /v1/library/items/{id}.
func (s *Server) DeleteLibraryItem(ctx context.Context, req api.DeleteLibraryItemRequestObject) (api.DeleteLibraryItemResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Library.Delete(ctx, req.Id.ID(), user, library.UserCaller); err != nil {
		return nil, err
	}
	return api.DeleteLibraryItem204Response{}, nil
}

// SetEpisodeWatched is PUT /v1/library/items/{id}/episodes/{season}/{episode}.
func (s *Server) SetEpisodeWatched(ctx context.Context, req api.SetEpisodeWatchedRequestObject) (api.SetEpisodeWatchedResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	key, err := core.NewEpisodeKey(req.Season, req.Episode)
	if err != nil {
		return nil, err
	}
	write, err := s.Library.SetEpisode(ctx, req.Id.ID(), user, key, req.Body.Watched, library.UserCaller)
	if err != nil {
		return nil, err
	}
	dto, err := LibraryEntryWithWatchedDTO(ctx, s.Library.Store, write.Entry)
	if err != nil {
		return nil, err
	}
	return api.SetEpisodeWatched200JSONResponse{
		Body: dto, Headers: api.SetEpisodeWatched200ResponseHeaders{AaruAction: apiid.Ptr(write.Action.ID)},
	}, nil
}

// MarkSeasonWatched is POST /v1/library/items/{id}/seasons/{season}/watched.
func (s *Server) MarkSeasonWatched(ctx context.Context, req api.MarkSeasonWatchedRequestObject) (api.MarkSeasonWatchedResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	write, err := s.Library.MarkSeasonWatched(ctx, req.Id.ID(), user, req.Season, library.UserCaller)
	if err != nil {
		return nil, err
	}
	dto, err := LibraryEntryWithWatchedDTO(ctx, s.Library.Store, write.Entry)
	if err != nil {
		return nil, err
	}
	return api.MarkSeasonWatched200JSONResponse{
		Body: dto, Headers: api.MarkSeasonWatched200ResponseHeaders{AaruAction: apiid.Ptr(write.Action.ID)},
	}, nil
}

// MarkShowWatched is POST /v1/library/items/{id}/watched (PROG-005).
func (s *Server) MarkShowWatched(ctx context.Context, req api.MarkShowWatchedRequestObject) (api.MarkShowWatchedResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	result, err := s.Library.MarkShowWatched(ctx, req.Id.ID(), user, library.UserCaller)
	if err != nil {
		return nil, err
	}
	dto, err := LibraryEntryWithWatchedDTO(ctx, s.Library.Store, result.Entry)
	if err != nil {
		return nil, err
	}
	out := api.ShowWatched{Entry: dto, Episodes: result.Episodes}
	if result.Action != nil {
		a := ActionDTO(*result.Action)
		out.Action = &a
	}
	return api.MarkShowWatched200JSONResponse(out), nil
}

// SyncLibrary is GET /v1/library/sync (LIB-004).
func (s *Server) SyncLibrary(ctx context.Context, req api.SyncLibraryRequestObject) (api.SyncLibraryResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	result, err := s.Library.Sync(ctx, user, req.Params.Since)
	if err != nil {
		return nil, err
	}
	return api.SyncLibrary200JSONResponse(api.LibrarySync{
		Items: LibraryEntriesDTO(result.Entries), Deleted: apiid.Slice(result.Deleted), Token: result.Token,
	}), nil
}

// ListActions is GET /v1/actions.
func (s *Server) ListActions(ctx context.Context, req api.ListActionsRequestObject) (api.ListActionsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	actions, err := s.Library.Actions(ctx, user, intOr(req.Params.Limit, 20))
	if err != nil {
		return nil, err
	}
	items := make([]api.Action, len(actions))
	for i, a := range actions {
		items[i] = ActionDTO(a)
	}
	return api.ListActions200JSONResponse(api.ActionList{Items: items}), nil
}

// UndoAction is POST /v1/actions/{id}/undo.
func (s *Server) UndoAction(ctx context.Context, req api.UndoActionRequestObject) (api.UndoActionResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	undo, err := s.Library.Undo(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.UndoAction200JSONResponse(ActionDTO(undo)), nil
}
