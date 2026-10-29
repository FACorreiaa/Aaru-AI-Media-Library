// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListBadges(context.Context, api.ListBadgesRequestObject) (api.ListBadgesResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) MarkBadgesSeen(context.Context, api.MarkBadgesSeenRequestObject) (api.MarkBadgesSeenResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListPoints(context.Context, api.ListPointsRequestObject) (api.ListPointsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetProgress(context.Context, api.GetProgressRequestObject) (api.GetProgressResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetLeaderboard(context.Context, api.GetLeaderboardRequestObject) (api.GetLeaderboardResponseObject, error) {
	return nil, errNotImplemented
}
