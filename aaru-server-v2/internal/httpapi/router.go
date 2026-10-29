package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/middleware"
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

// maxBody bounds any request body. Routes that take uploads (imports, capture,
// avatars) read their own, smaller limits.
const maxBody = 64 << 20

// Router builds the echo instance: log, metrics, the shared error shape, auth,
// client time zone, avatar cache headers, then the generated `/v1` handlers and
// the routes outside openapi.yaml.
func (s *Server) Router(reporter middleware.Reporter) *echo.Echo {
	e := echo.New()
	e.HideBanner = true
	e.HidePort = true
	e.HTTPErrorHandler = func(err error, c echo.Context) {
		if c.Response().Committed {
			return
		}
		_ = middleware.Write(c, middleware.Map(err))
	}
	e.Use(
		middleware.RequestLog(s.Log),
		middleware.Metrics(),
		middleware.Errors(s.Log, reporter),
		bodyLimit(maxBody),
		middleware.Auth(sessionLookup{s.q}, s.Config.WebClientSecret),
		middleware.ClientTimeZone(),
		middleware.AvatarCache(),
	)
	// Body and parameter decode failures surface as echo 400s, which the error
	// middleware maps to `bad_request` like the Swift server did.
	strict := api.NewStrictHandler(s, nil)
	api.RegisterHandlers(e, strict)
	s.registerRawRoutes(e)
	return e
}

// bodyLimit refuses an oversize body with 413 before a handler reads it.
func bodyLimit(limit int64) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			req := c.Request()
			if req.ContentLength > limit {
				return apperr.FromStatus(http.StatusRequestEntityTooLarge, "")
			}
			req.Body = http.MaxBytesReader(c.Response(), req.Body, limit)
			return next(c)
		}
	}
}

type sessionLookup struct{ q *sqlc.Queries }

func (l sessionLookup) UserIDForTokenHash(ctx context.Context, hash string, now time.Time) (uuid.UUID, bool, error) {
	id, err := l.q.SessionUserID(ctx, sqlc.SessionUserIDParams{TokenHash: hash, ExpiresAt: now})
	if err != nil {
		if isNoRows(err) {
			return uuid.Nil, false, nil
		}
		return uuid.Nil, false, err
	}
	return id, true, nil
}

// Logger is the request-independent logger handlers use.
func (s *Server) Logger() *slog.Logger { return s.Log }
