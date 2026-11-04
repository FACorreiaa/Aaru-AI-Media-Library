package middleware

import (
	"aaru-go-api/internal/apperr"
	"context"
	"errors"
	"io"
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
	// ReadTimeout bounds reading the whole body (HTTP-005); 0 leaves it open.
	ReadTimeout time.Duration
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
			if r.ReadTimeout > 0 && req.ContentLength != 0 {
				req.Body = deadlineBody(c.Response(), req.Body, r.ReadTimeout)
			}
			return next(c)
		}
	}
}

// deadlineBody bounds how long the client may take to send body (HTTP-005). A context deadline
// cannot do it: it does not interrupt a read. A server-wide ReadTimeout cannot either: it would cut
// WebSockets and large uploads alike. The connection's read deadline is lifted as soon as the body
// ends, because net/http then keeps a read open to notice the client leaving, and a deadline
// passing there would cancel a handler still at work. A writer that cannot set one (tests) just
// has no bound.
func deadlineBody(w http.ResponseWriter, body io.ReadCloser, timeout time.Duration) io.ReadCloser {
	rc := http.NewResponseController(w)
	if err := rc.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return body
	}
	return &timedBody{ReadCloser: body, rc: rc}
}

type timedBody struct {
	io.ReadCloser
	rc *http.ResponseController
}

// Read lifts the deadline once the body has ended, or failed.
func (b *timedBody) Read(p []byte) (int, error) {
	n, err := b.ReadCloser.Read(p)
	if err != nil {
		_ = b.rc.SetReadDeadline(time.Time{}) // the connection is going away if this fails
	}
	return n, err
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
