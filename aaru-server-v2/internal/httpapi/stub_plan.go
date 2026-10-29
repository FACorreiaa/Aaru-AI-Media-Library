// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListPlans(context.Context, api.ListPlansRequestObject) (api.ListPlansResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetPlan(context.Context, api.GetPlanRequestObject) (api.GetPlanResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ApprovePlan(context.Context, api.ApprovePlanRequestObject) (api.ApprovePlanResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) DenyPlan(context.Context, api.DenyPlanRequestObject) (api.DenyPlanResponseObject, error) {
	return nil, errNotImplemented
}
