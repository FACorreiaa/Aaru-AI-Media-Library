package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/social"
	"context"

	"github.com/google/uuid"
)

// SocialHandlers.swift: handles, friend requests, friends, blocks and reports (SOC-001/002).

// UpdateProfile saves a handle and names. Absent keeps a field; an empty name clears it.
func (s *Server) UpdateProfile(ctx context.Context, req api.UpdateProfileRequestObject) (api.UpdateProfileResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	profile, err := s.Social.SaveProfile(ctx, user, social.ProfileChange{
		Handle: req.Body.Handle, FirstName: req.Body.FirstName, LastName: req.Body.LastName, DisplayName: req.Body.DisplayName,
	})
	if err != nil {
		return nil, err
	}
	return api.UpdateProfile200JSONResponse(MeDTO(profile)), nil
}

// GetSocialUser looks a user up by handle.
func (s *Server) GetSocialUser(ctx context.Context, req api.GetSocialUserRequestObject) (api.GetSocialUserResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	user, rel, err := s.Social.Lookup(ctx, req.Handle, viewer)
	if err != nil {
		return nil, err
	}
	return api.GetSocialUser200JSONResponse(socialUserView(user, rel)), nil
}

// ListFriendRequests lists incoming and outgoing requests.
func (s *Server) ListFriendRequests(ctx context.Context, _ api.ListFriendRequestsRequestObject) (api.ListFriendRequestsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	incoming, outgoing, err := s.Social.Requests(ctx, viewer)
	if err != nil {
		return nil, err
	}
	out := api.FriendRequests{Incoming: make([]api.FriendRequest, 0, len(incoming)), Outgoing: make([]api.FriendRequest, 0, len(outgoing))}
	for _, r := range incoming {
		out.Incoming = append(out.Incoming, api.FriendRequest{Id: apiid.From(r.ID), User: SocialUserDTO(r.Sender), CreatedAt: apitime.From(r.CreatedAt)})
	}
	for _, r := range outgoing {
		out.Outgoing = append(out.Outgoing, api.FriendRequest{Id: apiid.From(r.ID), User: SocialUserDTO(r.Recipient), CreatedAt: apitime.From(r.CreatedAt)})
	}
	return api.ListFriendRequests200JSONResponse(out), nil
}

// SendFriendRequest asks a user to be friends.
func (s *Server) SendFriendRequest(ctx context.Context, req api.SendFriendRequestRequestObject) (api.SendFriendRequestResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, rel, err := s.Social.SendRequest(ctx, viewer, req.Body.Handle)
	if err != nil {
		return nil, err
	}
	return api.SendFriendRequest200JSONResponse(socialUserView(user, rel)), nil
}

// WithdrawFriendRequest declines or cancels a request.
func (s *Server) WithdrawFriendRequest(ctx context.Context, req api.WithdrawFriendRequestRequestObject) (api.WithdrawFriendRequestResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Social.Withdraw(ctx, req.Id.ID(), viewer); err != nil {
		return nil, err
	}
	return api.WithdrawFriendRequest204Response{}, nil
}

// AcceptFriendRequest accepts a request and returns the new friend.
func (s *Server) AcceptFriendRequest(ctx context.Context, req api.AcceptFriendRequestRequestObject) (api.AcceptFriendRequestResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	friend, err := s.Social.Accept(ctx, req.Id.ID(), viewer)
	if err != nil {
		return nil, err
	}
	return api.AcceptFriendRequest200JSONResponse(SocialUserDTO(friend)), nil
}

// ListFriends lists the viewer's friends.
func (s *Server) ListFriends(ctx context.Context, _ api.ListFriendsRequestObject) (api.ListFriendsResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	friends, err := s.Social.Friends(ctx, viewer)
	if err != nil {
		return nil, err
	}
	return api.ListFriends200JSONResponse(api.SocialUserList{Items: SocialUserDTOs(friends)}), nil
}

// RemoveFriend ends a friendship.
func (s *Server) RemoveFriend(ctx context.Context, req api.RemoveFriendRequestObject) (api.RemoveFriendResponseObject, error) {
	viewer, target, err := s.socialTarget(ctx, req.UserId)
	if err != nil {
		return nil, err
	}
	if err := s.Social.Unfriend(ctx, target, viewer); err != nil {
		return nil, err
	}
	return api.RemoveFriend204Response{}, nil
}

// ListBlocks lists who the viewer blocked.
func (s *Server) ListBlocks(ctx context.Context, _ api.ListBlocksRequestObject) (api.ListBlocksResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	blocked, err := s.Social.Blocked(ctx, viewer)
	if err != nil {
		return nil, err
	}
	return api.ListBlocks200JSONResponse(api.SocialUserList{Items: SocialUserDTOs(blocked)}), nil
}

// BlockUser blocks a user.
func (s *Server) BlockUser(ctx context.Context, req api.BlockUserRequestObject) (api.BlockUserResponseObject, error) {
	viewer, target, err := s.socialTarget(ctx, req.UserId)
	if err != nil {
		return nil, err
	}
	if err := s.Social.Block(ctx, target, viewer); err != nil {
		return nil, err
	}
	return api.BlockUser204Response{}, nil
}

// UnblockUser removes a block.
func (s *Server) UnblockUser(ctx context.Context, req api.UnblockUserRequestObject) (api.UnblockUserResponseObject, error) {
	viewer, target, err := s.socialTarget(ctx, req.UserId)
	if err != nil {
		return nil, err
	}
	if err := s.Social.Unblock(ctx, target, viewer); err != nil {
		return nil, err
	}
	return api.UnblockUser204Response{}, nil
}

// ReportUser reports a user to Aaru.
func (s *Server) ReportUser(ctx context.Context, req api.ReportUserRequestObject) (api.ReportUserResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	viewer, target, err := s.socialTarget(ctx, req.Body.UserId)
	if err != nil {
		return nil, err
	}
	if err := s.Social.Report(ctx, target, social.ReportReason(req.Body.Reason), req.Body.Note, viewer); err != nil {
		return nil, err
	}
	return api.ReportUser204Response{}, nil
}

// socialTarget is the viewer and a user id from the request; a malformed id is the same 404 as nobody.
func (s *Server) socialTarget(ctx context.Context, id apiid.UUID) (viewer, target uuid.UUID, err error) {
	if viewer, err = currentUser(ctx); err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	if id.ID() == uuid.Nil {
		return uuid.Nil, uuid.Nil, social.ErrNoSuchUser
	}
	return viewer, id.ID(), nil
}

// SocialUserDTO is a social user on the wire (Components.Schemas.SocialUser), with their avatar.
// Groups and boards answer the same shape.
func SocialUserDTO(u social.User) api.SocialUser {
	out := api.SocialUser{UserId: apiid.From(u.ID), Handle: u.Handle, DisplayName: u.DisplayName}
	if u.AvatarVersion != nil {
		path := AvatarPath(u.ID, *u.AvatarVersion)
		out.AvatarUrl = &path
	}
	return out
}

// SocialUserDTOs maps a list of users.
func SocialUserDTOs(users []social.User) []api.SocialUser {
	out := make([]api.SocialUser, 0, len(users))
	for _, u := range users {
		out = append(out, SocialUserDTO(u))
	}
	return out
}

func socialUserView(u social.User, rel social.Relationship) api.SocialUserView {
	return api.SocialUserView{User: SocialUserDTO(u), Relationship: api.SocialUserViewRelationship(rel)}
}
