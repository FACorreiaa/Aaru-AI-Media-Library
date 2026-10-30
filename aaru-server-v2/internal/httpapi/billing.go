package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/billing"
	"context"

	"github.com/google/uuid"
)

// BillingHandlers.swift: Aaru Plus (BIL-001…003).

func (s *Server) GetEntitlement(ctx context.Context, _ api.GetEntitlementRequestObject) (api.GetEntitlementResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	state, err := s.billingService().State(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetEntitlement200JSONResponse(entitlementDTO(state, userID)), nil
}

func (s *Server) RecordAppleTransaction(ctx context.Context, req api.RecordAppleTransactionRequestObject) (api.RecordAppleTransactionResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	state, err := s.billingService().RecordPurchase(ctx, req.Body.SignedTransaction, userID)
	if err != nil {
		return nil, err
	}
	return api.RecordAppleTransaction200JSONResponse(entitlementDTO(state, userID)), nil
}

// ReceiveAppleNotification is public: Apple reaches it without a session.
func (s *Server) ReceiveAppleNotification(ctx context.Context, req api.ReceiveAppleNotificationRequestObject) (api.ReceiveAppleNotificationResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	if err := s.billingService().Notify(ctx, req.Body.SignedPayload); err != nil {
		return nil, err
	}
	return api.ReceiveAppleNotification200Response{}, nil
}

func entitlementDTO(state billing.State, userID uuid.UUID) api.Entitlement {
	out := api.Entitlement{Plus: state.Plus != nil, AppAccountToken: apiid.From(userID)}
	if p := state.Plus; p != nil {
		out.ProductId = &p.ProductID
		if p.ExpiresAt != nil {
			t := apitime.From(*p.ExpiresAt)
			out.ExpiresAt = &t
		}
		sandbox := p.Environment != "Production"
		out.Sandbox = &sandbox
	}
	out.Capture.Used = state.CapturesUsed
	out.Capture.Limit = state.CaptureLimit
	out.Capture.ResetsAt = apitime.From(state.CapturesResetAt)
	return out
}

// billingService is the billing rules over this server's queries and Apple verifier.
func (s *Server) billingService() *billing.Service {
	return &billing.Service{Q: s.q, Apple: s.Apple}
}
