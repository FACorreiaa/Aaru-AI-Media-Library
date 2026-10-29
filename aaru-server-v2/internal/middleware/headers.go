package middleware

import (
	"aaru-go-api/internal/reqctx"
	"net/http"
	"strings"
	"time"

	"github.com/labstack/echo/v4"
)

// ClientTimeZone reads `X-Timezone` (GAM-003): points and streak days are dated
// in it. Anything Go does not know as an IANA zone is ignored.
func ClientTimeZone() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if loc := ParseTimeZone(c.Request().Header.Get("X-Timezone")); loc != nil {
				c.SetRequest(c.Request().WithContext(reqctx.WithTimeZone(c.Request().Context(), loc)))
			}
			return next(c)
		}
	}
}

// ParseTimeZone is an IANA identifier, or nil.
func ParseTimeZone(value string) *time.Location {
	if value == "" || len(value) > 64 || value == "Local" {
		return nil
	}
	loc, err := time.LoadLocation(value)
	if err != nil {
		return nil
	}
	return loc
}

// AvatarCache lets a private cache keep an avatar for a week (SOC-001b): its URL
// carries the version, so it is never stale.
func AvatarCache() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			req := c.Request()
			if req.Method == http.MethodGet && strings.HasPrefix(req.URL.Path, "/v1/users/") && strings.HasSuffix(req.URL.Path, "/avatar") {
				c.Response().Before(func() {
					if c.Response().Status == http.StatusOK {
						c.Response().Header().Set("Cache-Control", "private, max-age=604800")
					}
				})
			}
			return next(c)
		}
	}
}
