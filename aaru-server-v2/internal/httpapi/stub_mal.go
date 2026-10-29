// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) DisconnectMAL(context.Context, api.DisconnectMALRequestObject) (api.DisconnectMALResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetMALConnection(context.Context, api.GetMALConnectionRequestObject) (api.GetMALConnectionResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ConnectMAL(context.Context, api.ConnectMALRequestObject) (api.ConnectMALResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RequestMALPull(context.Context, api.RequestMALPullRequestObject) (api.RequestMALPullResponseObject, error) {
	return nil, errNotImplemented
}
