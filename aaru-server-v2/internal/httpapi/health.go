package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
	"time"
)

// GetHealth pings Postgres: 200 ok, or 503 unavailable with no database detail.
func (s *Server) GetHealth(ctx context.Context, _ api.GetHealthRequestObject) (api.GetHealthResponseObject, error) {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := s.Pool.Ping(ctx); err != nil {
		return api.GetHealth503JSONResponse{Status: api.HealthStatusUnavailable}, nil
	}
	return api.GetHealth200JSONResponse{Status: api.HealthStatusOk}, nil
}
