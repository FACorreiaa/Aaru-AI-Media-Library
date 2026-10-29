// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ReceiveAppleNotification(context.Context, api.ReceiveAppleNotificationRequestObject) (api.ReceiveAppleNotificationResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RecordAppleTransaction(context.Context, api.RecordAppleTransactionRequestObject) (api.RecordAppleTransactionResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetEntitlement(context.Context, api.GetEntitlementRequestObject) (api.GetEntitlementResponseObject, error) {
	return nil, errNotImplemented
}
