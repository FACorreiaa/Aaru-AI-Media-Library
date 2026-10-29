// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetOAuthRequest(context.Context, api.GetOAuthRequestRequestObject) (api.GetOAuthRequestResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ApproveOAuthRequest(context.Context, api.ApproveOAuthRequestRequestObject) (api.ApproveOAuthRequestResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DenyOAuthRequest(context.Context, api.DenyOAuthRequestRequestObject) (api.DenyOAuthRequestResponseObject, error) {
	return nil, errNotImplemented
}
