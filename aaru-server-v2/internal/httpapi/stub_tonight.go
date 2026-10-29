// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetTonight(context.Context, api.GetTonightRequestObject) (api.GetTonightResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ClearTonightFeedback(context.Context, api.ClearTonightFeedbackRequestObject) (api.ClearTonightFeedbackResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SendTonightFeedback(context.Context, api.SendTonightFeedbackRequestObject) (api.SendTonightFeedbackResponseObject, error) {
	return nil, errNotImplemented
}
