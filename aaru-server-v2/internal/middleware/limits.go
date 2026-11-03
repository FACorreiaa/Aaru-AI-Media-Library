package middleware

import (
	"aaru-go-api/internal/apperr"
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
)

// BodyRule is one request's body bound (HTTP-001).
type BodyRule struct {
	// Limit is the most the request may send; reading past it fails with *http.MaxBytesError.
	Limit int64
	// OwnBound marks a handler that checks the declared length itself and answers with its own
	// message: the middleware then only stops reading past Limit, and the handler's limit
	// (at most Limit) speaks.
	OwnBound bool
	// TooLarge answers an oversize body instead of the shared 413.
	TooLarge *apperr.Error
}

const tooLargeKey = "aaru.body.too.large"

// BodyLimit bounds each request's body by its route's rule, before the validator or a handler
// reads it. A declared length over the limit is refused at once.
func BodyLimit(rule func(c echo.Context) BodyRule) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			r := rule(c)
			tooLarge := r.TooLarge
			if tooLarge == nil {
				tooLarge = apperr.FromStatus(http.StatusRequestEntityTooLarge, "")
			}
			req := c.Request()
			if !r.OwnBound && req.ContentLength > r.Limit {
				return tooLarge
			}
			c.Set(tooLargeKey, tooLarge)
			req.Body = http.MaxBytesReader(c.Response(), req.Body, r.Limit)
			return next(c)
		}
	}
}

// bodyTooLarge is the answer for err when reading the body ran past its limit, else nil.
func bodyTooLarge(c echo.Context, err error) *apperr.Error {
	var maxErr *http.MaxBytesError
	if !errors.As(err, &maxErr) {
		return nil
	}
	if e, ok := c.Get(tooLargeKey).(*apperr.Error); ok {
		return e
	}
	return apperr.FromStatus(http.StatusRequestEntityTooLarge, "")
}

// Deadline bounds a request's context by timeout (DB-001), so a slow query, a full pool or a
// provider's Retry-After cannot hold a request until the client gives up. exempt routes (the
// WebSocket, uploads, the export, MCP) keep the request's own context. timeout <= 0 turns it off.
func Deadline(timeout time.Duration, exempt func(c echo.Context) bool) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		if timeout <= 0 {
			return next
		}
		return func(c echo.Context) error {
			if exempt != nil && exempt(c) {
				return next(c)
			}
			req := c.Request()
			ctx, cancel := context.WithTimeout(req.Context(), timeout)
			defer cancel()
			c.SetRequest(req.WithContext(ctx))
			return next(c)
		}
	}
}
