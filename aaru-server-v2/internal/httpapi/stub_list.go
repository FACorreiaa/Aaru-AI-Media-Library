// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListLists(context.Context, api.ListListsRequestObject) (api.ListListsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateList(context.Context, api.CreateListRequestObject) (api.CreateListResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteList(context.Context, api.DeleteListRequestObject) (api.DeleteListResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetList(context.Context, api.GetListRequestObject) (api.GetListResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RenameList(context.Context, api.RenameListRequestObject) (api.RenameListResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) AddListItem(context.Context, api.AddListItemRequestObject) (api.AddListItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RemoveListItem(context.Context, api.RemoveListItemRequestObject) (api.RemoveListItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ReorderList(context.Context, api.ReorderListRequestObject) (api.ReorderListResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListShelves(context.Context, api.ListShelvesRequestObject) (api.ListShelvesResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateShelf(context.Context, api.CreateShelfRequestObject) (api.CreateShelfResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteShelf(context.Context, api.DeleteShelfRequestObject) (api.DeleteShelfResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UpdateShelf(context.Context, api.UpdateShelfRequestObject) (api.UpdateShelfResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListShelfItems(context.Context, api.ListShelfItemsRequestObject) (api.ListShelfItemsResponseObject, error) {
	return nil, errNotImplemented
}
