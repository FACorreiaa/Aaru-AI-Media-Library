package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/library"
	"context"

	"github.com/google/uuid"
)

// List and shelf routes (API/ListHandlers.swift). A malformed list or shelf id reads as uuid.Nil,
// which none has: "No such list." / "No such shelf.".

// ListLists is GET /v1/lists.
func (s *Server) ListLists(ctx context.Context, _ api.ListListsRequestObject) (api.ListListsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	lists, err := s.Lists.All(ctx, user)
	if err != nil {
		return nil, err
	}
	items := make([]api.ListSummary, len(lists))
	for i, l := range lists {
		items[i] = api.ListSummary{
			Id: apiid.From(l.ID), Name: l.Name, ItemCount: len(l.TitleIDs),
			CreatedAt: apitime.From(l.CreatedAt), UpdatedAt: apitime.From(l.UpdatedAt),
		}
	}
	return api.ListLists200JSONResponse(api.ListList{Items: items}), nil
}

// CreateList is POST /v1/lists.
func (s *Server) CreateList(ctx context.Context, req api.CreateListRequestObject) (api.CreateListResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Lists.Create(ctx, req.Body.Name, user)
	if err != nil {
		return nil, err
	}
	return api.CreateList200JSONResponse(ListDetailDTO(detail)), nil
}

// GetList is GET /v1/lists/{id}.
func (s *Server) GetList(ctx context.Context, req api.GetListRequestObject) (api.GetListResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Lists.Detail(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.GetList200JSONResponse(ListDetailDTO(detail)), nil
}

// RenameList is PATCH /v1/lists/{id}.
func (s *Server) RenameList(ctx context.Context, req api.RenameListRequestObject) (api.RenameListResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Lists.Rename(ctx, req.Id.ID(), req.Body.Name, user)
	if err != nil {
		return nil, err
	}
	return api.RenameList200JSONResponse(ListDetailDTO(detail)), nil
}

// DeleteList is DELETE /v1/lists/{id}.
func (s *Server) DeleteList(ctx context.Context, req api.DeleteListRequestObject) (api.DeleteListResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Lists.Delete(ctx, req.Id.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteList204Response{}, nil
}

// AddListItem is POST /v1/lists/{id}/items.
func (s *Server) AddListItem(ctx context.Context, req api.AddListItemRequestObject) (api.AddListItemResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Lists.Add(ctx, MediaRefFromAPI(req.Body.MediaRef), req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.AddListItem200JSONResponse(ListDetailDTO(detail)), nil
}

// RemoveListItem is DELETE /v1/lists/{id}/items/{titleId}.
func (s *Server) RemoveListItem(ctx context.Context, req api.RemoveListItemRequestObject) (api.RemoveListItemResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.TitleId.ID() == uuid.Nil {
		return nil, apperr.NotFound()
	}
	detail, err := s.Lists.Remove(ctx, req.TitleId.ID(), req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.RemoveListItem200JSONResponse(ListDetailDTO(detail)), nil
}

// ReorderList is PUT /v1/lists/{id}/order.
func (s *Server) ReorderList(ctx context.Context, req api.ReorderListRequestObject) (api.ReorderListResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	order := apiid.IDs(req.Body.TitleIds)
	for _, id := range order {
		if id == uuid.Nil {
			return nil, apperr.BadRequest("That title id is not valid.")
		}
	}
	detail, err := s.Lists.Reorder(ctx, req.Id.ID(), order, user)
	if err != nil {
		return nil, err
	}
	return api.ReorderList200JSONResponse(ListDetailDTO(detail)), nil
}

// MARK: Shelves

// ListShelves is GET /v1/shelves.
func (s *Server) ListShelves(ctx context.Context, _ api.ListShelvesRequestObject) (api.ListShelvesResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	shelves, err := s.Shelves.All(ctx, user)
	if err != nil {
		return nil, err
	}
	items := make([]api.Shelf, len(shelves))
	for i, sh := range shelves {
		items[i] = ShelfDTO(sh)
	}
	return api.ListShelves200JSONResponse(api.ShelfList{Items: items}), nil
}

// CreateShelf is POST /v1/shelves.
func (s *Server) CreateShelf(ctx context.Context, req api.CreateShelfRequestObject) (api.CreateShelfResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	pinned := req.Body.IsPinned != nil && *req.Body.IsPinned
	shelf, err := s.Shelves.Create(ctx, req.Body.Name, ShelfFilterFromAPI(req.Body.Filter), pinned, user)
	if err != nil {
		return nil, err
	}
	return api.CreateShelf200JSONResponse(ShelfDTO(shelf)), nil
}

// UpdateShelf is PATCH /v1/shelves/{id}.
func (s *Server) UpdateShelf(ctx context.Context, req api.UpdateShelfRequestObject) (api.UpdateShelfResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var filter *library.Filter
	if req.Body.Filter != nil {
		f := ShelfFilterFromAPI(*req.Body.Filter)
		filter = &f
	}
	shelf, err := s.Shelves.Update(ctx, req.Id.ID(), user, req.Body.Name, filter, req.Body.IsPinned)
	if err != nil {
		return nil, err
	}
	return api.UpdateShelf200JSONResponse(ShelfDTO(shelf)), nil
}

// DeleteShelf is DELETE /v1/shelves/{id}.
func (s *Server) DeleteShelf(ctx context.Context, req api.DeleteShelfRequestObject) (api.DeleteShelfResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Shelves.Delete(ctx, req.Id.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteShelf204Response{}, nil
}

// ListShelfItems is GET /v1/shelves/{id}/items: the shelf's query, as GET /v1/library/items.
func (s *Server) ListShelfItems(ctx context.Context, req api.ListShelfItemsRequestObject) (api.ListShelfItemsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	entries, next, err := s.Shelves.Items(ctx, req.Id.ID(), user, req.Params.Cursor, intOr(req.Params.Limit, 50))
	if err != nil {
		return nil, err
	}
	return api.ListShelfItems200JSONResponse(api.LibraryPage{
		Items: LibraryEntriesDTO(entries), Page: api.PageInfo{NextCursor: next},
	}), nil
}
