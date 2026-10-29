// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListActions(context.Context, api.ListActionsRequestObject) (api.ListActionsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UndoAction(context.Context, api.UndoActionRequestObject) (api.UndoActionResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListLibraryItems(context.Context, api.ListLibraryItemsRequestObject) (api.ListLibraryItemsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) AddLibraryItem(context.Context, api.AddLibraryItemRequestObject) (api.AddLibraryItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DeleteLibraryItem(context.Context, api.DeleteLibraryItemRequestObject) (api.DeleteLibraryItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetLibraryItem(context.Context, api.GetLibraryItemRequestObject) (api.GetLibraryItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UpdateLibraryItem(context.Context, api.UpdateLibraryItemRequestObject) (api.UpdateLibraryItemResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SetEpisodeWatched(context.Context, api.SetEpisodeWatchedRequestObject) (api.SetEpisodeWatchedResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) MarkSeasonWatched(context.Context, api.MarkSeasonWatchedRequestObject) (api.MarkSeasonWatchedResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) MarkShowWatched(context.Context, api.MarkShowWatchedRequestObject) (api.MarkShowWatchedResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SyncLibrary(context.Context, api.SyncLibraryRequestObject) (api.SyncLibraryResponseObject, error) {
	return nil, errNotImplemented
}
