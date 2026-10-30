package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/social"
	"context"

	"github.com/google/uuid"
)

// InviteHandlers.swift: SOC-002 friend invite links.

// ListFriendInvites lists the viewer's open invites.
func (s *Server) ListFriendInvites(ctx context.Context, _ api.ListFriendInvitesRequestObject) (api.ListFriendInvitesResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	invites, err := s.Social.OpenInvites(ctx, viewer)
	if err != nil {
		return nil, err
	}
	items := make([]api.FriendInvite, 0, len(invites))
	for _, i := range invites {
		items = append(items, s.friendInviteDTO(i.Invite, i.Title))
	}
	return api.ListFriendInvites200JSONResponse(api.FriendInviteList{Items: items}), nil
}

// CreateFriendInvite makes a link, optionally carrying one title.
func (s *Server) CreateFriendInvite(ctx context.Context, req api.CreateFriendInviteRequestObject) (api.CreateFriendInviteResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	var ref *core.MediaRef
	if req.Body.Title != nil {
		r := MediaRefFromAPI(*req.Body.Title)
		ref = &r
	}
	invite, title, err := s.Social.CreateInvite(ctx, viewer, ref)
	if err != nil {
		return nil, err
	}
	return api.CreateFriendInvite200JSONResponse(s.friendInviteDTO(invite, title)), nil
}

// RevokeFriendInvite revokes one of the viewer's open invites.
func (s *Server) RevokeFriendInvite(ctx context.Context, req api.RevokeFriendInviteRequestObject) (api.RevokeFriendInviteResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Social.RevokeInvite(ctx, req.Code, viewer); err != nil {
		return nil, err
	}
	return api.RevokeFriendInvite204Response{}, nil
}

// RedeemFriendInvite accepts an invite.
func (s *Server) RedeemFriendInvite(ctx context.Context, req api.RedeemFriendInviteRequestObject) (api.RedeemFriendInviteResponseObject, error) {
	viewer, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	friend, added, err := s.Social.RedeemInvite(ctx, req.Code, viewer, req.Body.AddTitle)
	if err != nil {
		return nil, err
	}
	return api.RedeemFriendInvite200JSONResponse(api.InviteRedemption{Friend: SocialUserDTO(friend), TitleAdded: added}), nil
}

// GetInvitePreview is public: what the link shows, signed in or out.
func (s *Server) GetInvitePreview(ctx context.Context, req api.GetInvitePreviewRequestObject) (api.GetInvitePreviewResponseObject, error) {
	var viewer *uuid.UUID
	if id, ok := reqctx.UserID(ctx); ok {
		viewer = &id
	}
	preview, err := s.Social.PreviewInvite(ctx, req.Code, viewer, reqctx.ClientAddress(ctx))
	if err != nil {
		return nil, err
	}
	// The preview is public: the inviter's avatar stays behind sign-in (SOC-001b).
	inviter := SocialUserDTO(preview.Inviter)
	inviter.AvatarUrl = nil
	out := api.InvitePreview{Inviter: inviter, ExpiresAt: apitime.From(preview.Invite.ExpiresAt)}
	if preview.Title != nil {
		title := TitleSummaryDTO(*preview.Title)
		out.Title = &title
	}
	if preview.Relationship != nil {
		rel := api.InvitePreviewRelationship(*preview.Relationship)
		out.Relationship = &rel
	}
	return api.GetInvitePreview200JSONResponse(out), nil
}

func (s *Server) friendInviteDTO(i social.Invite, title *core.Title) api.FriendInvite {
	out := api.FriendInvite{
		Code: i.Code, Url: s.Social.InviteURL(i), CreatedAt: apitime.From(i.CreatedAt), ExpiresAt: apitime.From(i.ExpiresAt),
	}
	if title != nil {
		summary := TitleSummaryDTO(*title)
		out.Title = &summary
	}
	return out
}
