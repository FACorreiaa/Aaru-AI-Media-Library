// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ClearActivityReaction(context.Context, api.ClearActivityReactionRequestObject) (api.ClearActivityReactionResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SetActivityReaction(context.Context, api.SetActivityReactionRequestObject) (api.SetActivityReactionResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListRecommendations(context.Context, api.ListRecommendationsRequestObject) (api.ListRecommendationsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DismissRecommendation(context.Context, api.DismissRecommendationRequestObject) (api.DismissRecommendationResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) AddRecommendation(context.Context, api.AddRecommendationRequestObject) (api.AddRecommendationResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RecommendTitle(context.Context, api.RecommendTitleRequestObject) (api.RecommendTitleResponseObject, error) {
	return nil, errNotImplemented
}
