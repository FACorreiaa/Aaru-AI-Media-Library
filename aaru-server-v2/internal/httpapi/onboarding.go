package httpapi

import (
	"aaru-go-api/internal/aisharing"
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"time"
)

// First-run onboarding (ONB-001): the rows to pick from, the picks, titles related to them, and
// the end of the flow.

// FinishOnboarding is PUT /v1/me/onboarding: the flow is over, finished or skipped. The first call
// wins; what the flow saved stays.
func (s *Server) FinishOnboarding(ctx context.Context, req api.FinishOnboardingRequestObject) (api.FinishOnboardingResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Auth.Store.FinishOnboarding(ctx, user, req.Body.Skipped); err != nil {
		return nil, err
	}
	return api.FinishOnboarding204Response{}, nil
}

// GetOnboardingRows is GET /v1/onboarding/rows: well-known titles of one kind, marked with the
// caller's library.
func (s *Server) GetOnboardingRows(ctx context.Context, req api.GetOnboardingRowsRequestObject) (api.GetOnboardingRowsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.Catalog.Onboarding.Rows(ctx, catalog.RowKind(req.Params.Kind), user)
	if err != nil {
		return nil, err
	}
	out := make([]api.DiscoverRow, 0, len(rows))
	for _, row := range rows {
		out = append(out, api.DiscoverRow{
			Id: row.ID, Kind: api.DiscoverRowKind(row.Kind), Title: row.Title, Items: discoverHits(row.Items), Note: row.Note,
		})
	}
	return api.GetOnboardingRows200JSONResponse(api.DiscoverRows{Rows: out}), nil
}

// AddOnboardingPicks is POST /v1/onboarding/picks: one step's picks, as one action.
// onboardingPicksCeiling bounds one step's picks: 60 refs resolved four at a time at the
// slowest provider's pace, plus the batch.
const onboardingPicksCeiling = 2 * time.Minute

func (s *Server) AddOnboardingPicks(ctx context.Context, req api.AddOnboardingPicksRequestObject) (api.AddOnboardingPicksResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	picks := make([]library.Pick, 0, len(req.Body.Items))
	for _, item := range req.Body.Items {
		pick := library.Pick{Ref: MediaRefFromAPI(item.MediaRef)}
		if item.Status != nil {
			st := core.LibraryStatus(*item.Status)
			pick.Status = &st
		}
		picks = append(picks, pick)
	}
	// Off the request deadline (noDeadline): 60 new manga picks resolve at AniList's pace.
	ctx, cancel := context.WithTimeout(ctx, onboardingPicksCeiling)
	defer cancel()
	result, err := s.Library.AddPicks(ctx, picks, user)
	if err != nil {
		return nil, err
	}
	out := api.OnboardingPicked{Items: make([]api.OnboardingPickedItem, 0, len(result.Items)), Missed: result.Missed}
	for _, item := range result.Items {
		out.Items = append(out.Items, api.OnboardingPickedItem{
			Index: item.Index, LibraryItemId: apiid.From(item.ItemID), TitleId: apiid.From(item.TitleID),
		})
	}
	if result.ActionID != nil {
		id := apiid.From(*result.ActionID)
		out.ActionId = &id
	}
	return api.AddOnboardingPicks200JSONResponse(out), nil
}

// GetOnboardingRelated is POST /v1/onboarding/related: titles related to the picks, from their
// relation graphs, leaving out what the caller has.
func (s *Server) GetOnboardingRelated(ctx context.Context, req api.GetOnboardingRelatedRequestObject) (api.GetOnboardingRelatedResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	related, err := s.Catalog.Relations.OnboardingRelated(ctx, user, apiid.IDs(req.Body.TitleIds))
	if err != nil {
		return nil, err
	}
	out := api.OnboardingRelated{Items: make([]api.OnboardingRelatedItem, 0, len(related.Items)), Partial: related.Partial}
	for _, r := range related.Items {
		out.Items = append(out.Items, api.OnboardingRelatedItem{
			Hit: CatalogHitDTO(r.Hit, nil), Relation: api.Relation(r.Relation),
			FromTitleId: apiid.From(r.FromTitleID), FromTitle: r.FromTitle,
		})
	}
	return api.GetOnboardingRelated200JSONResponse(out), nil
}

// SetAISharing is PUT /v1/me/ai-sharing: the user's yes or no to Aaru sending their data to its AI
// provider (PRV-002). The latest answer holds.
func (s *Server) SetAISharing(ctx context.Context, req api.SetAISharingRequestObject) (api.SetAISharingResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	answer, err := aisharing.Set(ctx, s.q, user, req.Body.Allowed, time.Now())
	if err != nil {
		return nil, err
	}
	return api.SetAISharing200JSONResponse(aiSharingDTO(answer)), nil
}

// aiSharingDTO maps an answer to `AISharing`.
func aiSharingDTO(a aisharing.Answer) api.AISharing {
	return api.AISharing{State: api.AISharingState(a.State), DecidedAt: apitime.PtrOrNil(a.DecidedAt)}
}
