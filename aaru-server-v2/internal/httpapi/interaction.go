package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/social"
	"context"

	"github.com/google/uuid"
)

// InteractionHandlers.swift: SOC-007 reactions and SOC-006 recommendations.

// SetActivityReaction sets the viewer's reaction on a friend's activity row.
func (s *Server) SetActivityReaction(ctx context.Context, req api.SetActivityReactionRequestObject) (api.SetActivityReactionResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	emoji := string(req.Body.Emoji)
	if err := s.Social.React(ctx, &emoji, req.Id, viewer); err != nil {
		return nil, err
	}
	return api.SetActivityReaction204Response{}, nil
}

// ClearActivityReaction clears the viewer's reaction.
func (s *Server) ClearActivityReaction(ctx context.Context, req api.ClearActivityReactionRequestObject) (api.ClearActivityReactionResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Social.React(ctx, nil, req.Id, viewer); err != nil {
		return nil, err
	}
	return api.ClearActivityReaction204Response{}, nil
}

// RecommendTitle sends one title to up to ten friends.
func (s *Server) RecommendTitle(ctx context.Context, req api.RecommendTitleRequestObject) (api.RecommendTitleResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	recipients := make([]uuid.UUID, 0, len(req.Body.To))
	for _, id := range req.Body.To {
		if id.ID() == uuid.Nil {
			return nil, social.ErrNoSuchUser
		}
		recipients = append(recipients, id.ID())
	}
	if err := s.Social.Recommend(ctx, MediaRefFromAPI(req.Body.Title), req.Body.Note, recipients, viewer); err != nil {
		return nil, err
	}
	return api.RecommendTitle204Response{}, nil
}

// ListRecommendations answers the viewer's waiting recommendations.
func (s *Server) ListRecommendations(ctx context.Context, _ api.ListRecommendationsRequestObject) (api.ListRecommendationsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	inbox, err := s.Social.Inbox(ctx, viewer)
	if err != nil {
		return nil, err
	}
	items := make([]api.RecommendationItem, 0, len(inbox))
	for _, item := range inbox {
		items = append(items, api.RecommendationItem{
			Id: apiid.From(item.Recommendation.ID), From: SocialUserDTO(item.From), Title: TitleSummaryDTO(item.Title),
			Note: item.Recommendation.Note, CreatedAt: apitime.From(item.Recommendation.CreatedAt),
		})
	}
	return api.ListRecommendations200JSONResponse(api.RecommendationList{Items: items}), nil
}

// AddRecommendation adds a recommended title to Plan to watch.
func (s *Server) AddRecommendation(ctx context.Context, req api.AddRecommendationRequestObject) (api.AddRecommendationResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Social.AddRecommendation(ctx, req.Id.ID(), viewer); err != nil {
		return nil, err
	}
	return api.AddRecommendation204Response{}, nil
}

// DismissRecommendation removes a waiting recommendation.
func (s *Server) DismissRecommendation(ctx context.Context, req api.DismissRecommendationRequestObject) (api.DismissRecommendationResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Social.DismissRecommendation(ctx, req.Id.ID(), viewer); err != nil {
		return nil, err
	}
	return api.DismissRecommendation204Response{}, nil
}
