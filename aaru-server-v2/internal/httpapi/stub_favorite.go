// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetMyFavorites(context.Context, api.GetMyFavoritesRequestObject) (api.GetMyFavoritesResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SetMyFavorites(context.Context, api.SetMyFavoritesRequestObject) (api.SetMyFavoritesResponseObject, error) {
	return nil, errNotImplemented
}
