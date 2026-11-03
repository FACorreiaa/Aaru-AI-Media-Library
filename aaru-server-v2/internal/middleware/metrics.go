package middleware

import (
	"aaru-go-api/internal/metrics"
	"net/http"
	"regexp"
	"sync"
	"time"

	"github.com/labstack/echo/v4"
)

var echoParam = regexp.MustCompile(`:([A-Za-z0-9_]+)`)

// Metrics counts each request by method, route template and status, and times it by route group.
// The count is taken in a defer, so a request that panics still leaves the in-flight gauge.
func Metrics() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			metrics.RequestStarted()
			started := time.Now()
			defer func() {
				metrics.RequestFinished(MethodLabel(c.Request().Method), RouteTemplate(c), c.Response().Status, time.Since(started))
			}()
			return next(c)
		}
	}
}

// MethodLabel is the method as a metric label: a standard method as is, anything else `OTHER`.
// net/http accepts any token as a method, and each would be a new series (HTTP-003).
func MethodLabel(method string) string {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut, http.MethodPatch,
		http.MethodDelete, http.MethodConnect, http.MethodOptions, http.MethodTrace:
		return method
	}
	return "OTHER"
}

// templates memoises echo path → OpenAPI template. Keys are registered route paths only, so it
// stays as small as the route table.
var templates sync.Map

// RouteTemplate is the matched route in OpenAPI form (`/v1/titles/{id}`), "" when nothing matched.
func RouteTemplate(c echo.Context) string {
	path := c.Path()
	if path == "" || c.Get(unmatchedKey) != nil {
		return ""
	}
	if t, ok := templates.Load(path); ok {
		return t.(string)
	}
	t := echoParam.ReplaceAllString(path, "{$1}")
	templates.Store(path, t)
	return t
}

const unmatchedKey = "aaru.unmatched"
