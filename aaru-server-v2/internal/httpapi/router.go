package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/mcp"
	"aaru-go-api/internal/middleware"
	"aaru-go-api/internal/social"
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

// defaultBodyLimit bounds every request body but those in ownBodyLimits (HTTP-001): the
// validator reads and decodes a JSON body before the handler does, on public routes too.
const defaultBodyLimit = 1 << 20

// How long a client may take to send a body (HTTP-005): Traefik's own read timeout is off, for
// streams, so nothing else ends a request whose body stalls. An upload's allows 24 MB over a slow
// phone connection.
const (
	bodyReadTimeout   = time.Minute
	uploadReadTimeout = 10 * time.Minute
)

// ownBodyLimits are the routes that take more than the default, or read their body with their
// own bound and their own "too large" message. The middleware only stops reading past the
// limit here; the handler checks the declared length and speaks.
var ownBodyLimits = map[string]int64{
	"POST /v1/imports/csv":                         imports.MaxListenUploadBytes, // listening history; exports 5 MB
	"POST /v1/imports/cat":                         imports.MaxUploadBytes,
	"POST /v1/imports/capture":                     imports.MaxUploadBytes, // an image; JSON has captureJSONLimit
	"POST /v1/chats/transcribe":                    maxChatAudioBytes,
	"PUT /v1/me/avatar":                            social.MaxAvatarBytes,
	"POST " + listenBrainzPath + "/submit-listens": listenBrainzMaxBody,
	"POST " + mcp.Path:                             mcp.MaxBody,
	"POST " + scrobblePath + "/start":              defaultBodyLimit,
	"POST " + scrobblePath + "/pause":              defaultBodyLimit,
	"POST " + scrobblePath + "/stop":               defaultBodyLimit,
	"POST /oauth/register":                         defaultBodyLimit,
	"POST /oauth/token":                            defaultBodyLimit,
	"POST /oauth/revoke":                           defaultBodyLimit,
}

// noDeadline are the routes the request deadline leaves alone (DB-001): the socket lives for
// hours, uploads arrive at the client's pace, the export, MCP tool calls, a Chat turn and a
// transcription can run long (each has its own ceiling), and
// an import's approval, a plan's, their undo and account deletion are one transaction each that must not be
// cut half way through a large library.
var noDeadline = map[string]bool{
	"GET /v1/ws":                                   true,
	"POST /v1/imports/csv":                         true,
	"POST /v1/imports/cat":                         true,
	"POST /v1/imports/capture":                     true,
	"POST /v1/chats/:id/turns":                     true,
	"POST /v1/chats/transcribe":                    true,
	"PUT /v1/me/avatar":                            true,
	"POST " + listenBrainzPath + "/submit-listens": true,
	"GET /v1/me/export":                            true,
	"POST " + mcp.Path:                             true,
	"POST /v1/imports/:id/apply":                   true,
	"POST /v1/imports/:id/undo":                    true,
	"POST /v1/actions/:id/undo":                    true,
	"POST /v1/plans/:id/approve":                   true,
	"DELETE /v1/me":                                true,
}

func routeKey(c echo.Context) string { return c.Request().Method + " " + c.Path() }

// bodyRule is the request's body bound: its route's own, capture's JSON limit, or the default.
func bodyRule(c echo.Context) middleware.BodyRule {
	key := routeKey(c)
	if key == "POST /v1/imports/capture" && contentType(c) == "application/json" {
		return middleware.BodyRule{Limit: captureJSONLimit, TooLarge: errCaptureTooLarge, ReadTimeout: bodyReadTimeout}
	}
	if limit, ok := ownBodyLimits[key]; ok {
		timeout := bodyReadTimeout
		if limit > defaultBodyLimit {
			timeout = uploadReadTimeout
		}
		return middleware.BodyRule{Limit: limit, OwnBound: true, ReadTimeout: timeout}
	}
	return middleware.BodyRule{Limit: defaultBodyLimit, ReadTimeout: bodyReadTimeout}
}

// Router builds the echo instance: request id, log, metrics, the shared error shape,
// panic recovery, body limits, the request deadline, auth, client time zone, avatar cache headers, then the generated `/v1` handlers and
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
	spec, err := api.GetSwagger()
	if err != nil {
		panic(fmt.Sprintf("embedded openapi spec: %v", err))
	}
	validate, err := middleware.Validate(spec)
	if err != nil {
		panic(fmt.Sprintf("request validation: %v", err))
	}
	requestTimeout := time.Duration(s.Config.HTTP.RequestTimeoutSeconds) * time.Second
	e.Use(
		middleware.RequestID(),
		middleware.RequestLog(s.Log),
		middleware.Metrics(),
		middleware.Errors(s.Log, reporter),
		// Inside Errors, so a panic is answered, logged and reported as a 500 (REL-001).
		middleware.Recover(),
		middleware.BodyLimit(bodyRule),
		middleware.Deadline(requestTimeout, func(c echo.Context) bool { return noDeadline[routeKey(c)] }),
		middleware.Auth(sessionLookup{s.q}, s.Config.WebClientSecret, s.Config.HTTP.TrustedProxyHops),
		middleware.ClientTimeZone(),
		middleware.AvatarCache(),
		validate,
	)
	// Body and parameter decode failures surface as echo 400s, which the error
	// middleware maps to `bad_request` like the Swift server did.
	strict := api.NewStrictHandler(s, []api.StrictMiddlewareFunc{middleware.Operation})
	api.RegisterHandlers(e, strict)
	s.registerRawRoutes(e)
	return e
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
