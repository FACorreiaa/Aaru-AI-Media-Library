// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) GetInvitePreview(context.Context, api.GetInvitePreviewRequestObject) (api.GetInvitePreviewResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListFriendInvites(context.Context, api.ListFriendInvitesRequestObject) (api.ListFriendInvitesResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) CreateFriendInvite(context.Context, api.CreateFriendInviteRequestObject) (api.CreateFriendInviteResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RevokeFriendInvite(context.Context, api.RevokeFriendInviteRequestObject) (api.RevokeFriendInviteResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RedeemFriendInvite(context.Context, api.RedeemFriendInviteRequestObject) (api.RedeemFriendInviteResponseObject, error) {
	return nil, errNotImplemented
}
