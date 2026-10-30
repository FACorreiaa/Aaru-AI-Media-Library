package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"context"
)

// ListAgentTokens is `GET /v1/agent/tokens?for=`: one surface's live tokens, Stremio by default.
func (s *Server) ListAgentTokens(ctx context.Context, req api.ListAgentTokensRequestObject) (api.ListAgentTokensResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	group := auth.GroupStremio
	if req.Params.For != nil {
		g, ok := auth.ParseTokenGroup(string(*req.Params.For))
		if !ok {
			return nil, apperr.BadRequest()
		}
		group = g
	}
	tokens, err := s.AgentTokens.Tokens(ctx, userID, group)
	if err != nil {
		return nil, err
	}
	items := make([]api.AgentToken, 0, len(tokens))
	for _, t := range tokens {
		items = append(items, agentTokenDTO(t))
	}
	return api.ListAgentTokens200JSONResponse{Items: items}, nil
}

// CreateAgentToken is `POST /v1/agent/tokens`: the secret is shown once, with the setup that uses it.
func (s *Server) CreateAgentToken(ctx context.Context, req api.CreateAgentTokenRequestObject) (api.CreateAgentTokenResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	kind, ok := auth.ParseTokenKind(string(req.Body.Kind))
	if !ok {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	// A music token is named for its scrobbler unless the user named it.
	var scrobbler *api.MusicScrobbler
	name := req.Body.Name
	if kind == auth.KindMusic {
		sc := musicScrobbler(req.Body.Scrobbler)
		scrobbler = &sc
		if name == nil {
			title := musicScrobblerTitle(sc)
			name = &title
		}
	}
	minted, err := s.AgentTokens.Create(ctx, userID, kind, name, deref(req.Body.AllowLibraryWrites), deref(req.Body.AllowImports))
	if err != nil {
		return nil, err
	}
	out := api.CreateAgentToken201JSONResponse{Token: agentTokenDTO(minted.Token), Secret: minted.Secret}
	if links := minted.Stremio; links != nil {
		out.Stremio = &struct {
			// InstallUrl The `stremio://` link that opens the Stremio app.
			InstallUrl    string `json:"installUrl"`    //nolint:revive // mirrors the generated type
			ManifestUrl   string `json:"manifestUrl"`   //nolint:revive // mirrors the generated type
			WebInstallUrl string `json:"webInstallUrl"` //nolint:revive // mirrors the generated type
		}{InstallUrl: links.InstallURL, ManifestUrl: links.ManifestURL, WebInstallUrl: links.WebInstallURL}
	}
	if setup, ok := agentSetup(kind, s.AgentTokens.PublicBaseURL, &minted.Secret); ok {
		out.Setup = &setup
	}
	if scrobbler != nil {
		music := musicSetup(*scrobbler, s.AgentTokens.PublicBaseURL, minted.Secret)
		out.Music = &music
	}
	return out, nil
}

// GetAgentSetup is `GET /v1/agent/setup/{kind}`: the steps with a placeholder secret.
func (s *Server) GetAgentSetup(ctx context.Context, req api.GetAgentSetupRequestObject) (api.GetAgentSetupResponseObject, error) {
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	// The path takes only the MCP kinds; anything else fails decoding, as the Swift router did.
	if _, ok := mcpKind(auth.TokenKind(req.Kind)); !ok {
		return nil, apperr.BadRequest()
	}
	setup, ok := agentSetup(auth.TokenKind(req.Kind), s.AgentTokens.PublicBaseURL, nil)
	if !ok {
		return nil, apperr.NotFound()
	}
	return api.GetAgentSetup200JSONResponse(setup), nil
}

// RevokeAgentToken is `DELETE /v1/agent/tokens/{id}`.
func (s *Server) RevokeAgentToken(ctx context.Context, req api.RevokeAgentTokenRequestObject) (api.RevokeAgentTokenResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.AgentTokens.Revoke(ctx, req.Id, userID); err != nil {
		return nil, err
	}
	return api.RevokeAgentToken204Response{}, nil
}

func agentTokenDTO(t auth.AgentToken) api.AgentToken {
	scopes := make([]api.AgentTokenScopes, 0, len(t.Scopes))
	for _, sc := range auth.SortedScopes(t.Scopes) {
		scopes = append(scopes, api.AgentTokenScopes(sc))
	}
	return api.AgentToken{
		Id: t.ID, Name: t.Name, Kind: api.AgentTokenKind(t.Kind), Scopes: scopes,
		CreatedAt: apitime.From(t.CreatedAt), LastUsedAt: apitime.PtrOrNil(t.LastUsedAt),
	}
}

func deref(b *bool) bool { return b != nil && *b }
