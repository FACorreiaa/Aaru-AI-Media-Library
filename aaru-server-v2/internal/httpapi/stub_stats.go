// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetProfileStats(context.Context, api.GetProfileStatsRequestObject) (api.GetProfileStatsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetStats(context.Context, api.GetStatsRequestObject) (api.GetStatsResponseObject, error) {
	return nil, errNotImplemented
}
