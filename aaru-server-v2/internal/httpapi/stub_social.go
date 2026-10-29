// Placeholders until the real handlers land. Delete a method here when its handler is written.

package httpapi

import (
	"aaru-go-api/internal/api"
	"context"
)

func (s *Server) UpdateProfile(context.Context, api.UpdateProfileRequestObject) (api.UpdateProfileResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListBlocks(context.Context, api.ListBlocksRequestObject) (api.ListBlocksResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) UnblockUser(context.Context, api.UnblockUserRequestObject) (api.UnblockUserResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) BlockUser(context.Context, api.BlockUserRequestObject) (api.BlockUserResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListFriendRequests(context.Context, api.ListFriendRequestsRequestObject) (api.ListFriendRequestsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) SendFriendRequest(context.Context, api.SendFriendRequestRequestObject) (api.SendFriendRequestResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) WithdrawFriendRequest(context.Context, api.WithdrawFriendRequestRequestObject) (api.WithdrawFriendRequestResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) AcceptFriendRequest(context.Context, api.AcceptFriendRequestRequestObject) (api.AcceptFriendRequestResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ListFriends(context.Context, api.ListFriendsRequestObject) (api.ListFriendsResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) RemoveFriend(context.Context, api.RemoveFriendRequestObject) (api.RemoveFriendResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) ReportUser(context.Context, api.ReportUserRequestObject) (api.ReportUserResponseObject, error) {
	return nil, errNotImplemented
}

func (s *Server) GetSocialUser(context.Context, api.GetSocialUserRequestObject) (api.GetSocialUserResponseObject, error) {
	return nil, errNotImplemented
}
