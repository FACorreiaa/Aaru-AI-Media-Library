package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/oauth"
	"context"
	"net/url"
)

// OUT-004 · the consent page's side of OAuth: what the app asked, and the user's
// answer. Session-only, like every `/v1` route; the binding proves it is the
// browser that asked.

// GetOAuthRequest is `GET /v1/oauth/requests/{id}`.
func (s *Server) GetOAuthRequest(ctx context.Context, req api.GetOAuthRequestRequestObject) (api.GetOAuthRequestResponseObject, error) {
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	if s.OAuth == nil {
		return nil, apperr.NotFound("This connection request expired. Start again from the app.")
	}
	request, client, err := s.OAuth.Pending(ctx, req.Id)
	if err != nil {
		return nil, err
	}
	host := request.RedirectURI
	if u, err := url.Parse(request.RedirectURI); err == nil && u.Hostname() != "" {
		host = u.Hostname()
	}
	return api.GetOAuthRequest200JSONResponse{
		Id: request.ID, ClientName: client.Name, RedirectHost: host,
		Kind: api.AgentTokenKind(oauth.KindForClientName(client.Name)), ExpiresAt: apitime.From(request.ExpiresAt),
	}, nil
}

// ApproveOAuthRequest is `POST /v1/oauth/requests/{id}/approve`.
func (s *Server) ApproveOAuthRequest(ctx context.Context, req api.ApproveOAuthRequestRequestObject) (api.ApproveOAuthRequestResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if s.OAuth == nil {
		return nil, apperr.NotFound("This connection request expired. Start again from the app.")
	}
	next, err := s.OAuth.Approve(ctx, req.Id, userID, req.Body.Binding, req.Body.Name, deref(req.Body.AllowLibraryWrites))
	if err != nil {
		return nil, err
	}
	return api.ApproveOAuthRequest200JSONResponse{RedirectTo: next}, nil
}

// DenyOAuthRequest is `POST /v1/oauth/requests/{id}/deny`.
func (s *Server) DenyOAuthRequest(ctx context.Context, req api.DenyOAuthRequestRequestObject) (api.DenyOAuthRequestResponseObject, error) {
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	if s.OAuth == nil {
		return nil, apperr.NotFound("This connection request expired. Start again from the app.")
	}
	next, err := s.OAuth.Deny(ctx, req.Id, req.Body.Binding)
	if err != nil {
		return nil, err
	}
	return api.DenyOAuthRequest200JSONResponse{RedirectTo: next}, nil
}
