// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) CreateCATFeedImport(context.Context, api.CreateCATFeedImportRequestObject) (api.CreateCATFeedImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ConnectTrakt(context.Context, api.ConnectTraktRequestObject) (api.ConnectTraktResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DisconnectTrakt(context.Context, api.DisconnectTraktRequestObject) (api.DisconnectTraktResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetTraktConnection(context.Context, api.GetTraktConnectionRequestObject) (api.GetTraktConnectionResponseObject, error) {
	return nil, errNotImplemented
}
