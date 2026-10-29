// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListListens(context.Context, api.ListListensRequestObject) (api.ListListensResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetTopListens(context.Context, api.GetTopListensRequestObject) (api.GetTopListensResponseObject, error) {
	return nil, errNotImplemented
}
