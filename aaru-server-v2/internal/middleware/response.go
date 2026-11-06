package middleware

import (
	"github.com/labstack/echo/v5"
)

// Response is the request's *echo.Response under whatever wraps it (echo v5 hands handlers an
// http.ResponseWriter). Echo always installs one, so a miss is a bug; it falls back to a fresh
// one over the writer so a status read still works rather than panicking.
func Response(c *echo.Context) *echo.Response {
	if r, err := echo.UnwrapResponse(c.Response()); err == nil {
		return r
	}
	return echo.NewResponse(c.Response(), nil)
}

// Committed is whether the response's headers have gone out.
func Committed(c *echo.Context) bool { return Response(c).Committed }

// Status is the status the response was written with; 0 before it is.
func Status(c *echo.Context) int { return Response(c).Status }
