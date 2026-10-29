// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetAgentSetup(context.Context, api.GetAgentSetupRequestObject) (api.GetAgentSetupResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListAgentTokens(context.Context, api.ListAgentTokensRequestObject) (api.ListAgentTokensResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateAgentToken(context.Context, api.CreateAgentTokenRequestObject) (api.CreateAgentTokenResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RevokeAgentToken(context.Context, api.RevokeAgentTokenRequestObject) (api.RevokeAgentTokenResponseObject, error) {
	return nil, errNotImplemented
}
