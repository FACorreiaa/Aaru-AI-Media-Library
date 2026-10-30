package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/plans"
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
)

// Plan routes (API/PlanHandlers.swift): OUT-004 · the user's side of remote approval.
// Session-only: the auth middleware resolves sessions, never agent tokens, so no caller can
// approve its own plan. A malformed id reads as uuid.Nil, which no plan has: 404.

// ListPlans is GET /v1/plans: pending ones by default, or all with `status=all`.
func (s *Server) ListPlans(ctx context.Context, req api.ListPlansRequestObject) (api.ListPlansResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	pendingOnly := req.Params.Status == nil || *req.Params.Status != api.ListPlansParamsStatusAll
	list, err := s.Plans.Plans(ctx, user, pendingOnly)
	if err != nil {
		return nil, err
	}
	items := make([]planJSON, len(list))
	for i, p := range list {
		items[i] = planDTO(p)
	}
	return planListResponse{Items: items}, nil
}

// GetPlan is GET /v1/plans/{id}.
func (s *Server) GetPlan(ctx context.Context, req api.GetPlanRequestObject) (api.GetPlanResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	p, err := s.Plans.Plan(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return planResponse(planDTO(p)), nil
}

// ApprovePlan is POST /v1/plans/{id}/approve: the plan applied as one undoable action.
func (s *Server) ApprovePlan(ctx context.Context, req api.ApprovePlanRequestObject) (api.ApprovePlanResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	p, action, err := s.Plans.Approve(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return planApproveResponse{Plan: planDTO(p), Action: ActionDTO(action)}, nil
}

// DenyPlan is POST /v1/plans/{id}/deny.
func (s *Server) DenyPlan(ctx context.Context, req api.DenyPlanRequestObject) (api.DenyPlanResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	p, err := s.Plans.Deny(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return planResponse(planDTO(p)), nil
}

// planJSON is Components.Schemas.AgentPlan as the Swift server wrote it: the plan's id and its
// action's id lowercase (it wrote `uuidString.lowercased()`), titles and items uppercase. The
// generated type would write the id uppercase, so this shadows it.
type planJSON struct {
	api.AgentPlan
	Id string `json:"id"` //nolint:revive // mirrors the generated field
}

func planDTO(p plans.Plan) planJSON {
	out := api.AgentPlan{
		AgentName: p.AgentName, Status: api.AgentPlanStatus(p.Status), Summary: p.Summary,
		CreatedAt: apitime.From(p.CreatedAt), ExpiresAt: apitime.From(p.ExpiresAt),
	}
	out.Changes = make([]struct {
		LibraryItemId *string       `json:"libraryItemId,omitempty"` //nolint:revive // generated shape
		PosterUrl     *string       `json:"posterUrl,omitempty"`     //nolint:revive // generated shape
		Text          string        `json:"text"`
		Title         string        `json:"title"`
		TitleId       apiid.UUID    `json:"titleId"` //nolint:revive // generated shape
		Type          api.MediaType `json:"type"`
	}, len(p.Changes))
	for i, c := range p.Changes {
		line := &out.Changes[i]
		line.Text, line.Title, line.TitleId, line.Type, line.PosterUrl = c.Text, c.Title, apiid.From(c.TitleID), api.MediaType(c.Type), c.PosterURL
		if c.LibraryItemID != nil {
			id := apiid.From(*c.LibraryItemID).String()
			line.LibraryItemId = &id
		}
	}
	out.Counts.Adds, out.Counts.Updates, out.Counts.Removes, out.Counts.Episodes =
		p.Counts.Adds, p.Counts.Updates, p.Counts.Removes, p.Counts.Episodes
	if p.DecidedAt != nil {
		t := apitime.From(*p.DecidedAt)
		out.DecidedAt = &t
	}
	if p.ActionID != nil {
		id := strings.ToLower(p.ActionID.String())
		out.ActionId = &id
	}
	return planJSON{AgentPlan: out, Id: strings.ToLower(p.ID.String())}
}

// writeJSON answers as the generated responses do.
func writeJSON(w http.ResponseWriter, v any) error {
	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(v); err != nil {
		return err
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, err := buf.WriteTo(w)
	return err
}

type planResponse planJSON

func (r planResponse) VisitGetPlanResponse(w http.ResponseWriter) error  { return writeJSON(w, planJSON(r)) }
func (r planResponse) VisitDenyPlanResponse(w http.ResponseWriter) error { return writeJSON(w, planJSON(r)) }

type planListResponse struct {
	Items []planJSON `json:"items"`
}

func (r planListResponse) VisitListPlansResponse(w http.ResponseWriter) error { return writeJSON(w, r) }

type planApproveResponse struct {
	Action api.Action `json:"action"`
	Plan   planJSON   `json:"plan"`
}

func (r planApproveResponse) VisitApprovePlanResponse(w http.ResponseWriter) error {
	return writeJSON(w, r)
}
