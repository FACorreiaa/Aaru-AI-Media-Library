// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) ListFriendActivity(context.Context, api.ListFriendActivityRequestObject) (api.ListFriendActivityResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSocialSettings(context.Context, api.GetSocialSettingsRequestObject) (api.GetSocialSettingsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UpdateSocialSettings(context.Context, api.UpdateSocialSettingsRequestObject) (api.UpdateSocialSettingsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetFriendProfile(context.Context, api.GetFriendProfileRequestObject) (api.GetFriendProfileResponseObject, error) {
	return nil, errNotImplemented
}
