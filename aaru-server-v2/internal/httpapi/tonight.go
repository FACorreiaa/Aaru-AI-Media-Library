package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/tonight"
	"context"

	"github.com/google/uuid"
)

// TonightHandlers.swift: the Tonight strip (AG-005) and its two verdicts.

func (s *Server) GetTonight(ctx context.Context, req api.GetTonightRequestObject) (api.GetTonightResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	strip, err := s.Tonight.Tonight(ctx, userID, req.Params.Tz)
	if err != nil {
		return nil, err
	}
	picks := make([]api.TonightPick, 0, len(strip.Picks))
	for _, p := range strip.Picks {
		dto := api.TonightPick{
			LibraryItemId: apiid.From(p.LibraryItemID), Title: TitleSummaryDTO(p.Title), Kind: api.TonightPickKind(p.Kind),
			EpisodeName: p.EpisodeName, Minutes: p.Minutes, AirsAt: apitime.PtrOrNil(p.AirsAt),
			AirTimeKnown: p.AirTimeKnown, Reason: p.Reason,
		}
		if p.Episode != nil {
			dto.Episode = &api.EpisodeRef{Season: p.Episode.Season, Number: p.Episode.Episode}
		}
		picks = append(picks, dto)
	}
	return api.GetTonight200JSONResponse{Day: apiDate(strip.Day), Picks: picks}, nil
}

func (s *Server) SendTonightFeedback(ctx context.Context, req api.SendTonightFeedbackRequestObject) (api.SendTonightFeedbackResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound("No such library item.")
	}
	if req.Body == nil {
		return nil, apperr.NotFound()
	}
	verdict := tonight.VerdictRejected
	if req.Body.Verdict == api.TonightFeedbackVerdictNotTonight {
		verdict = tonight.VerdictNotTonight
	}
	if err := s.Tonight.SaveFeedback(ctx, userID, req.Id.ID(), verdict, req.Params.Tz); err != nil {
		return nil, err
	}
	return api.SendTonightFeedback204Response{}, nil
}

func (s *Server) ClearTonightFeedback(ctx context.Context, req api.ClearTonightFeedbackRequestObject) (api.ClearTonightFeedbackResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Id.ID() == uuid.Nil {
		return nil, apperr.NotFound("No such library item.")
	}
	if err := s.Tonight.ClearFeedback(ctx, userID, req.Id.ID(), req.Params.Tz); err != nil {
		return nil, err
	}
	return api.ClearTonightFeedback204Response{}, nil
}
