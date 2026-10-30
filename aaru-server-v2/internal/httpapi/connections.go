package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"context"
	"net/http"

	"github.com/labstack/echo/v4"
)

// Trakt connect (IMP-002, ImportHandlers.swift) and MyAnimeList connect (SCR-005,
// MALHandlers.swift), plus the providers' browser redirects (ConnectRedirectRoutes.swift).

func (s *Server) ConnectTrakt(ctx context.Context, req api.ConnectTraktRequestObject) (api.ConnectTraktResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	url, err := s.TraktConnect.Start(ctx, user, req.Body.ReturnTo)
	if err != nil {
		return nil, err
	}
	return api.ConnectTrakt200JSONResponse{AuthorizeUrl: url}, nil
}

func (s *Server) GetTraktConnection(ctx context.Context, _ api.GetTraktConnectionRequestObject) (api.GetTraktConnectionResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	status, err := s.TraktConnect.Status(ctx, user)
	if err != nil {
		return nil, err
	}
	return api.GetTraktConnection200JSONResponse{
		Connected: status.Connected, Username: status.Username, ConnectedAt: apitime.PtrOrNil(status.ConnectedAt),
	}, nil
}

func (s *Server) DisconnectTrakt(ctx context.Context, _ api.DisconnectTraktRequestObject) (api.DisconnectTraktResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.TraktConnect.Disconnect(ctx, user); err != nil {
		return nil, err
	}
	return api.DisconnectTrakt204Response{}, nil
}

func (s *Server) ConnectMAL(ctx context.Context, req api.ConnectMALRequestObject) (api.ConnectMALResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	url, err := s.MALConnect.Start(ctx, user, req.Body.ReturnTo)
	if err != nil {
		return nil, err
	}
	return api.ConnectMAL200JSONResponse{AuthorizeUrl: url}, nil
}

func (s *Server) GetMALConnection(ctx context.Context, _ api.GetMALConnectionRequestObject) (api.GetMALConnectionResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	status, err := s.MALConnect.Status(ctx, user)
	if err != nil {
		return nil, err
	}
	removed := make([]api.MALRemovedEntry, len(status.Removed))
	for i, r := range status.Removed {
		removed[i] = api.MALRemovedEntry{MalId: r.MalID, Title: r.Title, RemovedAt: apitime.From(r.RemovedAt)}
	}
	return api.GetMALConnection200JSONResponse{
		Connected: status.Connected, Username: status.Username, ConnectedAt: apitime.PtrOrNil(status.ConnectedAt),
		NeedsReconnect: status.NeedsReconnect, PulledAt: apitime.PtrOrNil(status.PulledAt), Removed: removed,
	}, nil
}

func (s *Server) RequestMALPull(ctx context.Context, _ api.RequestMALPullRequestObject) (api.RequestMALPullResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if _, err := s.MALConnect.RequestPull(ctx, user); err != nil {
		return nil, err
	}
	return api.RequestMALPull204Response{}, nil
}

func (s *Server) DisconnectMAL(ctx context.Context, _ api.DisconnectMALRequestObject) (api.DisconnectMALResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.MALConnect.Disconnect(ctx, user); err != nil {
		return nil, err
	}
	return api.DisconnectMAL204Response{}, nil
}

// registerConnectRedirectRoutes adds the providers' browser redirects after a connect: Trakt's
// (IMP-002) and MyAnimeList's (SCR-005). Plain, not generated: the generated server would
// percent-encode the `aaru://` Location. No session (both are public in the auth middleware): the
// one-time `state` names the user.
func (s *Server) registerConnectRedirectRoutes(e *echo.Echo) {
	e.GET("/v1/imports/trakt/callback", func(c echo.Context) error {
		code, state, errParam := callbackQuery(c)
		next, err := s.TraktConnect.Callback(c.Request().Context(), code, state, errParam)
		if err != nil {
			return err
		}
		return c.Redirect(http.StatusFound, next)
	})
	e.GET("/v1/connections/mal/callback", func(c echo.Context) error {
		code, state, errParam := callbackQuery(c)
		next, err := s.MALConnect.Callback(c.Request().Context(), code, state, errParam)
		if err != nil {
			return err
		}
		return c.Redirect(http.StatusFound, next)
	})
}

// callbackQuery is the redirect's `code`, `state` and `error`; nil when one was not sent.
func callbackQuery(c echo.Context) (code, state, errParam *string) {
	query := c.QueryParams()
	get := func(name string) *string {
		if values, ok := query[name]; ok && len(values) > 0 {
			v := values[0]
			return &v
		}
		return nil
	}
	return get("code"), get("state"), get("error")
}
