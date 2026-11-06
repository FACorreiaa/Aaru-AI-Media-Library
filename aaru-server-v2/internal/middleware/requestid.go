package middleware

import (
	"aaru-go-api/internal/reqctx"
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"

	"github.com/labstack/echo/v5"
)

// RequestIDHeader carries the request's id back to the caller, so a report can name the request.
const RequestIDHeader = "X-Request-Id"

// RequestID gives each request an id (HLT-005), keeps it in the request's context for the log
// handler, and sends it back in `X-Request-Id`. The id is always the server's own: a caller's
// header is never trusted into the logs.
func RequestID() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c *echo.Context) error {
			id := newRequestID()
			req := c.Request()
			c.SetRequest(req.WithContext(reqctx.WithRequestID(req.Context(), id)))
			c.Response().Header().Set(RequestIDHeader, id)
			return next(c)
		}
	}
}

func newRequestID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b) // crypto/rand.Read never fails on supported platforms
	return hex.EncodeToString(b)
}

// ContextHandler adds what the request's context knows (its id) to every record logged with
// that context, so the `*Context` logging calls tie a line to its request.
type ContextHandler struct {
	slog.Handler
}

// NewContextHandler wraps h.
func NewContextHandler(h slog.Handler) *ContextHandler { return &ContextHandler{Handler: h} }

// Handle adds `requestId` when ctx carries one.
func (h *ContextHandler) Handle(ctx context.Context, r slog.Record) error {
	if ctx != nil {
		if id := reqctx.RequestID(ctx); id != "" {
			r = r.Clone()
			r.AddAttrs(slog.String("requestId", id))
		}
	}
	return h.Handler.Handle(ctx, r)
}

// WithAttrs keeps the wrapper around the derived handler.
func (h *ContextHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &ContextHandler{Handler: h.Handler.WithAttrs(attrs)}
}

// WithGroup keeps the wrapper around the derived handler.
func (h *ContextHandler) WithGroup(name string) slog.Handler {
	return &ContextHandler{Handler: h.Handler.WithGroup(name)}
}
