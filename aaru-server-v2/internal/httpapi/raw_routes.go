package httpapi

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/middleware"
	"net/http"

	"github.com/labstack/echo/v4"
)

var isNoRows = db.IsNoRows

// registerRawRoutes adds the routes outside the strict server: the three
// imports whose bodies come in several binary types, and every transport that
// is not in openapi.yaml. Each area registers its own here.
func (s *Server) registerRawRoutes(e *echo.Echo) {
	e.POST("/v1/imports/csv", s.createCSVImport)
	e.POST("/v1/imports/cat", s.createCATImport)
	e.POST("/v1/imports/capture", s.createCaptureImport)
	e.GET("/internal/metrics", s.internalMetrics)
	s.registerOAuthRoutes(e)
	// The realtime socket (GRP-006) signs itself in: a bearer token, or a browser ticket.
	e.GET("/v1/ws", s.realtimeGateway().Handle)
	s.registerMCPRoutes(e)
	s.registerConnectRedirectRoutes(e)
}

// internalMetrics is `GET /internal/metrics` → `{"users": N}` for the board at
// facorreia.com/apps, called in-cluster with METRICS_SECRET. Bearer only,
// compared in constant time; an empty secret turns the route off (404).
func (s *Server) internalMetrics(c echo.Context) error {
	secret := s.Config.MetricsSecret
	if secret == "" {
		return c.NoContent(http.StatusNotFound)
	}
	presented := middleware.BearerToken(c.Request().Header.Get("Authorization"))
	if presented == "" || !middleware.ConstantTimeEquals(presented, secret) {
		return c.NoContent(http.StatusUnauthorized)
	}
	count, err := s.q.CountUsers(c.Request().Context())
	if err != nil {
		return err
	}
	c.Response().Header().Set("Cache-Control", "no-store")
	return c.JSON(http.StatusOK, map[string]int64{"users": count})
}
