// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) CreateShare(context.Context, api.CreateShareRequestObject) (api.CreateShareResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSharePreview(context.Context, api.GetSharePreviewRequestObject) (api.GetSharePreviewResponseObject, error) {
	return nil, errNotImplemented
}
