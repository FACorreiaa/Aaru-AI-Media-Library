// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListImports(context.Context, api.ListImportsRequestObject) (api.ListImportsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateAniListImport(context.Context, api.CreateAniListImportRequestObject) (api.CreateAniListImportResponseObject, error) {
	return nil, errNotImplemented
}

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

func (s *Server) CreateTraktImport(context.Context, api.CreateTraktImportRequestObject) (api.CreateTraktImportResponseObject, error) {
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

func (s *Server) DeleteImport(context.Context, api.DeleteImportRequestObject) (api.DeleteImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetImport(context.Context, api.GetImportRequestObject) (api.GetImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ApplyImport(context.Context, api.ApplyImportRequestObject) (api.ApplyImportResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ResolveImportRow(context.Context, api.ResolveImportRowRequestObject) (api.ResolveImportRowResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UndoListenImport(context.Context, api.UndoListenImportRequestObject) (api.UndoListenImportResponseObject, error) {
	return nil, errNotImplemented
}
