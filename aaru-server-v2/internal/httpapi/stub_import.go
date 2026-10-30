// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) CreateCATFeedImport(context.Context, api.CreateCATFeedImportRequestObject) (api.CreateCATFeedImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateLastFMImport(context.Context, api.CreateLastFMImportRequestObject) (api.CreateLastFMImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateListenBrainzImport(context.Context, api.CreateListenBrainzImportRequestObject) (api.CreateListenBrainzImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) StartStremioLink(context.Context, api.StartStremioLinkRequestObject) (api.StartStremioLinkResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) PollStremioLink(context.Context, api.PollStremioLinkRequestObject) (api.PollStremioLinkResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UndoListenImport(context.Context, api.UndoListenImportRequestObject) (api.UndoListenImportResponseObject, error) {
	return nil, errNotImplemented
}
