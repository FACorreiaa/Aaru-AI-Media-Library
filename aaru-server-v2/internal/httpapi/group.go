package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/groups"
	"context"

	"github.com/google/uuid"
)

// Group routes (API/GroupHandlers.swift). A malformed path id reads as uuid.Nil, which no row
// has, so it answers the route's own 404 ("No such group.", "No such channel.", …).

var errNoSuchUser = apperr.NotFound("No one has that handle.")

// ListGroups is GET /v1/groups.
func (s *Server) ListGroups(ctx context.Context, _ api.ListGroupsRequestObject) (api.ListGroupsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	found, err := s.Groups.Groups(ctx, user)
	if err != nil {
		return nil, err
	}
	items := make([]api.GroupSummary, len(found))
	for i, g := range found {
		items[i] = groupSummaryDTO(g)
	}
	return api.ListGroups200JSONResponse(api.GroupList{Items: items}), nil
}

// CreateGroup is POST /v1/groups.
func (s *Server) CreateGroup(ctx context.Context, req api.CreateGroupRequestObject) (api.CreateGroupResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Groups.Create(ctx, req.Body.Name, user)
	if err != nil {
		return nil, err
	}
	return api.CreateGroup200JSONResponse(groupDetailDTO(detail)), nil
}

// GetGroup is GET /v1/groups/{groupId}.
func (s *Server) GetGroup(ctx context.Context, req api.GetGroupRequestObject) (api.GetGroupResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Groups.Detail(ctx, req.GroupId.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.GetGroup200JSONResponse(groupDetailDTO(detail)), nil
}

// UpdateGroup is PATCH /v1/groups/{groupId}: rename.
func (s *Server) UpdateGroup(ctx context.Context, req api.UpdateGroupRequestObject) (api.UpdateGroupResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.Groups.Rename(ctx, req.GroupId.ID(), req.Body.Name, user)
	if err != nil {
		return nil, err
	}
	return api.UpdateGroup200JSONResponse(groupDetailDTO(detail)), nil
}

// DeleteGroup is DELETE /v1/groups/{groupId}.
func (s *Server) DeleteGroup(ctx context.Context, req api.DeleteGroupRequestObject) (api.DeleteGroupResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.Delete(ctx, req.GroupId.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteGroup204Response{}, nil
}

// UpdateGroupMember is PATCH /v1/groups/{groupId}/members/{userId}: admin or member.
func (s *Server) UpdateGroupMember(ctx context.Context, req api.UpdateGroupMemberRequestObject) (api.UpdateGroupMemberResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	role := groups.RoleMember
	if req.Body.Role == api.GroupMemberUpdateRoleAdmin {
		role = groups.RoleAdmin
	}
	if err := s.Groups.SetRole(ctx, req.GroupId.ID(), req.UserId.ID(), role, user); err != nil {
		return nil, err
	}
	return api.UpdateGroupMember204Response{}, nil
}

// RemoveGroupMember is DELETE /v1/groups/{groupId}/members/{userId}; yourself is leaving.
func (s *Server) RemoveGroupMember(ctx context.Context, req api.RemoveGroupMemberRequestObject) (api.RemoveGroupMemberResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.Remove(ctx, req.GroupId.ID(), req.UserId.ID(), user); err != nil {
		return nil, err
	}
	return api.RemoveGroupMember204Response{}, nil
}

// TransferGroup is POST /v1/groups/{groupId}/transfer.
func (s *Server) TransferGroup(ctx context.Context, req api.TransferGroupRequestObject) (api.TransferGroupResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.Transfer(ctx, req.GroupId.ID(), req.Body.UserId.ID(), user); err != nil {
		return nil, err
	}
	return api.TransferGroup204Response{}, nil
}

// InviteToGroup is POST /v1/groups/{groupId}/invites.
func (s *Server) InviteToGroup(ctx context.Context, req api.InviteToGroupRequestObject) (api.InviteToGroupResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	invitee := req.Body.UserId.ID()
	if invitee == uuid.Nil {
		return nil, errNoSuchUser
	}
	if err := s.Groups.Invite(ctx, req.GroupId.ID(), invitee, user); err != nil {
		return nil, err
	}
	return api.InviteToGroup204Response{}, nil
}

// ListGroupInvites is GET /v1/groups/invites: invites waiting for the viewer.
func (s *Server) ListGroupInvites(ctx context.Context, _ api.ListGroupInvitesRequestObject) (api.ListGroupInvitesResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	invites, err := s.Groups.Invites(ctx, user)
	if err != nil {
		return nil, err
	}
	items := make([]api.GroupInvite, len(invites))
	for i, inv := range invites {
		items[i] = api.GroupInvite{
			Id: apiid.From(inv.ID), GroupId: apiid.From(inv.GroupID), GroupName: inv.GroupName,
			Inviter: groupUserDTO(inv.Inviter), CreatedAt: apitime.From(inv.CreatedAt),
		}
	}
	return api.ListGroupInvites200JSONResponse(api.GroupInviteList{Items: items}), nil
}

// AcceptGroupInvite is POST /v1/groups/invites/{id}/accept.
func (s *Server) AcceptGroupInvite(ctx context.Context, req api.AcceptGroupInviteRequestObject) (api.AcceptGroupInviteResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	summary, err := s.Groups.Accept(ctx, req.Id.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.AcceptGroupInvite200JSONResponse(groupSummaryDTO(summary)), nil
}

// DeclineGroupInvite is DELETE /v1/groups/invites/{id}: decline one, or cancel one you sent.
func (s *Server) DeclineGroupInvite(ctx context.Context, req api.DeclineGroupInviteRequestObject) (api.DeclineGroupInviteResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.Decline(ctx, req.Id.ID(), user); err != nil {
		return nil, err
	}
	return api.DeclineGroupInvite204Response{}, nil
}

// CreateChannel is POST /v1/groups/{groupId}/channels.
func (s *Server) CreateChannel(ctx context.Context, req api.CreateChannelRequestObject) (api.CreateChannelResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	kind := groups.KindText
	if req.Body.Kind != nil {
		kind = groups.ChannelKind(*req.Body.Kind)
	}
	var ref *core.MediaRef
	if req.Body.Title != nil {
		r := MediaRefFromAPI(*req.Body.Title)
		ref = &r
	}
	channel, err := s.Groups.CreateChannel(ctx, req.GroupId.ID(), kind, req.Body.Name, req.Body.Topic, ref, user)
	if err != nil {
		return nil, err
	}
	dto, err := s.channelDTO(ctx, channel)
	if err != nil {
		return nil, err
	}
	return api.CreateChannel200JSONResponse(dto), nil
}

// UpdateChannel is PATCH /v1/groups/{groupId}/channels/{channelId}.
func (s *Server) UpdateChannel(ctx context.Context, req api.UpdateChannelRequestObject) (api.UpdateChannelResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	channel, err := s.Groups.UpdateChannel(ctx, req.GroupId.ID(), req.ChannelId.ID(), req.Body.Name, req.Body.Topic, user)
	if err != nil {
		return nil, err
	}
	dto, err := s.channelDTO(ctx, channel)
	if err != nil {
		return nil, err
	}
	return api.UpdateChannel200JSONResponse(dto), nil
}

// DeleteChannel is DELETE /v1/groups/{groupId}/channels/{channelId}.
func (s *Server) DeleteChannel(ctx context.Context, req api.DeleteChannelRequestObject) (api.DeleteChannelResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.DeleteChannel(ctx, req.GroupId.ID(), req.ChannelId.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteChannel204Response{}, nil
}

// ListMessages is GET /v1/groups/{groupId}/channels/{channelId}/messages.
func (s *Server) ListMessages(ctx context.Context, req api.ListMessagesRequestObject) (api.ListMessagesResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	cursor := groups.Cursor{Kind: groups.CursorLatest}
	switch {
	case req.Params.Before != nil:
		cursor = groups.Cursor{Kind: groups.CursorBefore, ID: req.Params.Before.ID()}
	case req.Params.After != nil:
		cursor = groups.Cursor{Kind: groups.CursorAfter, ID: req.Params.After.ID()}
	}
	if cursor.Kind != groups.CursorLatest && cursor.ID == uuid.Nil {
		return nil, groups.ErrNoSuchMessage
	}
	page, err := s.Groups.Messages(ctx, req.GroupId.ID(), req.ChannelId.ID(), cursor, req.Params.Limit, user)
	if err != nil {
		return nil, err
	}
	items := make([]api.GroupMessage, len(page.Messages))
	for i, m := range page.Messages {
		fromBlocked := m.Author != nil && page.Blocked[m.Author.ID]
		items[i] = GroupMessageDTO(m, fromBlocked, user, page.Veiled[m.ID])
	}
	return api.ListMessages200JSONResponse(api.GroupMessagePage{Items: items}), nil
}

// PostMessage is POST /v1/groups/{groupId}/channels/{channelId}/messages.
func (s *Server) PostMessage(ctx context.Context, req api.PostMessageRequestObject) (api.PostMessageResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	choice, err := spoilerChoice(req.Body.Spoiler, req.Body.SpoilerFree)
	if err != nil {
		return nil, err
	}
	m, err := s.Groups.Post(ctx, req.GroupId.ID(), req.ChannelId.ID(), req.Body.Body, req.Body.ClientNonce, choice, user)
	if err != nil {
		return nil, err
	}
	return api.PostMessage200JSONResponse(GroupMessageDTO(m, false, user, false)), nil
}

// EditMessage is PATCH /v1/groups/{groupId}/channels/{channelId}/messages/{messageId}.
func (s *Server) EditMessage(ctx context.Context, req api.EditMessageRequestObject) (api.EditMessageResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	m, err := s.Groups.Edit(ctx, req.GroupId.ID(), req.ChannelId.ID(), req.MessageId.ID(), req.Body.Body, user)
	if err != nil {
		return nil, err
	}
	return api.EditMessage200JSONResponse(GroupMessageDTO(m, false, user, false)), nil
}

// DeleteMessage is DELETE /v1/groups/{groupId}/channels/{channelId}/messages/{messageId}.
func (s *Server) DeleteMessage(ctx context.Context, req api.DeleteMessageRequestObject) (api.DeleteMessageResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.DeleteMessage(ctx, req.GroupId.ID(), req.ChannelId.ID(), req.MessageId.ID(), user); err != nil {
		return nil, err
	}
	return api.DeleteMessage204Response{}, nil
}

// MarkChannelRead is POST /v1/groups/{groupId}/channels/{channelId}/read.
func (s *Server) MarkChannelRead(ctx context.Context, req api.MarkChannelReadRequestObject) (api.MarkChannelReadResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.MarkRead(ctx, req.GroupId.ID(), req.ChannelId.ID(), req.Body.MessageId.ID(), user); err != nil {
		return nil, err
	}
	return api.MarkChannelRead204Response{}, nil
}

// MARK: DTOs

func groupSummaryDTO(g groups.Summary) api.GroupSummary {
	return api.GroupSummary{
		Id: apiid.From(g.ID), Name: g.Name, Role: api.GroupRole(g.Role), DefaultChannelId: apiid.From(g.DefaultChannelID),
		Unread: g.Unread, Mentions: g.Mentions, ShareProgress: g.ShareProgress, Muted: g.Muted,
	}
}

func channelDTOWith(c groups.Channel, title *core.Title) api.Channel {
	dto := api.Channel{
		Id: apiid.From(c.ID), Kind: api.ChannelKind(c.Kind), Name: c.Name, Topic: c.Topic, Position: c.Position,
		IsDefault: c.IsDefault, Unread: c.Unread, Mentions: c.Mentions,
	}
	if title != nil {
		t := TitleSummaryDTO(*title)
		dto.Title = &t
	}
	return dto
}

// channelDTO reads the title a title channel is about.
func (s *Server) channelDTO(ctx context.Context, c groups.Channel) (api.Channel, error) {
	var title *core.Title
	if c.TitleID != nil {
		t, err := s.Groups.Title(ctx, *c.TitleID)
		if err != nil {
			return api.Channel{}, err
		}
		title = t
	}
	return channelDTOWith(c, title), nil
}

func groupDetailDTO(d groups.Detail) api.GroupDetail {
	channels := make([]api.Channel, len(d.Channels))
	for i, c := range d.Channels {
		var title *core.Title
		if c.TitleID != nil {
			if t, ok := d.Titles[*c.TitleID]; ok {
				title = &t
			}
		}
		channels[i] = channelDTOWith(c, title)
	}
	members := make([]api.GroupMember, len(d.Members))
	for i, m := range d.Members {
		members[i] = api.GroupMember{
			User: groupUserDTO(m.User), Role: api.GroupRole(m.Role), JoinedAt: apitime.From(m.JoinedAt),
			ShareProgress: m.ShareProgress,
		}
	}
	return api.GroupDetail{
		Group: groupSummaryDTO(d.Summary), Channels: channels, Members: members, Invited: groupUsersDTO(d.Invited),
		Agent: d.Agent,
	}
}

// GroupMessageDTO is a message as one viewer sees it. The viewer sees the nonce only on their own
// messages, to match a pending send to its echo; the spoiler stamp says where the author is in
// the title, so only the author sees it, and readers learn only that it would spoil something.
func GroupMessageDTO(m groups.Message, fromBlocked bool, viewer uuid.UUID, veiled bool) api.GroupMessage {
	mine := m.Author != nil && m.Author.ID == viewer
	dto := api.GroupMessage{
		Id: apiid.From(m.ID), ChannelId: apiid.From(m.ChannelID), Body: m.Body, Mentions: apiid.Slice(m.Mentions),
		MentionsAgent: m.MentionsAgent, FromBlocked: fromBlocked, Deleted: m.DeletedAt != nil,
		CreatedAt: apitime.From(m.CreatedAt), Veiled: veiled, FromAgent: m.FromAgent, ReplyTo: apiid.PtrOrNil(m.ReplyTo),
	}
	if m.Author != nil {
		author := groupUserDTO(*m.Author)
		dto.Author = &author
	}
	if m.EditedAt != nil {
		t := apitime.From(*m.EditedAt)
		dto.EditedAt = &t
	}
	if mine {
		dto.ClientNonce = m.ClientNonce
		dto.Spoiler = spoilerStampDTO(m.Spoiler)
	}
	if len(m.Components) > 0 {
		cards := []api.MessageComponent{}
		for _, c := range m.Components {
			if c.Title != nil {
				cards = append(cards, api.MessageComponent{Type: api.MessageComponentTypeTitle, Title: TitleSummaryDTO(*c.Title)})
			}
		}
		dto.Components = &cards
	}
	return dto
}
