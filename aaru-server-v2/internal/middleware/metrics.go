package middleware

import (
	"aaru-go-api/internal/metrics"
	"regexp"
	"time"

	"github.com/labstack/echo/v4"
)

var echoParam = regexp.MustCompile(`:([A-Za-z0-9_]+)`)

// Metrics counts each request by method, route template and status, and times it by route group.
func Metrics() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			metrics.RequestStarted()
			started := time.Now()
			err := next(c)
			metrics.RequestFinished(c.Request().Method, RouteTemplate(c), c.Response().Status, time.Since(started))
			return err
		}
	}
}

// RouteTemplate is the matched route in OpenAPI form (`/v1/titles/{id}`), "" when nothing matched.
func RouteTemplate(c echo.Context) string {
	path := c.Path()
	if path == "" || c.Get(unmatchedKey) != nil {
		return ""
	}
	return echoParam.ReplaceAllString(path, "{$1}")
}

const unmatchedKey = "aaru.unmatched"
