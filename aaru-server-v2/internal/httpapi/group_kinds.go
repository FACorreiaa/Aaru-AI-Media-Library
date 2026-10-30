package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/groups"
	"context"
	"time"

	"github.com/google/uuid"
)

// Title, shelf and watch channels (API/GroupHandlers+Kinds.swift, GRP-007…GRP-009).

// UpdateMyMembership is PATCH /v1/groups/{groupId}/me: share progress, mute alerts.
func (s *Server) UpdateMyMembership(ctx context.Context, req api.UpdateMyMembershipRequestObject) (api.UpdateMyMembershipResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	summary, err := s.Groups.UpdateMembership(ctx, req.GroupId.ID(), req.Body.ShareProgress, req.Body.Muted, user)
	if err != nil {
		return nil, err
	}
	return api.UpdateMyMembership200JSONResponse(groupSummaryDTO(summary)), nil
}

// GetChannelProgress is GET …/channels/{channelId}/progress: a title channel's header.
func (s *Server) GetChannelProgress(ctx context.Context, req api.GetChannelProgressRequestObject) (api.GetChannelProgressResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	progress, err := s.Groups.TitleProgress(ctx, req.GroupId.ID(), req.ChannelId.ID(), user)
	if err != nil {
		return nil, err
	}
	me, err := s.Groups.Social.User(ctx, user)
	if err != nil {
		return nil, err
	}
	dto := api.ChannelProgress{Title: TitleSummaryDTO(progress.Title), Members: make([]api.MemberProgress, len(progress.Members))}
	if me != nil {
		mine := memberProgressDTO(groups.MemberProgress{User: *me, Progress: progress.Mine})
		dto.Mine = &mine
	}
	for i, m := range progress.Members {
		dto.Members[i] = memberProgressDTO(m)
	}
	return api.GetChannelProgress200JSONResponse(dto), nil
}

// ListChannelItems is GET …/channels/{channelId}/items: a shelf's titles.
func (s *Server) ListChannelItems(ctx context.Context, req api.ListChannelItemsRequestObject) (api.ListChannelItemsResponseObject, error) {
	list, err := s.shelf(ctx, req.GroupId.ID(), req.ChannelId.ID())
	if err != nil {
		return nil, err
	}
	return api.ListChannelItems200JSONResponse(list), nil
}

// AddChannelItem is POST …/channels/{channelId}/items.
func (s *Server) AddChannelItem(ctx context.Context, req api.AddChannelItemRequestObject) (api.AddChannelItemResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if _, err := s.Groups.AddToShelf(ctx, req.GroupId.ID(), req.ChannelId.ID(), MediaRefFromAPI(req.Body.Title), user); err != nil {
		return nil, err
	}
	list, err := s.shelf(ctx, req.GroupId.ID(), req.ChannelId.ID())
	if err != nil {
		return nil, err
	}
	return api.AddChannelItem200JSONResponse(list), nil
}

// RemoveChannelItem is DELETE …/channels/{channelId}/items/{titleId}.
func (s *Server) RemoveChannelItem(ctx context.Context, req api.RemoveChannelItemRequestObject) (api.RemoveChannelItemResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	title := req.TitleId.ID()
	if title == uuid.Nil {
		return nil, apperr.NotFound("That title is not on this shelf.")
	}
	if err := s.Groups.RemoveFromShelf(ctx, req.GroupId.ID(), req.ChannelId.ID(), title, user); err != nil {
		return nil, err
	}
	return api.RemoveChannelItem204Response{}, nil
}

// GetWatchParty is GET …/channels/{channelId}/party: the newest party, or none yet.
func (s *Server) GetWatchParty(ctx context.Context, req api.GetWatchPartyRequestObject) (api.GetWatchPartyResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	found, err := s.Groups.Party(ctx, req.GroupId.ID(), req.ChannelId.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.GetWatchParty200JSONResponse(partyViewDTO(found)), nil
}

// OpenWatchParty is POST …/channels/{channelId}/party.
func (s *Server) OpenWatchParty(ctx context.Context, req api.OpenWatchPartyRequestObject) (api.OpenWatchPartyResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var episode *groups.EpisodePoint
	if req.Body.Season != nil && req.Body.Episode != nil {
		episode = &groups.EpisodePoint{Season: *req.Body.Season, Episode: *req.Body.Episode}
	}
	found, err := s.Groups.OpenParty(ctx, req.GroupId.ID(), req.ChannelId.ID(), MediaRefFromAPI(req.Body.Title), episode, user)
	if err != nil {
		return nil, err
	}
	return api.OpenWatchParty200JSONResponse(partyViewDTO(&found)), nil
}

// SetWatchPartyReady is PUT …/party/ready.
func (s *Server) SetWatchPartyReady(ctx context.Context, req api.SetWatchPartyReadyRequestObject) (api.SetWatchPartyReadyResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	found, err := s.Groups.SetReady(ctx, req.GroupId.ID(), req.ChannelId.ID(), req.Body.Ready, user)
	if err != nil {
		return nil, err
	}
	return api.SetWatchPartyReady200JSONResponse(partyViewDTO(&found)), nil
}

// StartWatchParty is POST …/party/start: the countdown, from an optional body.
func (s *Server) StartWatchParty(ctx context.Context, req api.StartWatchPartyRequestObject) (api.StartWatchPartyResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	var seconds *int
	if req.Body != nil {
		seconds = req.Body.CountdownSeconds
	}
	found, err := s.Groups.StartCountdown(ctx, req.GroupId.ID(), req.ChannelId.ID(), seconds, user)
	if err != nil {
		return nil, err
	}
	return api.StartWatchParty200JSONResponse(partyViewDTO(&found)), nil
}

// EndWatchParty is POST …/party/end.
func (s *Server) EndWatchParty(ctx context.Context, req api.EndWatchPartyRequestObject) (api.EndWatchPartyResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	found, err := s.Groups.EndParty(ctx, req.GroupId.ID(), req.ChannelId.ID(), user)
	if err != nil {
		return nil, err
	}
	return api.EndWatchParty200JSONResponse(partyViewDTO(&found)), nil
}

// MarkWatchPartyWatched is POST …/party/watched: the viewer's own library only.
func (s *Server) MarkWatchPartyWatched(ctx context.Context, req api.MarkWatchPartyWatchedRequestObject) (api.MarkWatchPartyWatchedResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Groups.MarkWatched(ctx, req.GroupId.ID(), req.ChannelId.ID(), user); err != nil {
		return nil, err
	}
	return api.MarkWatchPartyWatched204Response{}, nil
}

func (s *Server) shelf(ctx context.Context, group, channel uuid.UUID) (api.ChannelItemList, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return api.ChannelItemList{}, err
	}
	entries, err := s.Groups.Shelf(ctx, group, channel, user)
	if err != nil {
		return api.ChannelItemList{}, err
	}
	items := make([]api.ChannelItem, len(entries))
	for i, e := range entries {
		item := api.ChannelItem{Title: TitleSummaryDTO(e.Title), AddedAt: apitime.From(e.Item.AddedAt)}
		if e.Item.AddedBy != nil {
			by := SocialUserDTO(*e.Item.AddedBy)
			item.AddedBy = &by
		}
		if e.Item.MyStatus != nil {
			status := api.LibraryStatus(*e.Item.MyStatus)
			item.MyStatus = &status
		}
		items[i] = item
	}
	return api.ChannelItemList{Items: items}, nil
}

func memberProgressDTO(m groups.MemberProgress) api.MemberProgress {
	dto := api.MemberProgress{User: SocialUserDTO(m.User)}
	if p := m.Progress; p != nil {
		status := api.LibraryStatus(p.Status)
		dto.Status = &status
		if p.Furthest != nil {
			season, episode := p.Furthest.Season, p.Furthest.Episode
			dto.Season, dto.Episode = &season, &episode
		}
	}
	return dto
}

func partyViewDTO(found *groups.Party) api.WatchPartyView {
	now := time.Now()
	view := api.WatchPartyView{ServerTime: apitime.From(now)}
	if found == nil {
		return view
	}
	p := found.Party
	party := api.WatchParty{
		Id: apiid.From(p.ID), Title: TitleSummaryDTO(found.Title), State: api.WatchPartyState(p.State(now)),
		StartsAt: apitime.PtrOrNil(p.StartsAt), EndedAt: apitime.PtrOrNil(p.EndedAt), Ready: SocialUserDTOs(p.Ready),
	}
	if p.Episode != nil {
		season, episode := p.Episode.Season, p.Episode.Episode
		party.Season, party.Episode = &season, &episode
	}
	if p.CreatedBy != nil {
		host := SocialUserDTO(*p.CreatedBy)
		party.Host = &host
	}
	view.Party = &party
	return view
}
