// Package middleware is the request pipeline, in the Swift server's order:
// log, metrics, error shape, auth, client time zone, avatar cache headers.
package middleware

import (
	"log/slog"
	"strings"
	"time"

	"github.com/labstack/echo/v4"
)

// RequestLog logs each request and its outcome, never a secret in the URL: the
// Stremio addon's token is a path segment, and the provider callbacks carry
// `code` and `state`.
func RequestLog(log *slog.Logger) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			req := c.Request()
			path := Redacted(req.URL.Path, req.URL.RawQuery)
			log.Info("Request", "hb.request.path", path, "hb.request.method", req.Method)
			started := time.Now()
			err := next(c)
			log.Info("Response",
				"hb.request.path", path,
				"hb.request.method", req.Method,
				"hb.response.status", c.Response().Status,
				"hb.response.ms", time.Since(started).Milliseconds(),
			)
			return err
		}
	}
}

// Redacted is the path as logged: `/stremio/<secret>/…` becomes `/stremio/[token]/…`;
// the provider callbacks and the concert city search lose their query.
func Redacted(path, query string) string {
	if rest, ok := strings.CutPrefix(path, "/stremio/"); ok {
		tail := ""
		if i := strings.IndexByte(rest, '/'); i >= 0 {
			tail = rest[i:]
		}
		return "/stremio/[token]" + tail
	}
	switch path {
	case "/v1/imports/trakt/callback", "/v1/connections/mal/callback", "/v1/concerts/places":
		return path
	}
	if query == "" {
		return path
	}
	return path + "?" + query
}
