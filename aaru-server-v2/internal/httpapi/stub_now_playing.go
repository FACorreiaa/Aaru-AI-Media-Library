// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) RegisterLiveActivityToken(context.Context, api.RegisterLiveActivityTokenRequestObject) (api.RegisterLiveActivityTokenResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetNowPlaying(context.Context, api.GetNowPlayingRequestObject) (api.GetNowPlayingResponseObject, error) {
	return nil, errNotImplemented
}
